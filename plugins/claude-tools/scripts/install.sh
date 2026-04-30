#!/usr/bin/env bash
# Install (or refresh) the claude-tools controller cron entry.
# The controller keeps a separate one-shot scheduled ping entry aligned with
# the current 5-hour window + 20 seconds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CONTROLLER_SCRIPT="${PLUGIN_ROOT}/scripts/controller.sh"

dry_run=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        -h|--help)
            cat <<EOF
Usage: install.sh [--dry-run]

Adds an hourly controller cron entry. The controller creates/refreshes a
separate scheduled ping entry for the detected limit window + 20 seconds.
EOF
            exit 0
            ;;
        *)
            echo "error: unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

if [ "$dry_run" -eq 0 ]; then
    if ! command -v claude >/dev/null 2>&1; then
        echo "error: claude CLI not found on PATH. Install Claude Code first." >&2
        exit 1
    fi
    CLAUDE_BIN=$(command -v claude)
    claude_dir=$(dirname "$CLAUDE_BIN")
else
    claude_dir="${CLAUDE_TOOLS_FAKE_CLAUDE_DIR:-/usr/local/bin}"
fi

if [ ! -f "$CONTROLLER_SCRIPT" ] && [ "$dry_run" -eq 0 ]; then
    echo "error: controller script not found at $CONTROLLER_SCRIPT" >&2
    exit 1
fi

cron_expr="0 * * * *"
path_line="PATH=${claude_dir}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
command="bash \"$CONTROLLER_SCRIPT\""
new_block=$(ct_build_block "$CT_CONTROLLER_MARKER" "$path_line" "$cron_expr" "$command")

existing=""
if existing=$(crontab -l 2>/dev/null); then :; else existing=""; fi
filtered=$(printf '%s' "$existing" | ct_filter_marker "$CT_CONTROLLER_MARKER")
final=$(printf '%s' "$filtered" | ct_compose_crontab "$new_block")

if [ "$dry_run" -eq 1 ]; then
    printf '%s' "$final"
    exit 0
fi

printf '%s' "$final" | crontab -
bash "$CONTROLLER_SCRIPT" || true

echo "claude-tools cron installed."
echo "  controller: $cron_expr"
echo "  controller: $CONTROLLER_SCRIPT"
echo "  ping:       scheduled by controller at window + 20 seconds"
echo "  state:      ${HOME}/.claude/claude-tools/state.json"
echo "  log file:   ${HOME}/.claude/claude-tools/ping.log"
