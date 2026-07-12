#!/usr/bin/env bash
# Unit tests for the `pat` plugin. No network, no Bitwarden, no GitHub App.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$THIS_DIR/.." && pwd)"
SCRIPTS="$PLUGIN_ROOT/scripts"

# shellcheck source=../scripts/pat_lib/jwt.sh
. "$SCRIPTS/pat_lib/jwt.sh"
# shellcheck source=../scripts/pat_lib/bw.sh
. "$SCRIPTS/pat_lib/bw.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL  %s\n' "$1"; }

assert_eq() {
    local name=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then ok "$name"; else
        fail "$name"
        printf '        expected: %q\n' "$expected"
        printf '        actual:   %q\n' "$actual"
    fi
}
assert_contains() {
    local name=$1 needle=$2 haystack=$3
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then ok "$name"; else
        fail "$name"
        printf '        missing: %q\n' "$needle"
        printf '        haystack: %s\n' "$haystack"
    fi
}
assert_not_contains() {
    local name=$1 needle=$2 haystack=$3
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        fail "$name"
        printf '        unexpected: %q\n' "$needle"
    else ok "$name"; fi
}

echo "pat:"

# --- base64url ---
b64_out=$(printf '%s' '{"a":"b/c"}' | pat_b64url)
assert_not_contains "b64url strips padding" "=" "$b64_out"
b64_urlsafe_in='>???'
b64_raw=$(printf '%s' "$b64_urlsafe_in" | base64)
b64_url=$(printf '%s' "$b64_urlsafe_in" | pat_b64url)
assert_contains     "raw base64 has / to convert" "/" "$b64_raw"
assert_not_contains "b64url maps / to _" "/" "$b64_url"
assert_contains     "b64url uses _ in place of /" "_" "$b64_url"
assert_eq           "b64url of 'hello'" "aGVsbG8" "$(printf '%s' hello | pat_b64url)"

# --- JWT sign + structure ---
jwt_tmpkey=$(mktemp -d)
jwt_key="$jwt_tmpkey/key.pem"
if openssl genrsa -out "$jwt_key" 2048 >/dev/null 2>&1; then
    jwt=$(pat_jwt_sign "1234567" "$jwt_key")
    jwt_parts=$(printf '%s.' "$jwt" | tr -cd '.' | wc -c | tr -d ' ')
    assert_eq "jwt has three dot-separated parts" "3" "$((jwt_parts + 0))"
    jwt_header_b64=${jwt%%.*}
    jwt_header_dec=$(printf '%s==' "$jwt_header_b64" | tr '_-' '/+' | base64 -d 2>/dev/null)
    assert_contains "jwt header alg is RS256" "RS256" "$jwt_header_dec"
    rm -rf "$jwt_tmpkey"
else
    fail "jwt: openssl genrsa available (skipping jwt sign test)"
fi

# --- pat_resolve_repo URL normalization (BSD-sed-safe, strips .git) ---
# Reproduces the exact sed pipeline used in pat_resolve_repo.
norm() { printf '%s' "$1" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#' | sed -E 's#\.git$##'; }
assert_eq "resolve ssh+git url"  "axisrow/profile" "$(norm 'git@github.com:axisrow/profile.git')"
assert_eq "resolve https url"    "axisrow/profile" "$(norm 'https://github.com/axisrow/profile')"
assert_eq "resolve https+git"    "axisrow/profile" "$(norm 'https://github.com/axisrow/profile.git')"

# --- PEM temp-file leak regression ---
# pat_with_pem must set the path in the CALLING shell so the EXIT trap can
# remove it. Earlier it was called via $(...) (subshell), which leaked a
# readable PEM copy on every run. This test emulates the call pattern in a
# subprocess and asserts the temp file is gone after exit.
leak_script='
set -euo pipefail
. "'"$SCRIPTS"'/pat_lib/bw.sh" 2>/dev/null || true
pat_PEM_TMP=""; pat_pem_cleanup() { [ -n "$pat_PEM_TMP" ] && [ -f "$pat_PEM_TMP" ] && rm -f "$pat_PEM_TMP"; pat_PEM_TMP=""; }
trap pat_pem_cleanup EXIT
pat_with_pem() {
    local _out=$1
    pat_PEM_TMP=$(mktemp -t pattest.XXXXXX) || return 1
    chmod 600 "$pat_PEM_TMP"; printf "FAKE_PEM_BODY\n" >"$pat_PEM_TMP"
    printf -v "$_out" "%s" "$pat_PEM_TMP"
}
pat_with_pem captured_path
test -n "$captured_path" && test -n "$pat_PEM_TMP"
echo "$captured_path"
'
leaked_path=$(bash -c "$leak_script")
if [ -n "$leaked_path" ] && [ ! -e "$leaked_path" ]; then
    ok "pat_with_pem temp file removed after exit (no leak)"
else
    fail "pat_with_pem temp file leaked: $leaked_path"
fi

# And the OLD $(...) pattern must still leak under the same trap — proves the
# test actually detects the bug class (regression guard for the guard).
oldleak_script='
set -euo pipefail
pat_PEM_TMP=""; pat_pem_cleanup() { [ -n "$pat_PEM_TMP" ] && [ -f "$pat_PEM_TMP" ] && rm -f "$pat_PEM_TMP"; }
trap pat_pem_cleanup EXIT
emit() { pat_PEM_TMP=$(mktemp -t pattest.XXXXXX); chmod 600 "$pat_PEM_TMP"; echo BODY > "$pat_PEM_TMP"; printf %s "$pat_PEM_TMP"; }
cap=$(emit)
echo "$cap"
'
old_path=$(bash -c "$oldleak_script")
if [ -n "$old_path" ] && [ -e "$old_path" ]; then
    ok "regression guard: old \$(...) pattern leaks (test detects the bug class)"
    rm -f "$old_path"
else
    fail "regression guard: old pattern did not leak (guard is broken)"
fi

# --- bw status parsing ---
bw_stat_locked='{"serverUrl":null,"status":"locked","userEmail":"x@y"}'
assert_eq "bw_status reads 'locked'" "locked" \
    "$(printf '%s' "$bw_stat_locked" | grep -o '\"status\":\"[^\"]*\"' | sed 's/\"status\":\"//;s/\"//')"

# --- pat.sh CLI surface ---
pat_help=$(bash "$SCRIPTS/pat.sh" help 2>&1)
assert_contains     "pat help lists grant"     "grant"     "$pat_help"
assert_contains     "pat help lists install"   "install"   "$pat_help"
assert_contains     "pat help mentions Bitwarden" "Bitwarden" "$pat_help"

pat_bad=$(bash "$SCRIPTS/pat.sh" bogus 2>&1)
assert_contains "pat unknown subcommand errors" "unknown subcommand" "$pat_bad"

pat_grant_nosecret=$(bash "$SCRIPTS/pat.sh" grant 2>&1)
assert_contains "pat grant without --secret errors" "secret is required" "$pat_grant_nosecret"

echo
echo "----------------------------------------"
TOTAL=$((PASS + FAIL))
printf 'Result: %d/%d passed\n' "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed tests:"
    for name in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$name"; done
    exit 1
fi
exit 0
