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
  "$fixture/default/voxtype" \
  "$fixture/qvcore/software" \
  "$fixture/qvcore/theme" \
  "$test_bin"
for route in \
  omarchy-install-nordvpn \
  omarchy-install-vscode \
  omarchy-voxtype-install \
  omarchy-voxtype-remove \
  qv-install-nordvpn \
  qv-install-vscode \
  qv-voxtype-install \
  qv-voxtype-remove; do
  install -m 0755 "$root/bin/$route" "$fixture/bin/$route"
done
for owner in \
  nordvpn-install \
  vscode-install \
  voxtype-install \
  voxtype-remove; do
  install -m 0755 "$root/qvcore/software/$owner" "$fixture/qvcore/software/$owner"
done
printf 'language = "en"\n' >"$fixture/default/voxtype/config.toml"
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
exit 0
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
