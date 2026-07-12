#!/usr/bin/env bash
# pat — issue a short-lived GitHub App installation access token and (optionally)
# store it as a repository Actions secret. Replaces manually created PATs.
#
# Flow:  Bitwarden (PEM) → RS256 JWT → installation access token (1h) → gh secret set
#
# Config (~/.config/pat/config, sourced, mode 0600 recommended):
#   PAT_APP_ID     numeric GitHub App ID
#   PAT_BW_ITEM    Bitwarden secure-note name holding the App private key
#   PAT_BW_FIELD   custom-field name with the PEM body (default: "private-key")
# Any of these may instead be supplied via environment variables.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pat_lib/bw.sh
. "$SCRIPT_DIR/pat_lib/bw.sh"
# shellcheck source=pat_lib/jwt.sh
. "$SCRIPT_DIR/pat_lib/jwt.sh"

PAT_CONFIG="${PAT_CONFIG:-$HOME/.config/pat/config}"

pat_die() { echo "error: $*" >&2; exit 1; }

pat_usage() {
    cat <<'EOF'
pat — issue a GitHub App installation access token (no manual PAT)

Subcommands:
  pat install                       Verify config, App, Bitwarden item, and gh.
  pat token                         Print a fresh installation token to stdout.
  pat grant --secret NAME --repo OWNER/REPO
                                    Store a fresh token as a repo Actions secret.
                                    --repo defaults to the current git origin.

Options:
  --secret NAME     Actions secret name (required for `grant`).
  --repo OWNER/REPO Target repository.
  --note  TEXT      Free-form note echoed after success.
  -h, help          Show this help.

Config (~/.config/pat/config or env):
  PAT_APP_ID        GitHub App ID (numeric).
  PAT_BW_ITEM       Bitwarden secure-note name with the App private key.
  PAT_BW_FIELD      Custom-field holding the PEM (default: private-key).
EOF
}

pat_load_config() {
    if [ -n "${PAT_APP_ID:-}" ] && [ -n "${PAT_BW_ITEM:-}" ]; then
        return 0   # env already provides what we need
    fi
    if [ -f "$PAT_CONFIG" ]; then
        # shellcheck disable=SC1090
        . "$PAT_CONFIG"
    fi
    : "${PAT_BW_FIELD:=$PAT_BW_FIELD_DEFAULT}"
}

pat_require_deps() {
    command -v openssl >/dev/null 2>&1 || pat_die "openssl not found on PATH."
    command -v bw       >/dev/null 2>&1 || pat_die "bw (Bitwarden CLI) not found on PATH."
    command -v gh       >/dev/null 2>&1 || pat_die "gh (GitHub CLI) not found on PATH."
    command -v curl     >/dev/null 2>&1 || pat_die "curl not found on PATH."
}

# pat_jwt_value <json> <key>  → echoes a top-level string value (grep fallback if no jq).
pat_json_get() {
    local json=$1 key=$2
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg k "$key" '.[$k] // empty'
    else
        printf '%s' "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
            | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//'
    fi
}

# pat_resolve_repo  → echoes OWNER/REPO from --repo or the current git origin.
pat_resolve_repo() {
    if [ -n "${OPT_REPO:-}" ]; then
        printf '%s' "$OPT_REPO"
        return
    fi
    local url
    url=$(git config --get remote.origin.url 2>/dev/null || true)
    [ -z "$url" ] && pat_die "no --repo given and not inside a git repo with origin."
    # normalize ssh/git/https URLs to owner/repo
    printf '%s' "$url" \
        | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#'
}

# pat_get_pem_file  → writes PEM to a private temp file, echoes its path.
# The file is 0600 and removed on exit.
pat_PEM_TMP=""
pat_cleanup() { [ -n "$pat_PEM_TMP" ] && [ -f "$pat_PEM_TMP" ] && rm -f "$pat_PEM_TMP"; }
trap pat_cleanup EXIT
pat_get_pem_file() {
    pat_bw_ensure_unlocked || pat_die "cannot unlock Bitwarden."
    local pem
    pem=$(pat_bw_get_field "$PAT_BW_ITEM" "$PAT_BW_FIELD")
    [ -z "$pem" ] && pat_die "empty PEM from Bitwarden item '$PAT_BW_ITEM' field '$PAT_BW_FIELD'."
    pat_PEM_TMP=$(mktemp -t pat.XXXXXX)
    chmod 600 "$pat_PEM_TMP"
    printf '%s\n' "$pem" >"$pat_PEM_TMP"
    printf '%s' "$pat_PEM_TMP"
}

# pat_installation_id_for <jwt> <app_id>  → echoes the installation id for the app.
pat_installation_id_for() {
    local jwt=$1 app_id=$2
    local json
    json=$(pat_jwt_installations "$jwt") || pat_die "failed to list App installations."
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" \
            | jq -r --arg app "$app_id" '.[] | select((.app_id|tostring)==$app) | .id' \
            | head -1
    else
        # crude grep fallback: find the first "id" after an "app_id" match
        printf '%s' "$json" \
            | awk -v app="$app_id" '
                /"app_id"[[:space:]]*:[[:space:]]*"/ {
                    match($0, /"app_id"[[:space:]]*:[[:space:]]*"?([0-9]+)/, m);
                    if (m[1]==app) want=1
                }
                want && /"id"[[:space:]]*:[[:space:]]*[0-9]+/ {
                    match($0, /"id"[[:space:]]*:[[:space:]]*([0-9]+)/, m);
                    print m[1]; want=0; exit
                }
            ' | head -1
    fi
}

# pat_fresh_token  → echoes "<token>\t<expires_at>" (tab-separated).
pat_fresh_token() {
    pat_load_config
    : "${PAT_APP_ID:?PAT_APP_ID is not set (config or env).}"
    : "${PAT_BW_ITEM:?PAT_BW_ITEM is not set (config or env).}"

    local pem_file jwt inst_json token expires
    pem_file=$(pat_get_pem_file)
    jwt=$(pat_jwt_sign "$PAT_APP_ID" "$pem_file")
    [ -z "$jwt" ] && pat_die "JWT signing failed (is the PEM valid?)."

    # sanity: App must be reachable with this JWT
    pat_jwt_app_meta "$jwt" >/dev/null 2>&1 || pat_die "JWT rejected by GET /app (wrong APP_ID or key?)."

    local installation_id
    installation_id=$(pat_installation_id_for "$jwt" "$PAT_APP_ID")
    [ -z "$installation_id" ] && pat_die "no installation found for App $PAT_APP_ID (install it on your account)."

    inst_json=$(pat_installation_token "$jwt" "$installation_id") \
        || pat_die "failed to mint installation token."
    token=$(pat_json_get "$inst_json" "token")
    expires=$(pat_json_get "$inst_json" "expires_at")
    [ -z "$token" ] && pat_die "installation token response had no .token."
    printf '%s\t%s' "$token" "$expires"
}

# ---- subcommands ----

cmd_install() {
    pat_require_deps
    pat_load_config
    local ok=1
    echo "pat install — checks"
    if [ -n "${PAT_APP_ID:-}" ]; then
        echo "  ✓ PAT_APP_ID = $PAT_APP_ID"
    else
        echo "  ✗ PAT_APP_ID not set"; ok=0
    fi
    if [ -n "${PAT_BW_ITEM:-}" ]; then
        echo "  ✓ PAT_BW_ITEM = $PAT_BW_ITEM"
    else
        echo "  ✗ PAT_BW_ITEM not set"; ok=0
    fi
    echo "  ✓ PAT_BW_FIELD = ${PAT_BW_FIELD:-$PAT_BW_FIELD_DEFAULT}"

    pat_bw_ensure_unlocked >/dev/null || { ok=0; }
    if pat_bw_item_exists "$PAT_BW_ITEM"; then
        echo "  ✓ Bitwarden item '$PAT_BW_ITEM' found"
    else
        echo "  ✗ Bitwarden item '$PAT_BW_ITEM' not found"; ok=0
    fi

    # JWT + App reachable?
    local pem_file jwt
    pem_file=$(pat_get_pem_file 2>/dev/null) || { echo "  ✗ cannot read PEM from Bitwarden"; ok=0; }
    if [ -n "${pem_file:-}" ]; then
        jwt=$(pat_jwt_sign "$PAT_APP_ID" "$pem_file" 2>/dev/null || true)
        if [ -n "$jwt" ] && pat_jwt_app_meta "$jwt" >/dev/null 2>&1; then
            echo "  ✓ GitHub App $PAT_APP_ID reachable (JWT valid)"
        else
            echo "  ✗ GitHub App not reachable (wrong APP_ID or PEM)"; ok=0
        fi
    fi

    if gh auth status >/dev/null 2>&1; then
        echo "  ✓ gh authenticated"
    else
        echo "  ✗ gh not authenticated (run 'gh auth login')"; ok=0
    fi

    if [ "$ok" -eq 1 ]; then
        echo "pat: all checks passed."
        return 0
    fi
    pat_die "one or more checks failed."
}

cmd_token() {
    pat_require_deps
    pat_fresh_token | cut -f1
}

cmd_grant() {
    pat_require_deps
    [ -n "${OPT_SECRET:-}" ] || pat_die "--secret is required for grant."
    local repo pair token expires
    repo=$(pat_resolve_repo)
    pair=$(pat_fresh_token)
    token=${pair%%$'\t'*}
    expires=${pair#*$'\t'}
    gh secret set "$OPT_SECRET" --repo "$repo" --body "$token" >/dev/null \
        || pat_die "gh secret set failed for $repo."
    printf '✓ %s set in %s · valid until %s\n' "$OPT_SECRET" "$repo" "$expires"
    [ -n "${OPT_NOTE:-}" ] && printf '  note: %s\n' "$OPT_NOTE"
}

# ---- arg parsing ----

main() {
    local sub="${1:-help}"
    [ $# -gt 0 ] && shift

    OPT_SECRET=""
    OPT_REPO=""
    OPT_NOTE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --secret) OPT_SECRET="${2:-}"; shift 2 ;;
            --repo)   OPT_REPO="${2:-}";   shift 2 ;;
            --note)   OPT_NOTE="${2:-}";   shift 2 ;;
            -h|--help|help) pat_usage; exit 0 ;;
            *) pat_die "unknown argument: $1" ;;
        esac
    done

    case "$sub" in
        install) cmd_install ;;
        token)   cmd_token ;;
        grant)   cmd_grant ;;
        help|-h|--help) pat_usage ;;
        *) pat_die "unknown subcommand: $sub (try: pat help)" ;;
    esac
}

main "$@"
