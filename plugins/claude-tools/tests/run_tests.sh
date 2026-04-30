#!/usr/bin/env bash
# Unit/smoke tests for claude-tools. No real cron and no real claude CLI.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$THIS_DIR/.." && pwd)"
SCRIPTS="$PLUGIN_ROOT/scripts"

# shellcheck source=../scripts/lib.sh
. "$SCRIPTS/lib.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
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
    else
        ok "$name"
    fi
}

assert_exit() {
    local name=$1 expected=$2
    shift 2
    "$@" >/dev/null 2>&1
    local rc=$?
    if [ "$rc" = "$expected" ]; then ok "$name"; else
        fail "$name"
        printf '        expected exit %s, got %s\n' "$expected" "$rc"
    fi
}

echo "window helpers:"
NOW=1000000
assert_contains "ct_decide protects fresh ping" "skip too_soon_" "$(ct_decide "$NOW" $((NOW - 60)))"
assert_contains "ct_decide waits until +20s target" "skip scheduled_in_20s" "$(ct_decide "$NOW" $((NOW - CT_WINDOW_SEC)))"
assert_contains "ct_decide pings when target due" "ping target_due_" "$(ct_decide "$NOW" $((NOW - CT_WINDOW_SEC - CT_TARGET_OFFSET_SEC)))"
assert_eq "next target is window + 20s" "$((NOW + CT_WINDOW_SEC + CT_TARGET_OFFSET_SEC))" "$(ct_next_target "$NOW")"
assert_eq "next target empty without state" "" "$(ct_next_target "")"

echo "crontab blocks:"
controller_block=$(ct_build_block "$CT_CONTROLLER_MARKER" "PATH=/bin" "0 * * * *" 'bash "/tmp/controller.sh"')
ping_block=$(ct_build_block "$CT_PING_MARKER" "PATH=/bin" "10 13 2 5 *" 'bash "/tmp/ping.sh" --target 123')
combined=$(printf '0 9 * * * /tmp/user.sh\n%s\n%s\n' "$controller_block" "$ping_block")
filtered=$(printf '%s' "$combined" | ct_filter_existing)
assert_contains "filter keeps user cron" "/tmp/user.sh" "$filtered"
assert_not_contains "filter removes controller" "$CT_CONTROLLER_MARKER" "$filtered"
assert_not_contains "filter removes scheduled ping" "$CT_PING_MARKER" "$filtered"
assert_contains "extract blocks sees controller" "$CT_CONTROLLER_MARKER BEGIN" "$(printf '%s' "$combined" | ct_extract_blocks)"
assert_contains "extract marker sees target" "--target 123" "$(printf '%s' "$combined" | ct_extract_marker "$CT_PING_MARKER")"

echo "install/controller with fake crontab:"
SHIM_DIR=$(mktemp -d)
TEST_HOME=$(mktemp -d)
PING_SHIM_DIR=$(mktemp -d)
cleanup() { rm -rf "$SHIM_DIR" "$TEST_HOME" "$PING_SHIM_DIR"; }
trap cleanup EXIT

cat > "$SHIM_DIR/crontab" <<'SHIM_EOF'
#!/usr/bin/env bash
state="${CT_FAKE_CRONTAB:?missing CT_FAKE_CRONTAB}"
if [ "${1:-}" = "-l" ]; then
    [ -f "$state" ] && cat "$state"
    exit 0
fi
if [ "${1:-}" = "-r" ]; then
    rm -f "$state"
    exit 0
fi
cat > "$state"
SHIM_EOF
chmod +x "$SHIM_DIR/crontab"

cat > "$PING_SHIM_DIR/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
exit 0
CLAUDE_EOF
chmod +x "$PING_SHIM_DIR/claude"

export CT_FAKE_CRONTAB="$TEST_HOME/crontab"
export HOME="$TEST_HOME"
export PATH="$PING_SHIM_DIR:$SHIM_DIR:$PATH"

install_out=$(CLAUDE_TOOLS_FAKE_CLAUDE_DIR="$PING_SHIM_DIR" bash "$SCRIPTS/install.sh" --dry-run 2>&1)
assert_contains "dry-run installs controller marker" "$CT_CONTROLLER_MARKER BEGIN" "$install_out"
assert_contains "dry-run uses controller" "controller.sh" "$install_out"

bash "$SCRIPTS/install.sh" >/dev/null 2>&1
cron_after_install=$(cat "$CT_FAKE_CRONTAB")
assert_contains "install writes controller block" "$CT_CONTROLLER_MARKER BEGIN" "$cron_after_install"

state_file="$TEST_HOME/.claude/claude-tools/state.json"
last_ok=$(( $(date +%s) - 60 ))
ct_state_write "$state_file" "$last_ok" "$last_ok" "ok"
bash "$SCRIPTS/controller.sh" >/dev/null 2>&1
cron_after_controller=$(cat "$CT_FAKE_CRONTAB")
target=$((last_ok + CT_WINDOW_SEC + CT_TARGET_OFFSET_SEC))
assert_contains "controller writes scheduled marker" "$CT_PING_MARKER BEGIN" "$cron_after_controller"
assert_contains "controller writes target epoch" "--target $target" "$cron_after_controller"

bash "$SCRIPTS/controller.sh" >/dev/null 2>&1
begin_count=$(grep -c "$CT_PING_MARKER BEGIN" "$CT_FAKE_CRONTAB" || true)
assert_eq "controller is idempotent" "1" "$begin_count"

echo "ping runner:"
rm -f "$state_file"
bash "$SCRIPTS/ping.sh" --target "$(date +%s)" --reason test >/dev/null 2>&1
assert_contains "ping runner writes ok state" "ok:test" "$(cat "$state_file" 2>/dev/null || echo)"

echo "uninstall:"
uni_out=$(bash "$SCRIPTS/uninstall.sh" --dry-run 2>&1)
assert_not_contains "uninstall removes all claude blocks" "$CT_MARKER" "$uni_out"

echo
echo "----------------------------------------"
TOTAL=$((PASS + FAIL))
printf 'Result: %d/%d passed\n' "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed tests:"
    for name in "${FAILED_NAMES[@]}"; do
        printf '  - %s\n' "$name"
    done
    exit 1
fi
exit 0
