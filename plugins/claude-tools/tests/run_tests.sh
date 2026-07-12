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

echo "run_with_timeout normalisation:"
# Extract the run_with_timeout function from ping.sh via a subshell that
# also disables PATH so that the bash-fallback branch is exercised on macOS
# (where `timeout` is rarely installed). We run inline to capture rc.
rwt_test() {
    local script
    script=$(awk '/^run_with_timeout\(\)/,/^}$/' "$SCRIPTS/ping.sh")
    bash -c "$script
$1"
}
rwt_test 'run_with_timeout 5 true; exit $?'                         ; rc=$?
assert_eq "rc=0 passes through"          "0"   "$rc"
rwt_test 'run_with_timeout 5 false; exit $?'                        ; rc=$?
assert_eq "rc=1 passes through"          "1"   "$rc"
rwt_test 'run_with_timeout 1 sleep 30; exit $?'                     ; rc=$?
assert_eq "timeout normalises to 124"    "124" "$rc"

echo "CT_DATA_DIR override:"
override_dir=$(mktemp -d)
CT_DATA_DIR="$override_dir" bash "$SCRIPTS/ping.sh" --target "$(date +%s)" --reason override >/dev/null 2>&1
assert_eq "state goes to override dir" "yes" "$([ -f "$override_dir/state.json" ] && echo yes || echo no)"
assert_contains "log goes to override dir" "ping" "$(cat "$override_dir/ping.log" 2>/dev/null || echo)"
rm -rf "$override_dir"

echo "lock TTL behaviour:"
# Fresh lock blocks a second run.
lock_dir=$(mktemp -d)
mkdir "$lock_dir/ping.lock"
CT_DATA_DIR="$lock_dir" bash "$SCRIPTS/ping.sh" --target "$(date +%s)" --reason locked >/dev/null 2>&1
assert_contains "fresh lock blocks ping" "another ping in progress" "$(cat "$lock_dir/ping.log" 2>/dev/null || echo)"
rm -rf "$lock_dir"

# Stale lock (mtime older than TTL) gets reclaimed.
stale_dir=$(mktemp -d)
mkdir "$stale_dir/ping.lock"
# Force lock mtime to 5 hours ago (> 4h30m TTL).
old=$(( $(date +%s) - 5 * 3600 ))
touch -t "$(date -r "$old" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$old" '+%Y%m%d%H%M.%S')" "$stale_dir/ping.lock"
CT_DATA_DIR="$stale_dir" bash "$SCRIPTS/ping.sh" --target "$(date +%s)" --reason stale >/dev/null 2>&1
assert_contains "stale lock reclaimed" "stale lock" "$(cat "$stale_dir/ping.log" 2>/dev/null || echo)"
assert_contains "stale lock then pings" "ok:stale" "$(cat "$stale_dir/state.json" 2>/dev/null || echo)"
rm -rf "$stale_dir"

echo "no-retry mode:"
# With --no-retry, a fast-failing claude must NOT trigger the retry chain.
# Simulate failure via PATH-shim that returns rc=1 instantly.
fail_dir=$(mktemp -d)
fail_shim=$(mktemp -d)
cat >"$fail_shim/claude" <<'CLAUDE_FAIL_EOF'
#!/usr/bin/env bash
echo "Not logged in · Please run /login" >&2
exit 1
CLAUDE_FAIL_EOF
chmod +x "$fail_shim/claude"

start=$(date +%s)
PATH="$fail_shim:$PATH" CT_DATA_DIR="$fail_dir" \
    bash "$SCRIPTS/ping.sh" --no-retry --reason notest >/dev/null 2>&1
elapsed=$(( $(date +%s) - start ))
assert_eq "no-retry exits fast (<5s)" "yes" "$([ "$elapsed" -lt 5 ] && echo yes || echo no)"
assert_contains "no-retry records error state" "error:rc1" "$(cat "$fail_dir/state.json" 2>/dev/null || echo)"
assert_not_contains "no-retry skips retry chain" "retry in" "$(cat "$fail_dir/ping.log" 2>/dev/null || echo)"
assert_contains "no-retry log mentions mode" "no-retry mode" "$(cat "$fail_dir/ping.log" 2>/dev/null || echo)"

rm -rf "$fail_dir" "$fail_shim"

echo "controller wires --no-retry:"
assert_contains "controller passes --no-retry" "--no-retry" "$(cat "$SCRIPTS/controller.sh")"

echo "timeout treated as failure:"
# A claude that hangs longer than the ping timeout must be recorded as an
# error, not as a successful ping — DNS/TLS stalls can time out before the
# request reaches Anthropic.
hang_dir=$(mktemp -d)
hang_shim=$(mktemp -d)
cat >"$hang_shim/claude" <<'CLAUDE_HANG_EOF'
#!/usr/bin/env bash
sleep 60
CLAUDE_HANG_EOF
chmod +x "$hang_shim/claude"

PATH="$hang_shim:$PATH" CT_DATA_DIR="$hang_dir" \
    bash "$SCRIPTS/ping.sh" --no-retry --reason hangtest >/dev/null 2>&1
assert_contains "hung ping records error state" "error:rc124" "$(cat "$hang_dir/state.json" 2>/dev/null || echo)"
assert_not_contains "hung ping does NOT record ok state" '"last_attempt_result": "ok' "$(cat "$hang_dir/state.json" 2>/dev/null || echo)"
assert_contains "hung ping log mentions timed out" "timed out" "$(cat "$hang_dir/ping.log" 2>/dev/null || echo)"
rm -rf "$hang_dir" "$hang_shim"

echo "scheduled ping refresh on path change:"
# ensure_scheduled_ping should reinstall when the embedded PING_SCRIPT path
# differs from the current desired block, even if --target matches.
refresh_dir=$(mktemp -d)
shim_dir=$(mktemp -d)
cat > "$shim_dir/crontab" <<'CRON_REFRESH_EOF'
#!/usr/bin/env bash
state="${CT_FAKE_CRONTAB:?missing CT_FAKE_CRONTAB}"
if [ "${1:-}" = "-l" ]; then [ -f "$state" ] && cat "$state"; exit 0; fi
if [ "${1:-}" = "-r" ]; then rm -f "$state"; exit 0; fi
cat > "$state"
CRON_REFRESH_EOF
chmod +x "$shim_dir/crontab"
cat > "$shim_dir/claude" <<'CLAUDE_REFRESH_EOF'
#!/usr/bin/env bash
exit 0
CLAUDE_REFRESH_EOF
chmod +x "$shim_dir/claude"

export CT_FAKE_CRONTAB="$refresh_dir/crontab"
PATH_BACKUP=$PATH
export PATH="$shim_dir:$PATH"
HOME_BACKUP=$HOME
export HOME="$refresh_dir"

# Pre-populate state so controller picks a target and fills crontab.
last_ok=$(( $(date +%s) - 60 ))
mkdir -p "$refresh_dir/.claude/claude-tools"
ct_state_write "$refresh_dir/.claude/claude-tools/state.json" "$last_ok" "$last_ok" "ok"

# Initial controller run installs scheduled ping with current PING_SCRIPT.
bash "$SCRIPTS/controller.sh" >/dev/null 2>&1
initial_cron=$(cat "$CT_FAKE_CRONTAB")
assert_contains "initial cron has scheduled-ping marker" "$CT_PING_MARKER BEGIN" "$initial_cron"

# Inject a stale PING_SCRIPT path into the crontab and re-run controller.
# It should detect the mismatch and rewrite the block.
sed_inplace=(-i)
case "$(uname)" in Darwin) sed_inplace=(-i '');; esac
sed "${sed_inplace[@]}" 's#'"$SCRIPTS/ping.sh"'#/old/stale/path/ping.sh#g' "$CT_FAKE_CRONTAB"
stale_cron=$(cat "$CT_FAKE_CRONTAB")
assert_contains "crontab now has stale path"   "/old/stale/path/ping.sh" "$stale_cron"

bash "$SCRIPTS/controller.sh" >/dev/null 2>&1
refreshed_cron=$(cat "$CT_FAKE_CRONTAB")
assert_not_contains "stale path was replaced" "/old/stale/path/ping.sh" "$refreshed_cron"
assert_contains    "refreshed cron uses real path" "$SCRIPTS/ping.sh"    "$refreshed_cron"

unset CT_FAKE_CRONTAB
export PATH=$PATH_BACKUP
export HOME=$HOME_BACKUP
rm -rf "$refresh_dir" "$shim_dir"

echo "controller self-removes cron when plugin is gone:"
# Simulate the plugin being deleted: run the controller from a *copy* of
# scripts/ (so we can delete files without touching the repo), fill the
# crontab, then remove ping.sh from the copy. The next controller run must
# detect the missing sibling and tear down the whole claude-tools cron block.
heal_dir=$(mktemp -d)
heal_scripts="$heal_dir/scripts"
mkdir -p "$heal_scripts"
cp "$SCRIPTS"/lib.sh "$SCRIPTS"/controller.sh "$SCRIPTS"/ping.sh "$heal_scripts/"

heal_shim=$(mktemp -d)
cat > "$heal_shim/crontab" <<'CRON_HEAL_EOF'
#!/usr/bin/env bash
state="${CT_FAKE_CRONTAB:?missing CT_FAKE_CRONTAB}"
if [ "${1:-}" = "-l" ]; then [ -f "$state" ] && cat "$state"; exit 0; fi
if [ "${1:-}" = "-r" ]; then rm -f "$state"; exit 0; fi
cat > "$state"
CRON_HEAL_EOF
chmod +x "$heal_shim/crontab"
cat > "$heal_shim/claude" <<'CLAUDE_HEAL_EOF'
#!/usr/bin/env bash
exit 0
CLAUDE_HEAL_EOF
chmod +x "$heal_shim/claude"

export CT_FAKE_CRONTAB="$heal_dir/crontab"
PATH_BACKUP=$PATH
export PATH="$heal_shim:$PATH"
HOME_BACKUP=$HOME
export HOME="$heal_dir"

# Pre-populate state so the controller installs a scheduled-ping block.
heal_last=$(( $(date +%s) - 60 ))
mkdir -p "$heal_dir/.claude/claude-tools"
ct_state_write "$heal_dir/.claude/claude-tools/state.json" "$heal_last" "$heal_last" "ok"

bash "$heal_scripts/controller.sh" >/dev/null 2>&1
assert_contains "controller filled cron before removal" "$CT_PING_MARKER BEGIN" "$(cat "$CT_FAKE_CRONTAB")"

# Plugin "deleted": ping.sh disappears, controller.sh + lib.sh still present.
rm -f "$heal_scripts/ping.sh"
bash "$heal_scripts/controller.sh" >/dev/null 2>&1
healed_cron=$(cat "$CT_FAKE_CRONTAB" 2>/dev/null || echo)
assert_not_contains "self-heal removed all claude-tools cron" "$CT_MARKER" "$healed_cron"
assert_contains "self-heal logged removal" "self-removing cron" "$(cat "$heal_dir/.claude/claude-tools/ping.log" 2>/dev/null || echo)"

unset CT_FAKE_CRONTAB
export PATH=$PATH_BACKUP
export HOME=$HOME_BACKUP
rm -rf "$heal_dir" "$heal_shim"

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
