#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
config_manifest="$test_root/font-configs"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

config_paths=(
  "$test_home/.config/alacritty/alacritty.toml"
  "$test_home/.config/kitty/kitty.conf"
  "$test_home/.config/ghostty/config"
  "$test_home/.config/foot/foot.ini"
  "$test_home/.config/hypr/hyprlock.conf"
  "$test_home/.config/waybar/style.css"
  "$test_home/.config/swayosd/style.css"
  "$test_home/.config/fontconfig/fonts.conf"
)

install -d \
  "$test_bin" \
  "$test_root/runtime" \
  "$test_home/.local/share/qvos/menu"
install -m 0755 \
  "$root/qv/menu/font-install" \
  "$test_home/.local/share/qvos/menu/font-install"
for path in "${config_paths[@]}"; do
  install -d "$(dirname -- "$path")"
  printf 'font=JetBrainsMono Nerd Font\n' >"$path"
  printf '%s\n' "$path" >>"$config_manifest"
done
cp -a -- "$test_home/.config" "$test_root/config-before"

install -m 0755 /dev/stdin "$test_bin/omarchy-font-current" <<'SCRIPT'
#!/bin/bash
IFS= read -r path <"$QVOS_TEST_FONT_CONFIGS"
sed -n 's/^font=//p' "$path"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-font-set" <<'SCRIPT'
#!/bin/bash
font=${1:-}
[[ -n $font ]] || exit 2
[[ -z ${QVOS_TEST_FONT_LOG:-} ]] || printf 'font\t%s\n' "$font" >>"$QVOS_TEST_FONT_LOG"
while IFS= read -r path; do
  printf 'font=%s\n' "$font" >"$path"
done <"$QVOS_TEST_FONT_CONFIGS"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
touch "$QVOS_TEST_PACKAGE_MARKER"
SCRIPT
for command in omarchy-restart-waybar omarchy-restart-swayosd; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
done
install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
-Q|-Qq)
  [[ -e $QVOS_TEST_PACKAGE_MARKER ]] || exit 1
  printf 'ttf-meslo-nerd\n'
  ;;
-Rn)
  printf 'pacman\t%s\n' "$*" >>"$QVOS_TEST_FONT_LOG"
  rm -f -- "$QVOS_TEST_PACKAGE_MARKER"
  ;;
*)
  exit 1
  ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$QVOS_TEST_FONT_LOG"
exec "$@"
SCRIPT

export HOME="$test_home"
export OMARCHY_PATH="$root"
export PATH="$test_bin:/usr/bin"
export XDG_RUNTIME_DIR="$test_root/runtime"
export QVOS_TEST_FONT_CONFIGS="$config_manifest"
export QVOS_TEST_PACKAGE_MARKER="$test_root/meslo-installed"
export QVOS_TEST_FONT_LOG="$test_root/font.log"
export QVOS_ACTION_SLUG=font-meslo-mono
export QVOS_ACTION_OPERATION=install
export QVOS_ACTION_ROLLBACK=owner-state-v1
export QVOS_ACTION_ROLLBACK_STATE="$test_root/runtime/rollback-state"

"$root/qv/tui/action/run-installer" --check
"$root/qv/tui/action/run-installer" >/dev/null
[[ $(omarchy-font-current) == "MesloLGL Nerd Font" ]] ||
  fail "font owner did not apply the selected font"
"$root/qv/tui/action/run-installer" --rollback

[[ $(omarchy-font-current) == "JetBrainsMono Nerd Font" ]] ||
  fail "font rollback did not restore the previous active font"
for path in "${config_paths[@]}"; do
  relative=${path#"$test_home/.config/"}
  cmp -s -- "$path" "$test_root/config-before/$relative" ||
    fail "font rollback did not restore $relative"
done
printf 'ok - completed font Stop restores the exact pre-install configuration\n'

export QVOS_ACTION_OPERATION=task
export QVOS_ACTION_SELECTIONS="Apply Now"
export QVOS_FONT_STATE=installed
[[ $("$root/qv/tui/action/font-run" --options) == $'Apply Now\nUninstall' ]] ||
  fail "installed inactive font actions"
"$root/qv/tui/action/font-run" --check
"$root/qv/tui/action/font-run" >/dev/null
[[ $(omarchy-font-current) == "MesloLGL Nerd Font" ]] ||
  fail "font Apply did not activate the installed font"
if "$root/qv/tui/action/font-run" --rollback >/dev/null 2>&1; then
  fail "font Apply retained obsolete Stop rollback plumbing"
fi
printf 'ok - installed font Apply completes without Stop plumbing\n'

"$test_bin/omarchy-font-set" "MesloLGL Nerd Font"
: >"$QVOS_TEST_FONT_LOG"
export QVOS_ACTION_SELECTIONS=Uninstall
export QVOS_ACTION_ROLLBACK=
export QVOS_FONT_STATE=active
[[ $("$root/qv/tui/action/font-run" --options) == "Uninstall" ]] ||
  fail "active font offered an action besides Uninstall"
if QVOS_ACTION_SELECTIONS="Apply Now" \
  "$root/qv/tui/action/font-run" >/dev/null 2>&1; then
  fail "active font accepted the obsolete Apply action"
fi
"$root/qv/tui/action/font-run" --check
"$root/qv/tui/action/font-run" >/dev/null
[[ ! -e $QVOS_TEST_PACKAGE_MARKER ]] ||
  fail "font Uninstall left the package installed"
[[ $(omarchy-font-current) == "JetBrainsMono Nerd Font" ]] ||
  fail "active font Uninstall did not restore JetBrains Mono"
[[ $(sed -n '1p' "$QVOS_TEST_FONT_LOG") == $'font\tJetBrainsMono Nerd Font' ]] ||
  fail "font Uninstall did not restore JetBrains Mono before package removal"
grep -Fqx $'sudo\tpacman -Rn --noconfirm -- ttf-meslo-nerd' "$QVOS_TEST_FONT_LOG" ||
  fail "font Uninstall did not use the exact package owner through sudo"
printf 'ok - active font Uninstall restores the default before exact removal\n'

touch "$QVOS_TEST_PACKAGE_MARKER"

second_state="$test_root/runtime/second-state"
"$root/qv/menu/font-install" meslo-mono --qvos-rollback-snapshot "$second_state"
"$test_bin/omarchy-font-set" "MesloLGL Nerd Font"
"$root/qv/menu/font-install" meslo-mono --qvos-rollback-seal "$second_state"
printf 'foreign change\n' >>"${config_paths[0]}"
if "$root/qv/menu/font-install" meslo-mono --qvos-rollback-restore "$second_state"; then
  fail "font rollback overwrote a concurrent config change"
fi
grep -Fqx 'foreign change' "${config_paths[0]}" ||
  fail "font rollback discarded the concurrent config change"
printf 'ok - font Stop preserves concurrently changed configuration\n'

sed -i '/foreign change/d' "${config_paths[0]}"
"$test_bin/omarchy-font-set" "JetBrainsMono Nerd Font"
font_route=$(
  bash -s -- "$root/qv/menu/extension.sh" <<'SCRIPT'
set -euo pipefail
source "$1"

menu() {
  printf '  Meslo LG Mono\n'
}

launch_font() {
  printf '%s\n' "$1"
}

show_install_font_menu
SCRIPT
)
[[ $font_route == "font-meslo-mono" ]] ||
  fail "font menu did not hand the selected font directly to the TUI"
printf 'ok - font menu delegates lifecycle choices to the shared TUI\n'

font_tui="$test_root/font-tui"
font_launch_log="$test_root/font-launch.log"
install -d "$font_tui/action"
install -m 0755 "$root/qv/tui/action/font-launch" "$font_tui/action/font-launch"
install -m 0755 "$root/qv/tui/owner-resolver" "$font_tui/owner-resolver"
install -m 0755 /dev/stdin "$font_tui/launch" <<'SCRIPT'
#!/bin/bash
{
  printf 'operation\t%s\n' "$QVOS_ACTION_OPERATION"
  printf 'sudo\t%s\n' "$QVOS_ACTION_REQUIRES_SUDO"
  printf 'primary\t%s\n' "$QVOS_ACTION_PRIMARY"
  printf 'rollback\t%s\n' "${QVOS_ACTION_ROLLBACK:-}"
  printf 'selection\t%s\n' "$QVOS_ACTION_SELECTION_MODE"
  printf 'summary-selection\t%s\n' "$QVOS_ACTION_SUMMARY_SELECTION"
  printf 'font-state\t%s\n' "$QVOS_FONT_STATE"
  printf 'selection-title\t%s\n' "$QVOS_ACTION_SELECTION_TITLE"
  printf 'script\t%s\n' "$QVOS_ACTION_SCRIPT"
} >"$QVOS_TEST_FONT_LAUNCH_LOG"
SCRIPT

touch "$QVOS_TEST_PACKAGE_MARKER"
"$test_bin/omarchy-font-set" "JetBrainsMono Nerd Font"
export QVOS_ACTION_ROLLBACK=owner-state-v1
QVOS_TEST_FONT_LAUNCH_LOG="$font_launch_log" \
  "$font_tui/action/font-launch" font-meslo-mono
grep -Fqx $'operation\ttask' "$font_launch_log" ||
  fail "font lifecycle did not use the custom mutation contract"
grep -Fqx $'sudo\t0' "$font_launch_log" ||
  fail "font lifecycle authorized before the user chose Uninstall"
grep -Fqx $'primary\tApply' "$font_launch_log" ||
  fail "font Apply action copy changed"
grep -Fqx $'rollback\t' "$font_launch_log" ||
  fail "font Apply retained obsolete Stop rollback state"
grep -Fqx $'selection\taction' "$font_launch_log" ||
  fail "font lifecycle choices were not assigned to the TUI"
grep -Fqx $'summary-selection\tUninstall' "$font_launch_log" ||
  fail "font Uninstall was not marked as the summary branch"
grep -Fqx $'font-state\tinstalled' "$font_launch_log" ||
  fail "inactive font state was not captured by the TUI adapter"
grep -Fqx $'selection-title\tMeslo LG Mono' "$font_launch_log" ||
  fail "inactive font action title"
printf 'ok - installed inactive font offers Apply Now or Uninstall\n'

"$test_bin/omarchy-font-set" "MesloLGL Nerd Font"
QVOS_TEST_FONT_LAUNCH_LOG="$font_launch_log" \
  "$font_tui/action/font-launch" font-meslo-mono
grep -Fqx $'font-state\tactive' "$font_launch_log" ||
  fail "active font state was not captured by the TUI adapter"
grep -Fqx $'selection-title\tMeslo LG Mono · Already Applied' "$font_launch_log" ||
  fail "active font did not show Already Applied status"
printf 'ok - active font shows Already Applied with Uninstall\n'

install -m 0755 /dev/stdin "$font_tui/action/launch" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_FONT_LAUNCH_LOG"
SCRIPT
rm -f -- "$QVOS_TEST_PACKAGE_MARKER"
unset QVOS_FONT_STATE
QVOS_TEST_FONT_LAUNCH_LOG="$font_launch_log" \
  "$font_tui/action/font-launch" font-meslo-mono
[[ $(<"$font_launch_log") == "--installer font-meslo-mono" ]] ||
  fail "available font did not open Install directly"
printf 'ok - available font keeps the direct Install TUI route\n'
