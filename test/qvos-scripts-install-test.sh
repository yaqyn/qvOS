#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"

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

install -d "$test_root/.local/share/qvos/hyprland" "$test_root/.local/share/qvos/screensaver" "$test_root/.local/share/qvos/tui" "$test_root/.local/share/qvos/waybar"
touch "$test_root/.local/share/qvos/hyprland/removed-helper" "$test_root/.local/share/qvos/screensaver/removed-launcher"
ln -s "$root/qv/apps/home" "$test_root/.local/share/qvos/home-dev"
touch "$test_root/.local/share/qvos/tui/retired-runtime-copy"
install -m 0755 /dev/null "$test_root/.local/share/qvos/waybar/prayer-data.sh"

HOME="$test_root" OMARCHY_PATH="$root" bash -c 'source "$1"' _ "$root/install/config/qvos-scripts.sh"

[[ ! -e $test_root/.local/share/qvos/hyprland/removed-helper ]] || fail "stale Hyprland helper cleanup"
[[ ! -e $test_root/.local/share/qvos/screensaver/removed-launcher ]] || fail "stale screensaver cleanup"
pass "stale helper payloads are removed"

[[ ! -e $test_root/.local/share/qvos/home-dev ]] || fail "retired qvPLAY development link cleanup"
[[ ! -e $test_root/.local/share/qvos/tui ]] || fail "retired desktop TUI payload cleanup"
pass "optional development and ISO tooling stay out of the desktop payload"

expected_hyprland="$(find "$root/qv/scripts/hyprland" -maxdepth 1 -type f -printf '%f\n' | sort)"
installed_hyprland="$(find "$test_root/.local/share/qvos/hyprland" -maxdepth 1 -type f -printf '%f\n' | sort)"
[[ $installed_hyprland == "$expected_hyprland" ]] || fail "Hyprland helper inventory"
pass "installed Hyprland helpers match tracked source"

screensaver_files="$(find "$test_root/.local/share/qvos/screensaver" -maxdepth 1 -type f -printf '%f\n')"
[[ $screensaver_files == "alacritty.toml" ]] || fail "screensaver config inventory"
[[ "$(stat -c '%a' "$test_root/.local/share/qvos/screensaver/alacritty.toml")" == "644" ]] || fail "screensaver config mode"
pass "screensaver configuration is singular and non-executable"

for command_name in omarchy-launch-screensaver qvos-launch-screensaver qvos-screensaver; do
  installed_command="$test_root/.local/share/qvos/bin/$command_name"
  [[ -x $installed_command ]] || fail "$command_name installation"
  [[ "$(readlink "$test_root/.local/bin/$command_name")" == "$installed_command" ]] || fail "$command_name link"
done
pass "screensaver commands and user links are installed"

[[ "$(stat -c '%a' "$test_root/.local/share/qvos/waybar/prayer-data.sh")" == "644" ]] || fail "data script mode"
[[ -x $test_root/.local/share/qvos/waybar/prayerbar.sh ]] || fail "Waybar command mode"
pass "tracked script and data modes are preserved"
