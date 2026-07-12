#!/usr/bin/env bash
# Bitwarden helpers for pat.
# Sourced by pat.sh. No side effects on source.
#
# Depends on: bw CLI (Bitwarden CLI), jq (optional, graceful grep fallback).
#
# PEM storage convention:
#   Item type : secure note
#   Name      : $PAT_BW_ITEM  (e.g. "github-app-axisrow")
#   Field     : $PAT_BW_FIELD (default "private-key")  → custom text field holding the PEM body.
#
# A custom field is chosen over an attachment because `bw get field` returns the
# value directly with no temp-file handling, keeping the key off disk.

PAT_BW_FIELD_DEFAULT="private-key"

# pat_bw_status  → echoes one of: unauthenticated | locked | unlocked
pat_bw_status() {
    bw status --raw 2>/dev/null | grep -o '"status":"[^"]*"' | sed 's/"status":"//;s/"//'
}

# pat_bw_ensure_unlocked
# If the vault is locked, prompt for the master password on the TTY and unlock.
# Exports BW_SESSION for the rest of the process. Returns non-zero on failure
# or if not logged in at all.
pat_bw_ensure_unlocked() {
    local status
    status=$(pat_bw_status)
    case "$status" in
        unlocked) return 0 ;;
        locked)
            local pw session
            printf 'Bitwarden vault is locked. Master password: ' >/dev/tty
            read -rs pw </dev/tty
            printf '\n' >/dev/tty
            if [ -z "$pw" ]; then
                echo "error: empty password" >&2
                return 1
            fi
            # SECURITY: pass the master password via STDIN, never as a CLI
            # argument — argv is visible to any process via `ps`//proc while bw
            # runs. `bw unlock --raw` reads the password from stdin.
            session=$(BW_SESSION="" bw unlock --raw < <(printf '%s\n' "$pw") 2>/dev/null) || true
            pw=""
            if [ -z "$session" ]; then
                echo "error: bw unlock failed (wrong password?)" >&2
                return 1
            fi
            export BW_SESSION="$session"
            return 0
            ;;
        *)
            echo "error: not logged in to Bitwarden (run 'bw login' first)" >&2
            return 1
            ;;
    esac
}

# pat_bw_get_field <item_name> [field_name]
# Echoes the field value on stdout. Uses BW_SESSION from the environment.
#
# bw 2026.x dropped `bw get field <name> <item>` (now rejects 3 args). We read
# the whole item JSON and pull the field with jq (preferred) or a grep fallback.
pat_bw_get_field() {
    local item=$1
    local field=${2:-$PAT_BW_FIELD_DEFAULT}
    local json
    json=$(bw get item "$item" 2>/dev/null) || return 1
    [ -z "$json" ] && return 1
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg f "$field" \
            '.fields[]? | select(.name==$f) | .value' 2>/dev/null
    else
        printf '%s' "$json" | python3 -c '
import sys, json
f = "'"$field"'"
try:
    for fld in json.load(sys.stdin).get("fields", []):
        if fld.get("name") == f:
            print(fld.get("value", ""))
            break
except Exception:
    pass
' 2>/dev/null
    fi
}

# pat_bw_item_exists <item_name> → 0 if found, non-zero otherwise.
pat_bw_item_exists() {
    local item=$1
    bw get item "$item" >/dev/null 2>&1
}
