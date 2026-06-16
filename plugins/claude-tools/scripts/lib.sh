#!/usr/bin/env bash
# Shared functions for claude-tools.
# Sourced by install.sh / controller.sh / uninstall.sh / status.sh / ping.sh and tests.
# No side effects on source — all functions are deterministic given their args.

CT_MARKER="claude-tools-marketplace"
CT_CONTROLLER_MARKER="${CT_MARKER}-controller"
CT_PING_MARKER="${CT_MARKER}-scheduled-ping"
CT_WINDOW_SEC=$((5 * 3600))   # Pro/Max 5-hour rolling window
CT_GUARD_SEC=$((15 * 60))     # min gap between pings (15 min)
CT_TARGET_OFFSET_SEC=20

# ct_decide <now_epoch> <last_ping_epoch_or_empty>
# Echoes "ping <reason>" or "skip <reason>".
ct_decide() {
    local now=$1
    local last=$2
    if [ -z "$last" ] || [ "$last" -le 0 ]; then
        echo "ping never_pinged"
        return
    fi
    local elapsed=$((now - last))
    if [ "$elapsed" -lt "$CT_GUARD_SEC" ]; then
        echo "skip too_soon_${elapsed}s"
        return
    fi
    local target=$((last + CT_WINDOW_SEC + CT_TARGET_OFFSET_SEC))
    local until_target=$((target - now))
    if [ "$until_target" -gt 0 ]; then
        echo "skip scheduled_in_${until_target}s"
        return
    fi
    echo "ping target_due_$((-until_target))s_ago"
}

# ct_state_get_last <state_file>
# Echoes the last_successful_ping value as stored (including "0"), or empty
# string if file/field is absent. Callers (ct_decide) treat "0" as never_pinged.
ct_state_get_last() {
    local file=$1
    [ -f "$file" ] || { echo ""; return; }
    if command -v jq >/dev/null 2>&1; then
        # `// empty` filters out null but keeps numeric 0.
        jq -r '.last_successful_ping // empty' "$file" 2>/dev/null
    else
        grep -o '"last_successful_ping"[[:space:]]*:[[:space:]]*[0-9]*' "$file" 2>/dev/null \
            | head -1 \
            | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/'
    fi
}

# ct_state_write <state_file> <last_successful> <last_attempt> <last_attempt_result>
# Atomically writes JSON state via tmp+mv. Empty last_successful is rendered as 0.
ct_state_write() {
    local file=$1
    local last_ok=${2:-0}
    local last_attempt=${3:-0}
    local result=${4:-unknown}
    [ -z "$last_ok" ] && last_ok=0
    local dir
    dir=$(dirname "$file")
    mkdir -p "$dir"
    local tmp="${file}.tmp.$$"
    cat >"$tmp" <<EOF
{
  "last_successful_ping": ${last_ok},
  "last_attempt": ${last_attempt},
  "last_attempt_result": "${result}"
}
EOF
    mv -f "$tmp" "$file"
}

ct_next_target() {
    local last=$1
    if [ -z "$last" ] || [ "$last" -le 0 ]; then
        echo ""
        return
    fi
    echo $((last + CT_WINDOW_SEC + CT_TARGET_OFFSET_SEC))
}

ct_cron_fields_for_epoch() {
    local epoch=$1
    local minute hour day month
    minute=$(date -r "$epoch" '+%M' 2>/dev/null || date -d "@$epoch" '+%M')
    hour=$(date -r "$epoch" '+%H' 2>/dev/null || date -d "@$epoch" '+%H')
    day=$(date -r "$epoch" '+%d' 2>/dev/null || date -d "@$epoch" '+%d')
    month=$(date -r "$epoch" '+%m' 2>/dev/null || date -d "@$epoch" '+%m')
    printf '%s %s %s %s *' "$((10#$minute))" "$((10#$hour))" "$((10#$day))" "$((10#$month))"
}

ct_human_time() {
    local epoch=$1
    date -r "$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
        || date -d "@$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
        || echo "epoch=$epoch"
}

# ct_filter_existing
# Reads a crontab dump from stdin, removes any claude-tools block(s),
# echoes the remainder. Safe on empty input.
ct_filter_existing() {
    awk -v marker="$CT_MARKER" '
        BEGIN { skip = 0 }
        {
            if (index($0, "# " marker) && index($0, " BEGIN")) { skip = 1; next }
            if (index($0, "# " marker) && index($0, " END"))   { skip = 0; next }
            if (skip) next
            if (index($0, "# " marker)) next
            print
        }
    '
}

# ct_self_remove_cron — remove every claude-tools block from the live crontab.
# Same marker-based filtering as uninstall.sh, factored out so the controller's
# self-heal path and the manual uninstall stay in lock-step. Safe when no
# crontab exists. If nothing else remains, drops the crontab entirely.
ct_self_remove_cron() {
    local existing filtered trimmed
    existing=$(crontab -l 2>/dev/null) || return 0
    filtered=$(printf '%s' "$existing" | ct_filter_existing)
    trimmed=$(printf '%s' "$filtered" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -z "$trimmed" ]; then
        crontab -r 2>/dev/null || true
    else
        printf '%s' "$filtered" | crontab -
    fi
}

ct_filter_marker() {
    local marker_name=$1
    awk -v marker="$marker_name" '
        BEGIN { skip = 0 }
        {
            if (index($0, "# " marker " BEGIN")) { skip = 1; next }
            if (index($0, "# " marker " END"))   { skip = 0; next }
            if (skip) next
            if (index($0, "# " marker)) next
            print
        }
    '
}

# ct_extract_blocks — prints all claude-tools blocks from stdin.
ct_extract_blocks() {
    awk -v marker="$CT_MARKER" '
        BEGIN { in_block = 0 }
        {
            if (index($0, "# " marker) && index($0, " BEGIN")) { in_block = 1; print; next }
            if (index($0, "# " marker) && index($0, " END"))   { print; in_block = 0; next }
            if (in_block) print
            else if (index($0, "# " marker))     print
        }
    '
}

ct_extract_marker() {
    local marker_name=$1
    awk -v marker="$marker_name" '
        BEGIN { in_block = 0 }
        {
            if (index($0, "# " marker " BEGIN")) { in_block = 1; print; next }
            if (index($0, "# " marker " END"))   { print; in_block = 0; next }
            if (in_block) print
            else if (index($0, "# " marker))     print
        }
    '
}

# ct_build_block <marker> <path-line> <cron-expr> <command>
# Echoes a full BEGIN..END marker block.
ct_build_block() {
    local marker_name=$1
    local path_line=$2
    local cron_expr=$3
    local command=$4
    cat <<EOF
# $marker_name BEGIN
$path_line
$cron_expr $command # $marker_name
# $marker_name END
EOF
}

# ct_compose_crontab <new-block-arg>  (existing crontab on stdin)
ct_compose_crontab() {
    local new_block=$1
    local existing
    existing=$(cat)
    if [ -n "$existing" ]; then
        printf '%s\n%s\n' "$existing" "$new_block"
    else
        printf '%s\n' "$new_block"
    fi
}

# ct_humanize_seconds <secs>  →  "1h 27m" or "5m" or "30s"
ct_humanize_seconds() {
    local s=$1
    [ "$s" -lt 0 ] && s=$((-s))
    local h=$((s / 3600))
    local m=$(((s % 3600) / 60))
    local sec=$((s % 60))
    if [ "$h" -gt 0 ]; then
        printf '%dh %dm' "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf '%dm' "$m"
    else
        printf '%ds' "$sec"
    fi
}
