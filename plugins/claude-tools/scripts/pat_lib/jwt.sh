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

# pat_jwt_app_meta <jwt>  → echoes the App JSON from GET /app (for install verification).
pat_jwt_app_meta() {
    local jwt=$1
    curl -fsSL -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app" 2>/dev/null
}

# pat_jwt_installations <jwt>  → echoes the installations JSON array.
pat_jwt_installations() {
    local jwt=$1
    curl -fsSL -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app/installations" 2>/dev/null
}

# pat_installation_token <jwt> <installation_id>
# Echoes the JSON response from POST /app/installations/<id>/access_tokens
# (contains .token and .expires_at).
pat_installation_token() {
    local jwt=$1
    local installation_id=$2
    curl -fsSL -X POST \
        -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app/installations/${installation_id}/access_tokens" 2>/dev/null
}
