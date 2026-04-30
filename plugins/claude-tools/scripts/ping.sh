#!/usr/bin/env bash
# Scheduled/recovery ping runner. The controller decides when this should run;
# this script handles second-level waiting, retries, state, and logging.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

DATA_DIR="${HOME}/.claude/claude-tools"
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
if ! mkdir "$LOCK" 2>/dev/null; then
    log "another ping in progress, skipping"
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

run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 60 "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout 60 "$@"
    else
        perl -e 'alarm shift; exec @ARGV' 60 "$@"
    fi
}

attempt_ping() {
    local label=$1
    local now last rc
    now=$(date +%s)
    last=$(ct_state_get_last "$STATE")
    log "pinging via claude -p \"1\" (${label}; reason=${REASON})"
    if run_with_timeout claude -p "1" >>"$LOG" 2>&1; then
        log "ping ok (${label})"
        ct_state_write "$STATE" "$now" "$now" "ok:${REASON}"
        return 0
    fi
    rc=$?
    log "ping failed rc=${rc} (${label})"
    ct_state_write "$STATE" "${last:-0}" "$now" "error:rc${rc}:${REASON}"
    return 1
}

attempt_ping "initial" && exit 0

for delay in 10 30 60 300; do
    log "retry in ${delay}s"
    sleep "$delay"
    attempt_ping "retry_${delay}s" && exit 0
done

exit 0
