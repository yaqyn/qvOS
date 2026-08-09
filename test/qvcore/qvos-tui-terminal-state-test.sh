#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_omarchy="$test_root/omarchy"
test_bin="$test_root/bin"
package_dir="$test_root/packages"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_home/.config" \
  "$test_home/.local/share/applications" \
  "$test_home/.local/lib/qvos/menu" \
  "$test_omarchy/bin" \
  "$test_omarchy/qvcore/menu" \
  "$package_dir"
install -m 0755 \
  "$root/qvcore/menu/terminal-action" \
  "$test_home/.local/lib/qvos/menu/terminal-action"
install -m 0755 \
  "$root/qvcore/menu/software-installer-state" \
  "$test_omarchy/qvcore/menu/software-installer-state"
install -m 0644 \
  "$root/qvcore/menu/software-installers.psv" \
  "$test_omarchy/qvcore/menu/software-installers.psv"

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
-Q)
  [[ -e $QVOS_TEST_PACKAGE_DIR/$2 ]] || exit 1
  printf '%s 1.0\n' "$2"
  ;;
-Qq)
  find "$QVOS_TEST_PACKAGE_DIR" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  ;;
*)
  exit 1
  ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_omarchy/bin/omarchy-default-terminal" <<'SCRIPT'
#!/bin/bash
default_file="$HOME/.config/xdg-terminals.list"
if (($# == 0)); then
  desktop_id=$(grep -vE '^($|#)' "$default_file" 2>/dev/null | head -n 1)
  case $desktop_id in
  Alacritty.desktop) printf 'alacritty\n' ;;
  foot.desktop) printf 'foot\n' ;;
  com.mitchellh.ghostty.desktop) printf 'ghostty\n' ;;
  kitty.desktop) printf 'kitty\n' ;;
  *) printf '%s\n' "$desktop_id" ;;
  esac
  exit
fi
case $1 in
alacritty) desktop_id="Alacritty.desktop" ;;
foot) desktop_id="foot.desktop" ;;
ghostty) desktop_id="com.mitchellh.ghostty.desktop" ;;
kitty) desktop_id="kitty.desktop" ;;
*) exit 2 ;;
esac
cat >"$default_file" <<EOF
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
$desktop_id
EOF
SCRIPT
cp -- \
  "$test_omarchy/bin/omarchy-default-terminal" \
  "$test_omarchy/bin/qv-default-terminal"
install -m 0755 /dev/stdin "$test_omarchy/bin/qv-install-terminal" <<'SCRIPT'
#!/bin/bash
mode=install
if [[ ${1:-} == "--check" ]]; then
  mode=check
  shift
fi
slug=${1:-}
[[ $slug == "alacritty" || $slug == "foot" || $slug == "ghostty" || $slug == "kitty" ]] || exit 2
[[ $mode == "install" ]] || exit 0
touch "$QVOS_TEST_PACKAGE_DIR/$slug"
if [[ ! -e $HOME/.config/$slug ]]; then
  install -d "$HOME/.config/$slug"
  printf 'owner=%s\n' "$slug" >"$HOME/.config/$slug/config"
fi
case $slug in
alacritty) printf 'Alacritty desktop\n' >"$HOME/.local/share/applications/Alacritty.desktop" ;;
foot) printf 'Foot desktop\n' >"$HOME/.local/share/applications/foot.desktop" ;;
esac
"$QVOS_PATH/bin/qv-default-terminal" "$slug"
SCRIPT

export HOME="$test_home"
export QVOS_PATH="$test_omarchy"
export PATH="$test_bin:/usr/bin"
export QVOS_TEST_PACKAGE_DIR="$package_dir"

touch "$package_dir/alacritty" "$package_dir/foot" "$package_dir/ghostty"
"$test_omarchy/bin/omarchy-default-terminal" ghostty
[[ $("$test_home/.local/lib/qvos/menu/terminal-action" alacritty --state) == "installed" ]] ||
  fail "installed non-default terminal state"
[[ $("$test_home/.local/lib/qvos/menu/terminal-action" ghostty --state) == "active" ]] ||
  fail "active default terminal state"
[[ $("$test_home/.local/lib/qvos/menu/terminal-action" kitty --state) == "available" ]] ||
  fail "available terminal state"
printf 'ok - terminal owner distinguishes available, installed, and active states\n'

"$test_home/.local/lib/qvos/menu/terminal-action" alacritty --apply
[[ $("$test_omarchy/bin/omarchy-default-terminal") == "alacritty" ]] ||
  fail "Make Default did not apply the installed terminal"
export QVOS_ACTION_SLUG=alacritty
export QVOS_ACTION_OPERATION=task
export QVOS_TERMINAL_MODE=default
[[ $("$root/qvcore/tui/action/terminal-run") == "Status: Already default" ]] ||
  fail "active terminal did not expose direct information"
printf 'ok - installed terminal applies once and active state is direct information\n'

terminal_tui="$test_root/terminal-tui"
launch_log="$test_root/terminal-launch.log"
install -d "$terminal_tui/action"
install -m 0755 "$root/qvcore/tui/action/terminal-launch" "$terminal_tui/action/terminal-launch"
install -m 0755 "$root/qvcore/tui/owner-resolver" "$terminal_tui/owner-resolver"
install -m 0755 /dev/stdin "$terminal_tui/launch" <<'SCRIPT'
#!/bin/bash
{
  printf 'mode\t%s\n' "$QVOS_TERMINAL_MODE"
  printf 'operation\t%s\n' "$QVOS_ACTION_OPERATION"
  printf 'behavior\t%s\n' "$QVOS_ACTION_BEHAVIOR"
  printf 'sudo\t%s\n' "$QVOS_ACTION_REQUIRES_SUDO"
  printf 'primary\t%s\n' "${QVOS_ACTION_PRIMARY:-}"
  printf 'rollback\t%s\n' "${QVOS_ACTION_ROLLBACK:-}"
} >"$QVOS_TEST_TERMINAL_LAUNCH_LOG"
SCRIPT
install -m 0755 /dev/stdin "$terminal_tui/action/launch" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_TERMINAL_LAUNCH_LOG"
SCRIPT

QVOS_TEST_TERMINAL_LAUNCH_LOG="$launch_log" \
  "$terminal_tui/action/terminal-launch" alacritty
grep -Fqx $'mode\tdefault' "$launch_log" || fail "active terminal mode"
grep -Fqx $'behavior\tinformation' "$launch_log" || fail "active terminal information contract"
grep -Fqx $'primary\t' "$launch_log" || fail "active terminal retained transaction copy"
grep -Fqx $'rollback\t' "$launch_log" || fail "active terminal retained Stop rollback"

"$test_omarchy/bin/omarchy-default-terminal" ghostty
QVOS_TEST_TERMINAL_LAUNCH_LOG="$launch_log" \
  "$terminal_tui/action/terminal-launch" foot
grep -Fqx $'mode\tapply' "$launch_log" || fail "installed terminal Apply mode"
grep -Fqx $'behavior\tmutation' "$launch_log" || fail "installed terminal mutation contract"
grep -Fqx $'sudo\t0' "$launch_log" || fail "installed terminal requested sudo"
grep -Fqx $'primary\tMake Default' "$launch_log" || fail "installed terminal action copy"
grep -Fqx $'rollback\t' "$launch_log" || fail "Make Default retained Stop rollback"

QVOS_TEST_TERMINAL_LAUNCH_LOG="$launch_log" \
  "$terminal_tui/action/terminal-launch" kitty
[[ $(<"$launch_log") == "--installer kitty" ]] ||
  fail "available terminal did not open Install"
printf 'ok - every terminal state opens its one truthful TUI flow\n'

rm -f -- "$package_dir/foot"
rm -rf -- "$test_home/.config/foot"
rm -f -- "$test_home/.local/share/applications/foot.desktop"
"$test_omarchy/bin/omarchy-default-terminal" ghostty
export QVOS_ACTION_SLUG=foot
export QVOS_ACTION_OPERATION=install
export QVOS_ACTION_ROLLBACK=owner-state-v1
export QVOS_ACTION_ROLLBACK_STATE="$test_root/rollback"
"$root/qvcore/tui/action/run-installer" --check
"$test_home/.local/lib/qvos/menu/terminal-action" \
  foot --qvos-rollback-snapshot "$QVOS_ACTION_ROLLBACK_STATE"
touch "$package_dir/foot"
"$test_home/.local/lib/qvos/menu/terminal-action" \
  foot --qvos-rollback-restore "$QVOS_ACTION_ROLLBACK_STATE"
rm -rf -- "$QVOS_ACTION_ROLLBACK_STATE"
rm -f -- "$package_dir/foot"
printf 'ok - terminal Stop before settings change permits clean package rollback\n'

"$root/qvcore/tui/action/run-installer" >/dev/null
[[ $("$test_omarchy/bin/omarchy-default-terminal") == "foot" ]] ||
  fail "terminal Install did not make the terminal default"
"$root/qvcore/tui/action/run-installer" --rollback
[[ $("$test_omarchy/bin/omarchy-default-terminal") == "ghostty" ]] ||
  fail "terminal Install Stop did not restore the previous default"
[[ ! -e $test_home/.config/foot ]] ||
  fail "terminal Install Stop retained created config"
[[ ! -e $test_home/.local/share/applications/foot.desktop ]] ||
  fail "terminal Install Stop retained created desktop entry"
printf 'ok - terminal Install Stop restores exact settings and created files\n'

install -m 0755 /dev/stdin "$test_root/terminal-route" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_TERMINAL_ROUTE_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_root/generic-route" <<'SCRIPT'
#!/bin/bash
touch "$QVOS_TEST_GENERIC_ROUTE_LOG"
SCRIPT
export QVOS_TEST_TERMINAL_ROUTE_LOG="$test_root/terminal-route.log"
export QVOS_TEST_GENERIC_ROUTE_LOG="$test_root/generic-route.log"
QVOS_TERMINAL_ACTION_LAUNCH="$test_root/terminal-route" \
  QVOS_SOFTWARE_INSTALLER_LAUNCH="$test_root/generic-route" \
  bash -s -- "$root/qvcore/menu/routes" <<'SCRIPT'
set -euo pipefail
source "$1"
launch_software_installer alacritty
SCRIPT
[[ $(<"$QVOS_TEST_TERMINAL_ROUTE_LOG") == "alacritty" ]] ||
  fail "terminal menu did not delegate the selected slug"
[[ ! -e $QVOS_TEST_GENERIC_ROUTE_LOG ]] ||
  fail "terminal menu bypassed the state-aware launcher"
printf 'ok - terminal menu route uses the state-aware launcher\n'
