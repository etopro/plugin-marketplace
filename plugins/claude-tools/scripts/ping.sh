#!/usr/bin/env bash
# Scheduled/recovery ping runner. The controller decides when this should run;
# this script handles second-level waiting, retries, state, and logging.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

DATA_DIR="${CT_DATA_DIR:-${HOME}/.claude/claude-tools}"
LOG="${DATA_DIR}/ping.log"
STATE="${DATA_DIR}/state.json"
LOCK="${DATA_DIR}/ping.lock"
mkdir -p "$DATA_DIR"

TARGET=""
REASON="manual"
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            shift
            TARGET=${1:-}
            [ -n "$TARGET" ] || { echo "error: --target needs epoch seconds" >&2; exit 2; }
            shift
            ;;
        --reason)
            shift
            REASON=${1:-manual}
            shift
            ;;
        -h|--help)
            echo 'Usage: ping.sh [--target EPOCH] [--reason TEXT]'
            exit 0
            ;;
        *)
            echo "error: unknown arg: $1" >&2
            exit 2
            ;;
    esac
done

# Log rotation when >1 MB.
if [ -f "$LOG" ]; then
    size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt 1048576 ]; then
        mv -f "$LOG" "$LOG.1"
    fi
fi

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*" >> "$LOG"; }

# Concurrency lock. mkdir is atomic on POSIX filesystems.
# Stale locks (older than CT_LOCK_TTL_SEC) are reclaimed — guards against a
# crashed previous run that didn't get to run its EXIT trap.
CT_LOCK_TTL_SEC=$((270 * 60))   # 4h 30m

acquire_lock() {
    if mkdir "$LOCK" 2>/dev/null; then
        return 0
    fi
    # Lock exists. Check its age via the directory mtime.
    local lock_mtime now age
    lock_mtime=$(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - lock_mtime))
    if [ "$age" -gt "$CT_LOCK_TTL_SEC" ]; then
        log "stale lock (age=${age}s > ttl=${CT_LOCK_TTL_SEC}s), reclaiming"
        rmdir "$LOCK" 2>/dev/null || rm -rf "$LOCK"
        mkdir "$LOCK" 2>/dev/null || return 1
        return 0
    fi
    return 1
}

if ! acquire_lock; then
    log "another ping in progress, skipping (lock age within TTL)"
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

if [ -n "$TARGET" ]; then
    now=$(date +%s)
    wait_for=$((TARGET - now))
    if [ "$wait_for" -gt 0 ]; then
        sleep "$wait_for"
    fi
    drift=$(( $(date +%s) - TARGET ))
    log "target reached: epoch=$TARGET drift=${drift}s reason=${REASON}"
fi

if ! command -v claude >/dev/null 2>&1; then
    log "error: claude CLI not on PATH (PATH=${PATH})"
    ct_state_write "$STATE" "$(ct_state_get_last "$STATE")" "$(date +%s)" "error:no_claude"
    exit 0
fi

CT_PING_TIMEOUT=10
CT_PING_PROMPT="ping"

# Run a command with a timeout. Always returns rc=124 if the timeout fired,
# pass-through otherwise. Works on macOS (no GNU coreutils) and Linux.
run_with_timeout() {
    local secs=$1
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
        return $?
    fi
    # Bash fallback: run in background, watchdog kills via SIGTERM after deadline.
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) &
    local watcher=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    case "$rc" in
        143|137) return 124 ;;  # SIGTERM/SIGKILL ⇒ treat as timeout
        *) return "$rc" ;;
    esac
}

attempt_ping() {
    local label=$1
    local now last rc
    now=$(date +%s)
    last=$(ct_state_get_last "$STATE")
    log "pinging via claude -p \"${CT_PING_PROMPT}\" (${label}; reason=${REASON}; timeout=${CT_PING_TIMEOUT}s)"
    run_with_timeout "$CT_PING_TIMEOUT" claude -p "$CT_PING_PROMPT" >>"$LOG" 2>&1
    rc=$?
    # rc=0   → claude finished cleanly within timeout
    # rc=124 → timeout reached; the request reached the server (window started)
    #          and we don't actually need the response — that's success for us.
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
        log "ping ok (${label}; rc=${rc})"
        ct_state_write "$STATE" "$now" "$now" "ok:${REASON}:rc${rc}"
        return 0
    fi
    log "ping failed rc=${rc} (${label})"
    ct_state_write "$STATE" "${last:-0}" "$now" "error:rc${rc}:${REASON}"
    return 1
}

attempt_ping "initial" && exit 0

# Retry schedule:
#   - 5s, 15s    → transient hiccups
#   - 5×60s      → short network outage (~5 min)
#   - 4×3600s    → extended outage (~4 h, e.g. ISP problem, laptop offline)
# Total budget ~4 h 6 m. After that the next hourly controller pass reschedules.
for delay in 5 15 60 60 60 60 60 3600 3600 3600 3600; do
    log "retry in ${delay}s"
    sleep "$delay"
    attempt_ping "retry_${delay}s" && exit 0
done

exit 0
