#!/usr/bin/env bash
# Show whether claude-tools cron entries are installed, the local state, and log.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

DATA_DIR="${HOME}/.claude/claude-tools"
LOG="${DATA_DIR}/ping.log"
STATE="${DATA_DIR}/state.json"

# --- crontab block ---
if existing=$(crontab -l 2>/dev/null); then
    blocks=$(printf '%s' "$existing" | ct_extract_blocks)
    if [ -n "$blocks" ]; then
        echo "claude-tools: INSTALLED"
        echo
        echo "Crontab blocks:"
        printf '%s\n' "$blocks" | sed 's/^/  /'
    else
        echo "claude-tools: NOT installed (no marker in crontab)."
    fi
else
    echo "claude-tools: NOT installed (no crontab)."
fi

# --- state ---
echo
echo "State: $STATE"
if [ -f "$STATE" ]; then
    last_ok=$(ct_state_get_last "$STATE")
    now=$(date +%s)
    if [ -n "$last_ok" ] && [ "$last_ok" -gt 0 ]; then
        elapsed=$((now - last_ok))
        ago=$(ct_humanize_seconds "$elapsed")
        last_human=$(date -r "$last_ok" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$last_ok" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "epoch=$last_ok")
        echo "  last successful ping: $last_human (${ago} ago)"
        next_decision=$(ct_decide "$now" "$last_ok")
        echo "  if cron ran now: $next_decision"
        next_target=$(ct_next_target "$last_ok")
        if [ -n "$next_target" ]; then
            echo "  next target ping: $(ct_human_time "$next_target")"
        fi
        remaining=$((CT_WINDOW_SEC - elapsed))
        if [ "$remaining" -gt 0 ]; then
            expires_at=$((last_ok + CT_WINDOW_SEC))
            expires_human=$(date -r "$expires_at" '+%H:%M' 2>/dev/null || date -d "@$expires_at" '+%H:%M' 2>/dev/null || echo "?")
            echo "  current window expires: $expires_human (in $(ct_humanize_seconds "$remaining"))"
        else
            echo "  current window: already expired ($(ct_humanize_seconds "$((-remaining))") ago)"
        fi
    else
        echo "  last_successful_ping: 0 (no successful ping yet)"
    fi
    if command -v jq >/dev/null 2>&1; then
        attempt=$(jq -r '.last_attempt_result // empty' "$STATE" 2>/dev/null)
        [ -n "$attempt" ] && echo "  last attempt result: $attempt"
    fi
else
    echo "  (state file does not exist yet)"
fi

# --- log ---
echo
echo "Log: $LOG"
if [ -f "$LOG" ]; then
    size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    echo "  size: ${size} bytes"
    echo "  last 10 lines:"
    tail -n 10 "$LOG" | sed 's/^/    /'
else
    echo "  (log file does not exist yet)"
fi
