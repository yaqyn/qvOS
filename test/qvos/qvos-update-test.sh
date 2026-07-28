#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
adapter="$root/bin/omarchy-qvos-update"
owner="$root/qv/update/qvos-update"
availability_owner="$root/qv/update/update-available"
tui_update="$root/qv/tui/update/run"
tui_update_compat="$root/qv/tui/bin/qvos-update"
tui_launch="$root/qv/tui/update/launch"
launch_adapter="$root/bin/omarchy-launch-qvos-update"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
display_log="$test_root/display.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$test_root/live"
touch "$action_log" "$display_log"

install -m 0755 /dev/stdin "$test_bin/git" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"branch --show-current"* ]]; then
  printf '%s\n' "${QVOS_TEST_BRANCH:-OS}"
else
  exit 2
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
style)
  printf '%s\n' "$*" >"$QVOS_TEST_DISPLAY_LOG"
  printf 'gum-style\n' >>"$QVOS_TEST_ACTION_LOG"
  ;;
confirm)
  printf 'gum-confirm\n' >>"$QVOS_TEST_ACTION_LOG"
  exit "${QVOS_TEST_CONFIRM_STATUS:-0}"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-update" <<'SCRIPT'
#!/bin/bash
printf 'omarchy-update\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit "${QVOS_TEST_UPDATE_STATUS:-0}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-update-available" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_AVAILABLE_OUTPUT:-Omarchy update available (1.2.3)}"
exit "${QVOS_TEST_AVAILABLE_STATUS:-0}"
SCRIPT

run_owner() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_BRANCH="${QVOS_TEST_BRANCH:-OS}" \
    QVOS_TEST_CONFIRM_STATUS="${QVOS_TEST_CONFIRM_STATUS:-0}" \
    QVOS_TEST_DISPLAY_LOG="$display_log" \
    QVOS_TUI_BINARY="${QVOS_TEST_TUI_BINARY:-}" \
    QVOS_TEST_UPDATE_STATUS="${QVOS_TEST_UPDATE_STATUS:-0}" \
    OMARCHY_PATH="$test_root/live" \
    PATH="$test_bin:/usr/bin" \
    "$owner" "$@"
}

: >"$action_log"
confirmed_output=$(run_owner)
[[ $(<"$action_log") == $'gum-style\ngum-confirm\nomarchy-update\t-y' ]] ||
  fail "confirmed qvOS update delegation"
grep -Fq 'original Omarchy updater' "$display_log" ||
  fail "qvOS confirmation explains upstream ownership"
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS/commits/OS' "$display_log" ||
  fail "qvOS update history link"
grep -Fq 'Press Ctrl+C to stop the update if needed' "$display_log" ||
  fail "qvOS fallback cancellation guidance"
if grep -Fq 'cannot stop the update' "$display_log"; then
  fail "qvOS fallback retained the ISO-only interruption guard"
fi
grep -Fq 'qvOS update is complete.' <<<"$confirmed_output" ||
  fail "qvOS update completion result"
pass "qvOS confirms once and delegates once to the original Omarchy updater"

: >"$action_log"
run_owner -y >/dev/null
[[ $(<"$action_log") == $'omarchy-update\t-y' ]] ||
  fail "non-interactive qvOS update delegation"
pass "qvOS non-interactive mode skips only its wrapper confirmation"

: >"$action_log"
run_owner --check >/dev/null
[[ ! -s $action_log ]] ||
  fail "read-only qvOS update preflight entered the updater"
pass "qvOS exposes a read-only preflight for the TUI before sudo"

: >"$action_log"
set +e
cancel_output=$(QVOS_TEST_CONFIRM_STATUS=1 run_owner 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) ||
  fail "qvOS update cancellation status"
[[ $(<"$action_log") == $'gum-style\ngum-confirm' ]] ||
  fail "qvOS update cancellation mutation"
grep -Fq 'qvOS update cancelled.' <<<"$cancel_output" ||
  fail "qvOS update cancellation result"
pass "qvOS cancellation is explicit and never enters Omarchy update"

: >"$action_log"
set +e
wrong_branch_output=$(QVOS_TEST_BRANCH=master run_owner 2>&1)
wrong_branch_status=$?
set -e
((wrong_branch_status == 1)) ||
  fail "qvOS update wrong-branch status"
grep -Fq "requires the live checkout on branch OS; found 'master'." \
  <<<"$wrong_branch_output" ||
  fail "qvOS update wrong-branch result"
[[ ! -s $action_log ]] ||
  fail "qvOS update wrong-branch mutation"
pass "qvOS preflight refuses non-OS branches before confirmation or mutation"

: >"$action_log"
set +e
invalid_output=$(run_owner --unknown 2>&1)
invalid_status=$?
set -e
((invalid_status == 2)) ||
  fail "qvOS update invalid argument status"
grep -Fq 'Usage: omarchy-qvos-update [-y|--check]' <<<"$invalid_output" ||
  fail "qvOS update invalid argument usage"
[[ ! -s $action_log ]] ||
  fail "qvOS update invalid argument mutation"
pass "qvOS wrapper rejects unsupported arguments before preflight"

: >"$action_log"
set +e
failed_output=$(QVOS_TEST_UPDATE_STATUS=7 run_owner -y 2>&1)
failed_status=$?
set -e
((failed_status == 7)) ||
  fail "original updater failure propagation"
if grep -Fq 'qvOS update is complete.' <<<"$failed_output"; then
  fail "qvOS wrapper claims completion after an upstream failure"
fi
pass "qvOS preserves original updater failures without false completion"

if grep -Eq \
  'omarchy-update-(git|perform|system-pkgs|aur-pkgs|orphan-pkgs)|omarchy-migrate|omarchy-hook' \
  "$owner"; then
  fail "qvOS wrapper duplicates the original update pipeline"
fi
[[ $(grep -c '^omarchy-update -y$' "$owner") == "1" ]] ||
  fail "qvOS wrapper delegation count"
pass "qvOS owns only preflight and presentation, never Omarchy update stages"

available_output=$(PATH="$test_bin:/usr/bin" "$availability_owner")
[[ $available_output == "qvOS update available (1.2.3)" ]] ||
  fail "qvOS update-availability presentation"
set +e
current_output=$(
  QVOS_TEST_AVAILABLE_OUTPUT="Omarchy is up to date (1.2.3)" \
    QVOS_TEST_AVAILABLE_STATUS=1 \
    PATH="$test_bin:/usr/bin" \
    "$availability_owner"
)
current_status=$?
set -e
((current_status == 1)) ||
  fail "qvOS update-availability status preservation"
[[ $current_output == "qvOS is up to date (1.2.3)" ]] ||
  fail "qvOS current-version presentation"
pass "qvOS relabels only the original update-availability result"

install -m 0755 /dev/stdin "$test_bin/qvos-tui" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_TUI_BINARY_LOG"
SCRIPT
tui_binary_log="$test_root/tui-binary.log"
: >"$action_log"
QVOS_TEST_TUI_BINARY="$test_bin/qvos-tui" \
  QVOS_TEST_TUI_BINARY_LOG="$tui_binary_log" \
  run_owner >/dev/null
[[ $(<"$tui_binary_log") == "--update" ]] ||
  fail "interactive qvOS update TUI mode"
[[ ! -s $action_log ]] ||
  fail "interactive qvOS update bypassed TUI confirmation"
pass "interactive qvOS update delegates presentation to the shared TUI"

fixture="$test_root/fixture"
install -d "$fixture/qv/update"
install -m 0755 /dev/stdin "$fixture/qv/update/qvos-update" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_ADAPTER_LOG"
SCRIPT
adapter_log="$test_root/adapter.log"
QVOS_TEST_ADAPTER_LOG="$adapter_log" \
  OMARCHY_PATH="$fixture" \
  "$adapter" -y
[[ $(<"$adapter_log") == "-y" ]] ||
  fail "public qvOS update adapter"
pass "public qvOS command remains a thin adapter to its feature owner"

install -m 0755 /dev/stdin "$test_bin/omarchy-qvos-update" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_TUI_UPDATE_LOG"
if [[ -n ${QVOS_TEST_TUI_UPDATE_ENV_LOG:-} ]]; then
  printf '%s\n' "${OMARCHY_UPDATE_LOGGED:-}" >"$QVOS_TEST_TUI_UPDATE_ENV_LOG"
fi
if [[ -n ${QVOS_TEST_TUI_CANCEL_LOG:-} ]]; then
  trap 'printf "%s\n" stopped >"$QVOS_TEST_TUI_CANCEL_LOG"; exit 130' INT TERM
  printf '%s\n' ready >"$QVOS_TEST_TUI_CANCEL_LOG"
  while true; do
    sleep 0.1
  done
fi
exit "${QVOS_TEST_TUI_UPDATE_STATUS:-0}"
SCRIPT
tui_update_log="$test_root/tui-update.log"
tui_update_env_log="$test_root/tui-update-env.log"
tui_session_log="$test_root/tui-session.log"
QVOS_TEST_TUI_UPDATE_LOG="$tui_update_log" \
  QVOS_TEST_TUI_UPDATE_ENV_LOG="$tui_update_env_log" \
  QVOS_UPDATE_LOG_PATH="$tui_session_log" \
  PATH="$test_bin:/usr/bin" \
  "$tui_update"
[[ $(<"$tui_update_log") == "-y" ]] ||
  fail "qvOS TUI update delegation"
[[ $(<"$tui_update_env_log") == "1" ]] ||
  fail "qvOS TUI update process-group mode"
[[ -f $tui_session_log ]] ||
  fail "qvOS TUI update session log"
QVOS_TEST_TUI_UPDATE_LOG="$tui_update_log" \
  PATH="$test_bin:/usr/bin" \
  "$tui_update" --check
[[ $(<"$tui_update_log") == "--check" ]] ||
  fail "qvOS TUI update preflight delegation"
QVOS_TEST_TUI_UPDATE_LOG="$tui_update_log" \
  QVOS_UPDATE_LOG_PATH="$tui_session_log" \
  PATH="$test_bin:/usr/bin" \
  "$tui_update_compat"
[[ $(<"$tui_update_log") == "-y" ]] ||
  fail "legacy qvOS TUI update adapter"
set +e
QVOS_TEST_TUI_UPDATE_LOG="$tui_update_log" \
  QVOS_TEST_TUI_UPDATE_STATUS=7 \
  QVOS_UPDATE_LOG_PATH="$tui_session_log" \
  PATH="$test_bin:/usr/bin" \
  "$tui_update" >/dev/null
tui_update_status=$?
set -e
((tui_update_status == 7)) ||
  fail "qvOS TUI update failure status"
cancel_log="$test_root/tui-cancel.log"
set +e
QVOS_TEST_TUI_CANCEL_LOG="$cancel_log" \
  QVOS_TEST_TUI_UPDATE_LOG="$tui_update_log" \
  QVOS_UPDATE_LOG_PATH="$tui_session_log" \
  PATH="$test_bin:/usr/bin" \
  setsid bash -c 'trap - INT TERM; exec "$@"' _ "$tui_update" >/dev/null 2>&1 &
cancel_pid=$!
for ((attempt = 0; attempt < 50; attempt++)); do
  [[ -f $cancel_log ]] && break
  sleep 0.02
done
if [[ $(<"$cancel_log") != "ready" ]]; then
  kill -TERM -- "-$cancel_pid" 2>/dev/null || true
  wait "$cancel_pid" 2>/dev/null
  set -e
  fail "qvOS TUI update cancellation fixture"
fi
kill -TERM -- "-$cancel_pid"
wait "$cancel_pid"
tui_cancel_status=$?
set -e
((tui_cancel_status == 143)) ||
  fail "qvOS TUI update cancellation status"
for ((attempt = 0; attempt < 50; attempt++)); do
  ! kill -0 -- "-$cancel_pid" 2>/dev/null && break
  sleep 0.02
done
if kill -0 -- "-$cancel_pid" 2>/dev/null; then
  fail "qvOS TUI update process-group cancellation"
fi
pass "qvOS TUI owns cancellable logging and preserves wrapper results"

install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_TUI_LAUNCH_LOG"
SCRIPT
tui_launch_log="$test_root/tui-launch.log"
QVOS_TEST_TUI_LAUNCH_LOG="$tui_launch_log" \
  PATH="$test_bin:/usr/bin" \
  "$tui_launch"
[[ $(<"$tui_launch_log") == "uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal --title=qvOS -e omarchy-qvos-update" ]] ||
  fail "qvOS TUI update terminal launch"
pass "qvOS Update opens the shared TUI without the legacy presentation wrapper"

install -D -m 0755 "$tui_launch" "$fixture/qv/tui/update/launch"
QVOS_TEST_TUI_LAUNCH_LOG="$tui_launch_log" \
  OMARCHY_PATH="$fixture" \
  PATH="$test_bin:/usr/bin" \
  "$launch_adapter"
[[ $(<"$tui_launch_log") == "uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal --title=qvOS -e omarchy-qvos-update" ]] ||
  fail "public qvOS Update launch adapter"
pass "public qvOS Update launcher remains a thin TUI-domain adapter"
