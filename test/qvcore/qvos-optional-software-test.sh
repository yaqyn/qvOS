#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
fixture="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$fixture/bin" \
  "$fixture/qvcore/software" \
  "$fixture/qvcore/theme" \
  "$test_bin"
for route in \
  omarchy-install-nordvpn \
  omarchy-install-vscode \
  omarchy-voxtype-config \
  omarchy-voxtype-install \
  omarchy-voxtype-model \
  omarchy-voxtype-remove \
  omarchy-voxtype-status \
  qv-install-nordvpn \
  qv-install-vscode \
  qv-voxtype-config \
  qv-voxtype-install \
  qv-voxtype-model \
  qv-voxtype-remove \
  qv-voxtype-status; do
  install -m 0755 "$root/bin/$route" "$fixture/bin/$route"
done
for owner in \
  nordvpn-install \
  vscode-install \
  voxtype-config \
  voxtype-install \
  voxtype-model \
  voxtype-remove \
  voxtype-status; do
  install -m 0755 "$root/qvcore/software/$owner" "$fixture/qvcore/software/$owner"
done
printf 'language = "en"\n' >"$fixture/qvcore/software/voxtype-config.toml"
install -m 0755 /dev/stdin "$fixture/qvcore/theme/install-vscode" <<'STUB'
#!/bin/bash
printf 'install-vscode-theme\n' >>"$QVOS_TEST_ACTION_LOG"
STUB

install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg-add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-aur-add" <<'STUB'
#!/bin/bash
printf 'aur-add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-drop" <<'STUB'
#!/bin/bash
printf 'pkg-drop:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-theme-set-vscode" <<'STUB'
#!/bin/bash
printf 'set-vscode-theme\n' >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/gtk-launch" <<'STUB'
#!/bin/bash
printf 'unexpected-launch:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/setsid" <<'STUB'
#!/bin/bash
printf 'unexpected-setsid:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/gum" <<'STUB'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit "${QVOS_TEST_GUM_STATUS:-0}"
STUB
install -m 0755 /dev/stdin "$test_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/id" <<'STUB'
#!/bin/bash
[[ $1 == "-nG" ]] || exit 2
printf 'qv%s\n' "${QVOS_TEST_GROUPS:+ $QVOS_TEST_GROUPS}"
STUB
install -m 0755 /dev/stdin "$test_bin/voxtype" <<'STUB'
#!/bin/bash
if [[ ${1:-} == "status" ]]; then
  if [[ ${QVOS_TEST_VOXTYPE_FOLLOW:-0} == "1" ]]; then
    printf '%s\n' "$BASHPID" >"$QVOS_TEST_VOXTYPE_PID_FILE"
    trap 'printf "voxtype-terminated:%s\n" "$BASHPID" >>"$QVOS_TEST_ACTION_LOG"; exit 0' TERM
    while :; do
      :
    done
  fi
  printf '{"class":"idle","tooltip":"Ready"}\n'
  exit 0
fi
printf 'voxtype:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-hw-vulkan" <<'STUB'
#!/bin/bash
exit 1
STUB
install -m 0755 /dev/stdin "$test_bin/qv-restart-waybar" <<'STUB'
#!/bin/bash
printf 'restart-waybar\n' >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/notify-send" <<'STUB'
#!/bin/bash
printf 'notify\n' >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'STUB'
#!/bin/bash
for command_name in "$@"; do
  [[ " ${QVOS_TEST_MISSING_COMMANDS:-} " != *" $command_name "* ]] || exit 1
done
exit 0
STUB
install -m 0755 /dev/stdin "$test_bin/qv-launch-editor" <<'STUB'
#!/bin/bash
printf 'launch-editor:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin \
  "$test_bin/qv-launch-floating-terminal-with-presentation" <<'STUB'
#!/bin/bash
printf 'presentation:' >>"$QVOS_TEST_ACTION_LOG"
printf '<%s>' "$@" >>"$QVOS_TEST_ACTION_LOG"
printf '\n' >>"$QVOS_TEST_ACTION_LOG"
STUB

touch "$action_log"
run_software() {
  HOME="$test_home" \
    USER=qv \
    QVOS_PATH="$fixture" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$@"
}

argv_file="$test_home/.vscode/argv.json"
settings_file="$test_home/.config/Code/User/settings.json"
install -D -m 0600 /dev/stdin "$argv_file" <<'ARGV'
{"custom":true}
ARGV
install -D -m 0600 /dev/stdin "$settings_file" <<'SETTINGS'
{"editor.fontSize":17}
SETTINGS
cp "$argv_file" "$test_root/argv.before"
cp "$settings_file" "$test_root/settings.before"
run_software "$fixture/bin/qv-install-vscode" >/dev/null
cmp -s "$test_root/argv.before" "$argv_file" ||
  fail "VS Code argv preservation"
cmp -s "$test_root/settings.before" "$settings_file" ||
  fail "VS Code settings preservation"
grep -Fqx 'pkg-add:visual-studio-code-bin' "$action_log" ||
  fail "VS Code package owner"
if rg -q 'unexpected-(launch|setsid)' "$action_log"; then
  fail "captured VS Code install launched the application"
fi

config_file="$test_home/.config/voxtype/config.toml"
model_file="$test_home/.local/share/voxtype/models/model.bin"
unit_file="$test_home/.config/systemd/user/voxtype.service"
install -D -m 0600 /dev/stdin "$config_file" <<'CONFIG'
language = "custom"
CONFIG
install -D -m 0600 /dev/stdin "$model_file" <<'MODEL'
model
MODEL
install -D -m 0644 /dev/stdin "$unit_file" <<'UNIT'
[Service]
ExecStart=voxtype daemon
UNIT
run_software "$fixture/bin/qv-voxtype-install" --yes >/dev/null
grep -Fqx 'language = "custom"' "$config_file" ||
  fail "Voxtype config preservation"
grep -Fqx 'pkg-add:voxtype-bin' "$action_log" ||
  fail "Voxtype singular package owner"
if grep -Fq 'pkg-add:wtype' "$action_log"; then
  fail "Voxtype install claimed qvOS base wtype"
fi

rm -- "$config_file"
run_software "$fixture/bin/qv-voxtype-install" --yes >/dev/null
grep -Fqx 'language = "en"' "$config_file" ||
  fail "Voxtype native configuration seed"
[[ $(stat -c '%a' "$config_file") == "644" ]] ||
  fail "Voxtype native configuration seed mode"

: >"$action_log"
run_software "$fixture/bin/qv-voxtype-config"
grep -Fqx "launch-editor:$config_file" "$action_log" ||
  fail "Voxtype native config owner"
run_software "$fixture/bin/omarchy-voxtype-config"
(( $(grep -Fxc "launch-editor:$config_file" "$action_log") == 2 )) ||
  fail "Voxtype compatibility config owner"

: >"$action_log"
run_software "$fixture/bin/qv-voxtype-model"
run_software "$fixture/bin/omarchy-voxtype-model"
(( $(grep -Fxc 'presentation:<voxtype><setup><model>' "$action_log") == 2 )) ||
  fail "Voxtype model exact argument boundaries"
if QVOS_TEST_MISSING_COMMANDS=voxtype run_software \
  "$fixture/bin/qv-voxtype-model" >/dev/null 2>&1; then
  fail "Voxtype missing model command rejection"
fi

status_output=$(run_software "$fixture/bin/qv-voxtype-status")
[[ $status_output == '{"class":"idle","tooltip":"Ready","alt":"idle"}' ]] ||
  fail "Voxtype native status transformation"
status_output=$(run_software "$fixture/bin/omarchy-voxtype-status")
[[ $status_output == '{"class":"idle","tooltip":"Ready","alt":"idle"}' ]] ||
  fail "Voxtype compatibility status transformation"
status_output=$(QVOS_TEST_MISSING_COMMANDS=voxtype run_software \
  "$fixture/bin/qv-voxtype-status")
[[ $status_output == '{"alt":"","tooltip":""}' ]] ||
  fail "Voxtype missing status fallback"
if run_software "$fixture/bin/qv-voxtype-status" unexpected >/dev/null 2>&1; then
  fail "Voxtype status argument rejection"
fi

follow_pid_file="$test_root/voxtype-follow.pid"
HOME="$test_home" \
  USER=qv \
  QVOS_PATH="$fixture" \
  OMARCHY_PATH="$fixture" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  QVOS_TEST_VOXTYPE_FOLLOW=1 \
  QVOS_TEST_VOXTYPE_PID_FILE="$follow_pid_file" \
  "$fixture/bin/qv-voxtype-status" >"$test_root/follow.out" &
status_owner_pid=$!
for _ in {1..200}; do
  [[ -s $follow_pid_file ]] && break
  sleep 0.01
done
[[ -s $follow_pid_file ]] || fail "Voxtype follower startup"
voxtype_follower_pid=$(<"$follow_pid_file")
sleep 30 &
unrelated_pid=$!
kill -TERM "$status_owner_pid"
set +e
wait "$status_owner_pid"
status_owner_result=$?
set -e
(( status_owner_result == 143 )) || fail "Voxtype status termination result"
if kill -0 "$voxtype_follower_pid" 2>/dev/null; then
  fail "Voxtype exact follower cleanup"
fi
kill -0 "$unrelated_pid" 2>/dev/null ||
  fail "Voxtype cleanup signaled an unrelated process"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true
grep -Fqx "voxtype-terminated:$voxtype_follower_pid" "$action_log" ||
  fail "Voxtype follower graceful termination"

run_software "$fixture/bin/qv-voxtype-remove" >/dev/null
[[ -f $config_file && -f $model_file ]] ||
  fail "Voxtype configuration or model removal"
[[ ! -e $unit_file ]] || fail "Voxtype exact service-unit cleanup"
grep -Fqx 'pkg-drop:voxtype-bin' "$action_log" ||
  fail "Voxtype singular package removal"

: >"$action_log"
set +e
QVOS_TEST_GUM_STATUS=1 run_software \
  "$fixture/bin/omarchy-voxtype-install" >/dev/null 2>&1
cancel_status=$?
set -e
(( cancel_status == 130 )) || fail "Voxtype direct cancellation status"
if grep -Fq 'pkg-add:' "$action_log"; then
  fail "Voxtype cancellation reached package mutation"
fi

: >"$action_log"
QVOS_TEST_GROUPS=nordvpn run_software \
  "$fixture/bin/omarchy-install-nordvpn" --defer-reboot >"$test_root/nordvpn.out"
if grep -Fq 'usermod' "$action_log" ||
  grep -Fq 'qvOS action: reboot required' "$test_root/nordvpn.out"; then
  fail "NordVPN requested redundant group mutation or reboot"
fi
: >"$action_log"
run_software "$fixture/bin/qv-install-nordvpn" --defer-reboot \
  >"$test_root/nordvpn-new-group.out"
grep -Fqx 'sudo:usermod -aG nordvpn qv' "$action_log" ||
  fail "NordVPN group mutation"
grep -Fqx 'qvOS action: reboot required: NordVPN group membership changed' \
  "$test_root/nordvpn-new-group.out" ||
  fail "NordVPN required reboot deferral"

"$root/qvcore/software/check"
printf 'ok - optional software preserves configuration, data, and base packages\n'
