#!/usr/bin/env bash
# JWT (RS256) helpers for pat.
# Sourced by pat.sh. No side effects on source.
#
# Depends on: openssl (present on macOS and most Linux distros).

# pat_b64url <stdin>  — base64, URL-safe, no padding.
pat_b64url() {
    base64 | tr -d '\n=' | tr '+/' '-_'
}

# pat_jwt_sign <app_id> <pem_file>  → echoes a signed RS256 JWT on stdout.
# JWT payload: iss = app_id, iat = now - 60s (clock-skew tolerance),
# exp = now + 540s (9 min; GitHub max is 10 min).
pat_jwt_sign() {
    local app_id=$1
    local pem_file=$2

    # epoch seconds; tolerate both GNU and BSD date.
    local now exp iat
    now=$(date +%s 2>/dev/null || echo 0)
    iat=$((now - 60))
    exp=$((now + 540))

    local header payload
    header='{"alg":"RS256","typ":"JWT"}'
    payload='{"iss":"'"$app_id"'","iat":'"$iat"',"exp":'"$exp"'}'

    local h64 p64 signing_input
    h64=$(printf '%s' "$header" | pat_b64url)
    p64=$(printf '%s' "$payload" | pat_b64url)
    signing_input="$h64.$p64"

    local sig64
    sig64=$(printf '%s' "$signing_input" \
        | openssl dgst -sha256 -sign "$pem_file" 2>/dev/null \
        | pat_b64url)

    printf '%s.%s' "$signing_input" "$sig64"
}

# pat_gh_curl <jwt> <method> <url> [data]
# curl wrapper that keeps the JWT out of the process argv: the Authorization
# header is written to a 0600 temp curl-config file and passed via --config,
# then removed. (curl -H would expose the signed JWT in `ps`.)
pat_gh_curl() {
    local jwt=$1 method=$2 url=$3 data=${4:-}
    local cfg
    cfg=$(mktemp -t patcurl.XXXXXX) || return 1
    chmod 600 "$cfg"
    {
        printf 'header = "Authorization: Bearer %s"\n' "$jwt"
        printf 'header = "Accept: application/vnd.github+json"\n'
        printf 'silent\nfail\nshow-error\nlocation\n'
        [ -n "$method" ] && printf 'request = "%s"\n' "$method"
        [ -n "$data" ] && printf 'data = "%s"\n' "$data"
    } >"$cfg"
    curl --config "$cfg" "$url" 2>/dev/null
    local rc=$?
    rm -f "$cfg"
    return $rc
}

# pat_jwt_app_meta <jwt>  → echoes the App JSON from GET /app (for install verification).
pat_jwt_app_meta() {
    pat_gh_curl "$1" GET "https://api.github.com/app"
}

# pat_jwt_installations <jwt>  → echoes the installations JSON array.
pat_jwt_installations() {
    pat_gh_curl "$1" GET "https://api.github.com/app/installations"
}

# pat_installation_token <jwt> <installation_id>
# Echoes the JSON response from POST /app/installations/<id>/access_tokens
# (contains .token and .expires_at).
pat_installation_token() {
    pat_gh_curl "$1" POST \
        "https://api.github.com/app/installations/${2}/access_tokens"
}
