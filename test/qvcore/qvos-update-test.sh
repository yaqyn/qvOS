#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
action_log="$test_root/actions.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

install -d "$test_bin"
: >"$action_log"

# Product wrapper: preflight and confirmation must happen before one delegation.
live="$test_root/live"
install -d "$live/qvcore/update"
install -m 0755 "$root/qvcore/update/source-check" "$live/qvcore/update/source-check"
install -m 0755 /dev/stdin "$live/qvcore/update/run" <<'SCRIPT'
#!/bin/bash
printf 'run\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit "${QVOS_TEST_RUN_STATUS:-0}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/git" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"branch --show-current"* ]]; then
  printf '%s\n' "${QVOS_TEST_BRANCH:-OS}"
elif [[ $* == *"status --porcelain=v1 --untracked-files=all"* ]]; then
  printf '%s' "${QVOS_TEST_SOURCE_STATUS:-}"
elif [[ $* == *"config --get remote.origin.url"* ]]; then
  printf '%s\n' "${QVOS_TEST_ORIGIN:-https://github.com/Yaqyn-qvOS/qvOS.git}"
else
  exit 2
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
style) printf 'style:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG" ;;
confirm)
  printf 'confirm\n' >>"$QVOS_TEST_ACTION_LOG"
  exit "${QVOS_TEST_CONFIRM_STATUS:-0}"
  ;;
*) exit 2 ;;
esac
SCRIPT

run_wrapper() {
  HOME="$test_root/home" \
    QVOS_PATH="$live" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_BRANCH="${QVOS_TEST_BRANCH:-OS}" \
    QVOS_TEST_CONFIRM_STATUS="${QVOS_TEST_CONFIRM_STATUS:-0}" \
    QVOS_TEST_ORIGIN="${QVOS_TEST_ORIGIN:-https://github.com/Yaqyn-qvOS/qvOS.git}" \
    QVOS_TEST_RUN_STATUS="${QVOS_TEST_RUN_STATUS:-0}" \
    QVOS_TEST_SOURCE_STATUS="${QVOS_TEST_SOURCE_STATUS:-}" \
    QVOS_TUI_BINARY="${QVOS_TEST_TUI_BINARY:-}" \
    PATH="$test_bin:/usr/bin" \
    "$root/qvcore/update/qvos-update" "$@"
}

: >"$action_log"
wrapper_output=$(run_wrapper)
grep -Fq 'qvOS update is complete.' <<<"$wrapper_output" ||
  fail "wrapper completion output"
[[ $(tail -n 2 "$action_log") == $'confirm\nrun\t' ]] ||
  fail "wrapper confirmation and delegation order"
[[ $(grep -c '^run' "$action_log") == 1 ]] || fail "wrapper delegation count"

: >"$action_log"
run_wrapper -y >/dev/null
[[ $(<"$action_log") == $'run\t' ]] || fail "noninteractive wrapper delegation"

: >"$action_log"
run_wrapper --check >/dev/null
[[ ! -s $action_log ]] || fail "read-only preflight entered update engine"

set +e
QVOS_TEST_CONFIRM_STATUS=1 cancel_output=$(run_wrapper 2>&1)
cancel_status=$?
set -e
(( cancel_status == 130 )) || fail "wrapper cancellation status"
grep -Fq 'qvOS update cancelled.' <<<"$cancel_output" || fail "wrapper cancellation output"
QVOS_TEST_CONFIRM_STATUS=0

set +e
QVOS_TEST_BRANCH=master wrong_branch=$(run_wrapper -y 2>&1)
wrong_branch_status=$?
set -e
(( wrong_branch_status == 1 )) || fail "wrong branch status"
grep -Fq "branch OS; found 'master'" <<<"$wrong_branch" || fail "wrong branch message"
QVOS_TEST_BRANCH=OS

set +e
QVOS_TEST_SOURCE_STATUS=' M local-change' dirty_output=$(run_wrapper -y 2>&1)
dirty_status=$?
set -e
(( dirty_status == 1 )) || fail "dirty source status"
grep -Fq 'source has local changes' <<<"$dirty_output" ||
  fail "dirty source message"
QVOS_TEST_SOURCE_STATUS=""

set +e
QVOS_TEST_ORIGIN=https://example.invalid/qvos.git \
  wrong_origin_output=$(run_wrapper -y 2>&1)
wrong_origin_status=$?
set -e
(( wrong_origin_status == 1 )) || fail "unofficial source origin status"
grep -Fq 'requires the official origin' <<<"$wrong_origin_output" ||
  fail "unofficial source origin message"
QVOS_TEST_ORIGIN=https://github.com/Yaqyn-qvOS/qvOS.git

set +e
invalid_output=$(run_wrapper --bad 2>&1)
invalid_status=$?
set -e
(( invalid_status == 2 )) || fail "invalid wrapper argument status"
grep -Fq 'Usage: qv update [-y|--check]' <<<"$invalid_output" ||
  fail "native wrapper usage"

set +e
QVOS_TEST_RUN_STATUS=7 failed_output=$(run_wrapper -y 2>&1)
failed_status=$?
set -e
(( failed_status == 7 )) || fail "update failure propagation"
! grep -Fq 'qvOS update is complete.' <<<"$failed_output" ||
  fail "false completion after update failure"
pass "qvOS preflights, confirms, and delegates exactly once"

# Native and inherited adapters must share the same singular owner.
adapter_fixture="$test_root/adapter-fixture"
install -d "$adapter_fixture/qvcore/update"
install -m 0755 /dev/stdin "$adapter_fixture/qvcore/update/qvos-update" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_ADAPTER_LOG"
SCRIPT
for adapter in qv-update omarchy-update; do
  adapter_log="$test_root/$adapter.log"
  QVOS_PATH="$adapter_fixture" QVOS_TEST_ADAPTER_LOG="$adapter_log" \
    "$root/bin/$adapter" -y
  [[ $(<"$adapter_log") == "-y" ]] || fail "update adapter: $adapter"
done
pass "native and inherited update routes share one owner"

# The fixed private session log rejects link attacks and uses private modes.
log_home="$test_root/log-home"
install -d "$log_home"
log_path=$(HOME="$log_home" "$root/qvcore/update/log-path" prepare)
[[ $log_path == "$log_home/.local/state/qvos/update/update.log" ]] ||
  fail "fixed update log path"
[[ $(stat -c '%a' "${log_path%/*}") == "700" ]] || fail "update log directory mode"
[[ $(stat -c '%a' "$log_path") == "600" ]] || fail "update log mode"
rm -f -- "$log_path"
ln -s "$test_root/unsafe-target" "$log_path"
if HOME="$log_home" "$root/qvcore/update/log-path" prepare >/dev/null 2>&1; then
  fail "update log symlink rejection"
fi
rm -f -- "$log_path"
pass "qvOS update logs are private and link-safe"

# Captured engine mode must serialize snapshot, source, and pipeline stages.
engine="$test_root/engine"
install -d "$engine/qvcore/update" "$test_root/engine-home" "$test_root/runtime"
install -m 0755 "$root/qvcore/update/log-path" "$engine/qvcore/update/log-path"
install -m 0755 /dev/stdin "$engine/qvcore/update/snapshot" <<'SCRIPT'
#!/bin/bash
printf 'snapshot\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit "${QVOS_TEST_SNAPSHOT_STATUS:-0}"
SCRIPT
install -m 0755 /dev/stdin "$engine/qvcore/update/update-source" <<'SCRIPT'
#!/bin/bash
printf 'update-source\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit "${QVOS_TEST_UPDATE_SOURCE_STATUS:-0}"
SCRIPT
install -m 0755 /dev/stdin "$engine/qvcore/update/perform" <<'SCRIPT'
#!/bin/bash
printf 'perform\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit "${QVOS_TEST_PERFORM_STATUS:-0}"
SCRIPT
engine_log=$(HOME="$test_root/engine-home" QVOS_PATH="$engine" \
  "$engine/qvcore/update/log-path" prepare)
: >"$action_log"
HOME="$test_root/engine-home" \
  XDG_RUNTIME_DIR="$test_root/runtime" \
  QVOS_PATH="$engine" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  QVOS_UPDATE_CAPTURED=1 \
  QVOS_UPDATE_LOG_PATH="$engine_log" \
  "$root/qvcore/update/run"
[[ $(<"$action_log") == $'snapshot\tcreate\nupdate-source\t\nperform\t' ]] ||
  fail "native engine stage order"

: >"$action_log"
HOME="$test_root/engine-home" \
  XDG_RUNTIME_DIR="$test_root/runtime" \
  QVOS_PATH="$engine" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  QVOS_TEST_SNAPSHOT_STATUS=127 \
  QVOS_UPDATE_CAPTURED=1 \
  QVOS_UPDATE_LOG_PATH="$engine_log" \
  "$root/qvcore/update/run"
grep -Fqx $'perform\t' "$action_log" || fail "optional snapshot absence"

set +e
engine_failure=$(
  HOME="$test_root/engine-home" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QVOS_PATH="$engine" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_UPDATE_SOURCE_STATUS=9 \
    QVOS_UPDATE_CAPTURED=1 \
    QVOS_UPDATE_LOG_PATH="$engine_log" \
    "$root/qvcore/update/run" 2>&1
)
engine_failure_status=$?
set -e
(( engine_failure_status == 9 )) || fail "native engine failure status"
grep -Fq "$engine_log" <<<"$engine_failure" || fail "native engine failure log guidance"

exec 8>>"$test_root/runtime/qvos-update.lock"
flock -n 8 || fail "update lock fixture"
set +e
lock_output=$(
  HOME="$test_root/engine-home" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QVOS_PATH="$engine" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_UPDATE_CAPTURED=1 \
    QVOS_UPDATE_LOG_PATH="$engine_log" \
    "$root/qvcore/update/run" 2>&1
)
lock_status=$?
set -e
flock -u 8
exec 8>&-
(( lock_status == 1 )) || fail "concurrent update lock status"
grep -Fq 'another update is already running' <<<"$lock_output" ||
  fail "concurrent update lock message"
pass "qvOS update engine orders and reports its transaction safely"

# The pipeline always removes no-idle and stops at the first failed stage.
pipeline="$test_root/pipeline"
install -d "$pipeline/qvcore/packages" "$pipeline/qvcore/update" "$pipeline/qvcore/migrations"
for stage in update-keyring update-system update-aur remove-orphans; do
  install -m 0755 /dev/stdin "$pipeline/qvcore/packages/$stage" <<SCRIPT
#!/bin/bash
printf '$stage\\n' >>"\$QVOS_TEST_ACTION_LOG"
[[ '$stage' != "\${QVOS_TEST_FAIL_STAGE:-}" ]]
SCRIPT
done
install -m 0755 /dev/stdin "$pipeline/qvcore/update/available-reset" <<'SCRIPT'
#!/bin/bash
printf 'available-reset\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$pipeline/qvcore/update/analyze-log" <<'SCRIPT'
#!/bin/bash
printf 'analyze-log\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$pipeline/qvcore/update/restart" <<'SCRIPT'
#!/bin/bash
printf 'restart\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$pipeline/qvcore/migrations/run" <<'SCRIPT'
#!/bin/bash
printf 'migrations\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf 'hyprctl:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hook" <<'SCRIPT'
#!/bin/bash
printf 'hook:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

: >"$action_log"
QVOS_PATH="$pipeline" QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" "$root/qvcore/update/perform"
[[ $(tail -n 1 "$action_log") == 'hyprctl:dispatch tagwindow -- -noidle' ]] ||
  fail "successful no-idle cleanup"

: >"$action_log"
set +e
QVOS_PATH="$pipeline" QVOS_TEST_ACTION_LOG="$action_log" \
  QVOS_TEST_FAIL_STAGE=update-system PATH="$test_bin:/usr/bin" \
  "$root/qvcore/update/perform" >/dev/null 2>&1
pipeline_failure_status=$?
set -e
(( pipeline_failure_status != 0 )) || fail "pipeline stage failure status"
[[ $(tail -n 1 "$action_log") == 'hyprctl:dispatch tagwindow -- -noidle' ]] ||
  fail "failed no-idle cleanup"
! grep -Fq 'migrations' "$action_log" || fail "pipeline continued after failure"
pass "qvOS update cleanup runs after success and failure"

# Package update owners preserve argument boundaries and truthful failures.
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo' >>"$QVOS_TEST_ACTION_LOG"
printf '\t%s' "$@" >>"$QVOS_TEST_ACTION_LOG"
printf '\n' >>"$QVOS_TEST_ACTION_LOG"
if [[ ${1:-} == "snapper" && ${2:-} == "--csvout" ]]; then
  printf 'Config,Subvolume\nroot,/\ninvalid name,/bad\nhome,/home\n'
fi
if [[ ${1:-} == "systemctl" && ${2:-} == "is-active" ]]; then
  exit "${QVOS_TEST_ACTIVE_STATUS:-0}"
fi
SCRIPT

: >"$action_log"
QVOS_TEST_ACTION_LOG="$action_log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/packages/update-system" >/dev/null
[[ $(<"$action_log") == $'sudo\tpacman\t-Syu\t--noconfirm' ]] ||
  fail "system package update arguments"

keyring_fixture="$test_root/keyring-fixture"
install -d "$keyring_fixture/qvcore/packages"
install -m 0755 /dev/stdin "$keyring_fixture/qvcore/packages/missing" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
: >"$action_log"
QVOS_PATH="$keyring_fixture" QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" "$root/qvcore/packages/update-keyring" >/dev/null
grep -Fqx $'sudo\tpacman\t-Sy\t--noconfirm\t--\tarchlinux-keyring' "$action_log" ||
  fail "Arch keyring update arguments"
! grep -Fq -- '--recv-keys' "$action_log" ||
  fail "trusted provider key was imported again"

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
-Qtdq)
  if [[ -v QVOS_TEST_ORPHAN_OUTPUT ]]; then
    printf '%s' "$QVOS_TEST_ORPHAN_OUTPUT"
  else
    printf 'one\ntwo words\n'
  fi
  exit "${QVOS_TEST_ORPHAN_STATUS:-0}"
  ;;
-Qem) exit "${QVOS_TEST_FOREIGN_STATUS:-1}" ;;
*) exit 2 ;;
esac
SCRIPT
: >"$action_log"
QVOS_TEST_ACTION_LOG="$action_log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/packages/remove-orphans" >/dev/null
[[ $(<"$action_log") == $'sudo\tpacman\t-Rs\t--noconfirm\t--\tone\ttwo words' ]] ||
  fail "orphan cleanup argument boundaries"
: >"$action_log"
QVOS_TEST_ACTION_LOG="$action_log" QVOS_TEST_ORPHAN_OUTPUT="" \
  PATH="$test_bin:/usr/bin" "$root/qvcore/packages/remove-orphans" >/dev/null
[[ ! -s $action_log ]] || fail "empty orphan cleanup mutation"

aur_fixture="$test_root/aur-fixture"
install -d "$aur_fixture/qvcore/packages"
install -m 0755 /dev/stdin "$aur_fixture/qvcore/packages/aur-accessible" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/yay" <<'SCRIPT'
#!/bin/bash
printf 'yay:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
: >"$action_log"
QVOS_TEST_ACTION_LOG="$action_log" QVOS_TEST_FOREIGN_STATUS=0 \
  QVOS_PATH="$aur_fixture" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/packages/update-aur" >/dev/null
grep -Fqx 'yay:-Sua --noconfirm --cleanafter --ignore gcc14,gcc14-libs' "$action_log" ||
  fail "AUR update arguments"
pass "package update stages preserve exact targets and options"

# Availability follows the official OS commit, not upstream tags.
availability_work="$test_root/availability-work"
availability_remote="$test_root/availability.git"
availability_peer="$test_root/availability-peer"
install -d "$availability_work"
git -C "$availability_work" init -q -b OS
git -C "$availability_work" config user.name 'qvOS Test'
git -C "$availability_work" config user.email test@qvos.invalid
printf 'one\n' >"$availability_work/version"
git -C "$availability_work" add version
git -C "$availability_work" commit -qm initial
git clone -q --bare "$availability_work" "$availability_remote"
git -C "$availability_work" remote add origin "$availability_remote"
git -C "$availability_work" remote set-url origin \
  https://github.com/Yaqyn-qvOS/qvOS.git
availability_git_env=(
  GIT_ALLOW_PROTOCOL=file
  GIT_CONFIG_COUNT=1
  "GIT_CONFIG_KEY_0=url.file://$availability_remote.insteadOf"
  GIT_CONFIG_VALUE_0=https://github.com/Yaqyn-qvOS/qvOS.git
)

set +e
current_output=$(env "${availability_git_env[@]}" QVOS_PATH="$availability_work" \
  "$root/qvcore/update/update-available")
current_status=$?
set -e
(( current_status == 1 )) || fail "current availability status"
grep -Fq 'qvOS is up to date' <<<"$current_output" || fail "current availability output"

printf 'local\n' >>"$availability_work/version"
git -C "$availability_work" commit -qam local
set +e
ahead_output=$(env "${availability_git_env[@]}" QVOS_PATH="$availability_work" \
  "$root/qvcore/update/update-available")
ahead_status=$?
set -e
(( ahead_status == 1 )) || fail "local-ahead availability status"
grep -Fq 'locally ahead' <<<"$ahead_output" || fail "local-ahead availability output"

git clone -q "$availability_remote" "$availability_peer"
git -C "$availability_peer" config user.name 'qvOS Test'
git -C "$availability_peer" config user.email test@qvos.invalid
printf 'remote\n' >>"$availability_peer/version"
git -C "$availability_peer" commit -qam remote
git -C "$availability_peer" push -q origin OS
available_output=$(env "${availability_git_env[@]}" QVOS_PATH="$availability_work" \
  "$root/qvcore/update/update-available")
grep -Fq 'qvOS update available' <<<"$available_output" || fail "remote update output"
pass "qvOS update availability follows the official OS commit"

# Manual owners validate systemd, firmware, and snapshot handoffs without mutation.
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit "${QVOS_TEST_ACTIVE_STATUS:-0}"
SCRIPT
: >"$action_log"
QVOS_TEST_ACTION_LOG="$action_log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/update/time-sync" >/dev/null
[[ $(<"$action_log") == $'sudo\tsystemctl\trestart\tsystemd-timesyncd.service\nsystemctl:is-active --quiet systemd-timesyncd.service' ]] ||
  fail "time synchronization verification"

install -m 0755 /dev/stdin "$test_bin/fwupdmgr" <<'SCRIPT'
#!/bin/bash
printf 'fwupdmgr:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/snapper" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
: >"$action_log"
QVOS_TEST_ACTION_LOG="$action_log" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/update/firmware" >/dev/null
grep -Fqx 'fwupdmgr:refresh --force' "$action_log" || fail "firmware refresh"
grep -Fqx $'sudo\tfwupdmgr\tupdate' "$action_log" || fail "firmware update"

snapshot_fixture="$test_root/snapshot-fixture"
install -d "$snapshot_fixture"
printf '1.0-test\n' >"$snapshot_fixture/version"
: >"$action_log"
QVOS_PATH="$snapshot_fixture" QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" "$root/qvcore/update/snapshot" create >/dev/null
grep -Fqx $'sudo\tsnapper\t-c\troot\tcreate\t-c\tnumber\t-d\tqvOS 1.0-test' "$action_log" ||
  fail "root snapshot creation"
grep -Fqx $'sudo\tsnapper\t-c\thome\tcreate\t-c\tnumber\t-d\tqvOS 1.0-test' "$action_log" ||
  fail "home snapshot creation"
! grep -Fq 'invalid name' "$action_log" || fail "invalid snapshot config filtering"
install -d "$test_root/empty-bin"
set +e
PATH="$test_root/empty-bin" /bin/bash "$root/qvcore/update/snapshot" create >/dev/null 2>&1
snapshot_absent_status=$?
set -e
(( snapshot_absent_status == 127 )) || fail "optional Snapper absence status"
pass "manual update owners validate their exact system handoffs"

# TUI adapter uses native names, the private log, and qvOS reboot deferral.
install -m 0755 /dev/stdin "$test_bin/qv-update" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_TUI_LOG"
printf '%s\t%s\t%s\n' \
  "${QVOS_UPDATE_CAPTURED:-}" \
  "${QVOS_UPDATE_DEFER_REBOOT:-}" \
  "${QVOS_UPDATE_LOG_PATH:-}" \
  >"$QVOS_TEST_TUI_ENV_LOG"
exit "${QVOS_TEST_TUI_STATUS:-0}"
SCRIPT
tui_home="$test_root/tui-home"
install -d "$tui_home"
tui_log="$test_root/tui-action.log"
tui_env="$test_root/tui-env.log"
QVOS_PATH="$root" HOME="$tui_home" PATH="$test_bin:/usr/bin" \
  QVOS_TEST_TUI_LOG="$tui_log" QVOS_TEST_TUI_ENV_LOG="$tui_env" \
  "$root/qvcore/tui/update/run" >/dev/null
[[ $(<"$tui_log") == "-y" ]] || fail "TUI update delegation"
expected_tui_log="$tui_home/.local/state/qvos/update/update.log"
[[ $(<"$tui_env") == $'1\t1\t'"$expected_tui_log" ]] ||
  fail "TUI captured update environment"
[[ -f $expected_tui_log && $(stat -c '%a' "$expected_tui_log") == "600" ]] ||
  fail "TUI private session log"

install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT
launch_log="$test_root/launch.log"
QVOS_TEST_LAUNCH_LOG="$launch_log" QVOS_PATH="$root" \
  PATH="$test_bin:/usr/bin" "$root/qvcore/tui/update/launch"
[[ $(<"$launch_log") == 'uwsm-app -- xdg-terminal-exec --app-id=org.qvos.tui --title=qvOS Update -e qv-update' ]] ||
  fail "native TUI update launch"

deferred_output=$(QVOS_UPDATE_DEFER_REBOOT=1 \
  "$root/qvcore/update/reboot-request" "Kernel updated" "Reboot?")
grep -Fqx 'qvOS action: reboot required: Kernel updated' <<<"$deferred_output" ||
  fail "native deferred reboot signal"
pass "qvOS TUI uses the native update route and private session state"
