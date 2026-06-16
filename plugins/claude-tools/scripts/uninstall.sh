#!/usr/bin/env bash
# Remove the claude-tools entries from the user's crontab.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; fi

if ! existing=$(crontab -l 2>/dev/null); then
    if [ "$dry_run" -eq 1 ]; then
        printf ''
        exit 0
    fi
    echo "claude-tools: no crontab found, nothing to remove."
    exit 0
fi

filtered=$(printf '%s' "$existing" | ct_filter_existing)
trimmed=$(printf '%s' "$filtered" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [ "$dry_run" -eq 1 ]; then
    printf '%s' "$filtered"
    exit 0
fi

# Same removal the controller does for self-heal; one shared code path.
ct_self_remove_cron
if [ -z "$trimmed" ]; then
    echo "claude-tools cron removed (crontab is now empty)."
else
    echo "claude-tools cron removed."
fi
