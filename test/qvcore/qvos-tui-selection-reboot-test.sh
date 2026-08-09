#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
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

install -d \
  "$test_home/.config" \
  "$test_home/.config/omarchy/themes/Alpha" \
  "$test_home/.config/omarchy/themes/Zeta" \
  "$test_home/.local/share/applications/icons" \
  "$test_bin"
touch "$action_log"

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'unexpected gum:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exit 97
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ ${1:-} == "tee" ]]; then
  cat >/dev/null
  exit
fi
"$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/timedatectl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
list-timezones)
  printf 'Africa/Cairo\nEurope/London\n'
  ;;
set-timezone)
  printf 'timezone:%s\n' "$2" >>"$QVOS_TEST_ACTION_LOG"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-restart-walker" <<'SCRIPT'
#!/bin/bash
printf 'restart-walker\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
ln -s qv-restart-walker "$test_bin/omarchy-restart-walker"
install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'pkg-add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
ln -s omarchy-pkg-add "$test_bin/qv-pkg-add"
install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-aur-add" <<'SCRIPT'
#!/bin/bash
printf 'pkg-aur-add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
ln -s omarchy-pkg-aur-add "$test_bin/qv-pkg-aur-add"
install -m 0755 /dev/stdin "$test_bin/voxtype" <<'SCRIPT'
#!/bin/bash
printf 'voxtype:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-hw-vulkan" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
for command_name in \
  notify-send \
  qv-restart-waybar \
  systemctl \
  usermod \
  modprobe; do
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash
printf '%s:%s\n' "$(basename "$0")" "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
done
install -m 0755 /dev/stdin "$test_bin/id" <<'SCRIPT'
#!/bin/bash
[[ $1 == "-nG" ]] || exit 2
printf 'qv wheel\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/lsmod" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

run_owner() {
  HOME="$test_home" \
    USER=qv \
    QVOS_PATH="$root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

software_owner() {
  local slug=$1
  local field=$2

  awk -F '|' -v wanted="$slug" -v wanted_field="$field" '
    $1 == wanted {
      print $wanted_field
      found = 1
      exit
    }
    END { exit !found }
  ' "$root/qvcore/menu/software-actions.psv"
}

installer_owner() {
  local slug=$1

  awk -F '|' -v wanted="$slug" '
    $1 == wanted {
      print $11
      found = 1
      exit
    }
    END { exit !found }
  ' "$root/qvcore/menu/software-installers.psv"
}

[[ $(software_owner dictation 8) == "qv-voxtype-install --yes" ]] ||
  fail "Dictation catalog lost its noninteractive owner contract"
[[ $(software_owner xbox-controller 8) == "qv-install-gaming-xbox-controllers --defer-reboot" ]] ||
  fail "Xbox Controllers catalog lost its deferred reboot contract"
[[ $(software_owner proton 9) == "services/proton/manage remove --yes" &&
$(software_owner devel 9) == "development/devel/manage remove --yes" ]] ||
  fail "optional integration removal catalog lost its noninteractive owner contract"
[[ $(installer_owner nordvpn) == "qv-install-nordvpn --defer-reboot" ]] ||
  fail "NordVPN catalog lost its deferred reboot contract"

while IFS= read -r owner; do
  read -r owner_command _ <<<"$owner"
  if [[ $owner_command == qvcore/* ]]; then
    owner_source="$root/$owner_command"
  elif [[ -f $root/bin/$owner_command ]]; then
    owner_source="$root/bin/$owner_command"
  else
    continue
  fi

  if grep -Eq '(^|[[:space:]])gum([[:space:]]|$)' "$owner_source" &&
    [[ $owner != *" --"* &&
      $owner != "development/devel/manage install" ]]; then
    fail "captured Gum owner lacks an explicit noninteractive option: $owner"
  fi
done < <(
  awk -F '|' '
    $1 !~ /^#/ {
      if ($4 == "tui") print $8
      if ($6 == "tui") print $9
    }
  ' "$root/qvcore/menu/software-actions.psv"
  awk -F '|' '$1 !~ /^#/ && $6 == "tui" { print $11 }' \
    "$root/qvcore/menu/software-installers.psv"
  awk -F '|' '$1 !~ /^#/ && $6 == "tui" { print $11 }' \
    "$root/qvcore/tui/task/actions.psv"
)

theme_options=$(run_owner "$root/qvcore/tui/task/selectable-owner" theme-remove --list)
[[ $theme_options == $'Alpha\nZeta' ]] ||
  fail "Extra Theme selection inventory"
run_owner "$root/qvcore/tui/task/selectable-owner" theme-remove -- Alpha
[[ ! -e $test_home/.config/omarchy/themes/Alpha ]] ||
  fail "Extra Theme selected delegation"

install -m 0644 /dev/stdin "$test_home/.local/share/applications/My Web.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=omarchy-launch-webapp https://example.com
DESKTOP
touch "$test_home/.local/share/applications/icons/My Web.png"

[[ $(run_owner "$root/qvcore/tui/task/selectable-owner" webapp-remove --list) == "My Web" ]] ||
  fail "Web App searchable selection inventory"
selection_error="$test_root/selection-error.log"
run_owner "$root/qvcore/tui/task/selectable-owner" webapp-remove -- "My Web" \
  >/dev/null 2>"$selection_error"
[[ ! -s $selection_error ]] || fail "web app removal emitted warnings"
grep -Fqx 'restart-walker' "$action_log" || fail "web app removal restarted Walker"
[[ ! -e "$test_home/.local/share/applications/My Web.desktop" ]] ||
  fail "Web App multi-selection delegation"

[[ $(run_owner "$root/qvcore/tui/task/selectable-owner" timezone --list) == $'Africa/Cairo\nEurope/London' ]] ||
  fail "Timezone searchable selection inventory"
run_owner "$root/qvcore/tui/task/selectable-owner" timezone -- Africa/Cairo >/dev/null
grep -Fqx 'timezone:Africa/Cairo' "$action_log" ||
  fail "Timezone selected delegation"
grep -Fqx 'sudo:timedatectl set-timezone Africa/Cairo' "$action_log" ||
  fail "Timezone selected privilege boundary"
if run_owner "$root/qvcore/config/timezone" -- Etc/Unknown >/dev/null 2>&1; then
  fail "Timezone owner accepted a selection outside its current inventory"
fi
if grep -Fq 'set-timezone Etc/Unknown' "$action_log"; then
  fail "Invalid timezone reached the privileged mutation"
fi

run_owner "$root/bin/qv-voxtype-install" --yes >/dev/null
grep -Fqx 'pkg-add:voxtype-bin' "$action_log" ||
  fail "Dictation noninteractive TUI owner"

nord_output=$(run_owner "$root/bin/qv-install-nordvpn" --defer-reboot)
grep -Fqx 'qvOS action: reboot required: NordVPN group membership changed' \
  <<<"$nord_output" ||
  fail "NordVPN deferred reboot signal"

xbox_output=$(run_owner "$root/bin/qv-install-gaming-xbox-controllers" --defer-reboot)
grep -Fqx 'qvOS action: reboot required: Xbox controller setup needs a reboot' \
  <<<"$xbox_output" ||
  fail "Xbox Controllers deferred reboot signal"

if grep -Fq 'unexpected gum:' "$action_log"; then
  fail "converted owners retained nested native prompts"
fi

printf 'ok - converted owners expose searchable choices and deferred reboot results\n'
