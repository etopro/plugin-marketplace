#!/usr/bin/env bash
# Hourly controller. Keeps the one-shot scheduled ping cron aligned with the
# current Claude limit window; if the target is already missed, runs recovery.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PING_SCRIPT="${PLUGIN_ROOT}/scripts/ping.sh"

DATA_DIR="${HOME}/.claude/claude-tools"
LOG="${DATA_DIR}/ping.log"
STATE="${DATA_DIR}/state.json"
mkdir -p "$DATA_DIR"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] controller: %s\n' "$(ts)" "$*" >> "$LOG"; }

# Self-heal: there is no plugin-uninstall hook in Claude Code, so a removed
# plugin leaves these cron entries orphaned — they then fail hourly with
# "No such file or directory" forever (and spam the local mailbox). The
# controller is the only piece of us that still runs after removal, so it
# checks whether its sibling ping.sh is still on disk. If not, the plugin is
# gone (or moved): tear down the whole claude-tools cron block (including this
# controller entry) and exit.
if [ ! -f "$PING_SCRIPT" ]; then
    log "ping.sh not found at $PING_SCRIPT — plugin appears removed; self-removing cron"
    ct_self_remove_cron
    exit 0
fi

install_scheduled_ping() {
    local target=$1
    local claude_dir=${2:-}
    if [ -z "$claude_dir" ]; then
        if command -v claude >/dev/null 2>&1; then
            claude_dir=$(dirname "$(command -v claude)")
        else
            claude_dir="/usr/local/bin"
        fi
    fi

    local cron_expr path_line command existing filtered block final
    cron_expr=$(ct_cron_fields_for_epoch "$target")
    path_line="PATH=${claude_dir}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
    command="bash \"$PING_SCRIPT\" --target $target --reason scheduled"
    block=$(ct_build_block "$CT_PING_MARKER" "$path_line" "$cron_expr" "$command")

    if existing=$(crontab -l 2>/dev/null); then :; else existing=""; fi
    filtered=$(printf '%s' "$existing" | ct_filter_marker "$CT_PING_MARKER")
    final=$(printf '%s' "$filtered" | ct_compose_crontab "$block")
    printf '%s' "$final" | crontab -
    log "scheduled ping for $(ct_human_time "$target") (epoch=$target)"
}

ensure_scheduled_ping() {
    local target=$1
    local existing current_block desired_block claude_dir
    if existing=$(crontab -l 2>/dev/null); then :; else existing=""; fi
    current_block=$(printf '%s' "$existing" | ct_extract_marker "$CT_PING_MARKER")

    # Build the block we *would* install and compare against current. This
    # catches not just a stale target but also a stale PING_SCRIPT path or a
    # stale claude binary dir (e.g. plugin reinstalled at a different path).
    if command -v claude >/dev/null 2>&1; then
        claude_dir=$(dirname "$(command -v claude)")
    else
        claude_dir="/usr/local/bin"
    fi
    local cron_expr path_line command
    cron_expr=$(ct_cron_fields_for_epoch "$target")
    path_line="PATH=${claude_dir}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
    command="bash \"$PING_SCRIPT\" --target $target --reason scheduled"
    desired_block=$(ct_build_block "$CT_PING_MARKER" "$path_line" "$cron_expr" "$command")

    if [ "$current_block" = "$desired_block" ]; then
        log "scheduled ping already current: epoch=$target"
        return
    fi
    install_scheduled_ping "$target" "$claude_dir"
}

NOW=$(date +%s)
LAST=$(ct_state_get_last "$STATE")
DECISION=$(ct_decide "$NOW" "${LAST:-}")
ACTION=${DECISION%% *}
REASON=${DECISION#* }

log "decision: $ACTION ($REASON); now=$NOW last=${LAST:-none}"

if [ "$ACTION" = "ping" ]; then
    log "target missed or absent; running recovery ping"
    # --no-retry: the controller itself runs hourly, so the hourly cadence is
    # the external retry. Without --no-retry, a fast-failing claude (e.g.
    # unauthenticated) would block this call for ~4 hours via ping.sh's
    # internal retry chain — and freeze /claude-tools:install for that long.
    bash "$PING_SCRIPT" --no-retry --reason "recovery:${REASON}" || true
    LAST=$(ct_state_get_last "$STATE")
fi

TARGET=$(ct_next_target "${LAST:-}")
if [ -n "$TARGET" ]; then
    ensure_scheduled_ping "$TARGET"
else
    log "no successful ping yet; scheduled ping not created"
fi
