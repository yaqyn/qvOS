#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
export GOCACHE=${GOCACHE:-$(go env GOCACHE)}
export GOMODCACHE=${GOMODCACHE:-$(go env GOMODCACHE)}

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

partial_root="$test_root/partial-source"
partial_home="$test_root/partial-home"
install -d \
  "$partial_root/qv/desktop" \
  "$partial_root/qv/screensaver" \
  "$partial_root/qv/thunar" \
  "$partial_root/qv/waybar" \
  "$partial_home/.local/share/qvos/desktop"
touch "$partial_home/.local/share/qvos/desktop/keep-existing"

if HOME="$partial_home" OMARCHY_PATH="$partial_root" \
  bash -c 'source "$1"' _ "$root/qv/install/desktop" \
  >"$test_root/preflight.log" 2>&1; then
  fail "incomplete source preflight"
fi
grep -Fq 'Missing qvOS desktop feature source:' "$test_root/preflight.log" ||
  fail "incomplete source error"
[[ -e $partial_home/.local/share/qvos/desktop/keep-existing ]] ||
  fail "incomplete source preserved payload"
pass "incomplete source cannot erase the installed desktop payload"

partial_file_root="$test_root/partial-file-source"
partial_file_home="$test_root/partial-file-home"
install -d "$partial_file_root/qv"
for feature in codex desktop maintenance power screensaver shell thunar tmux tui waybar; do
  cp -a "$root/qv/$feature" "$partial_file_root/qv/$feature"
done
install -d "$partial_file_home/.local/share/qvos/desktop"
touch "$partial_file_home/.local/share/qvos/desktop/keep-existing"
unlink "$partial_file_root/qv/thunar/transcode"

if HOME="$partial_file_home" OMARCHY_PATH="$partial_file_root" \
  bash -c 'source "$1"' _ "$root/qv/install/desktop" \
  >"$test_root/preflight-file.log" 2>&1; then
  fail "incomplete source-file preflight"
fi
grep -Fq 'Missing qvOS desktop feature file:' \
  "$test_root/preflight-file.log" ||
  fail "incomplete source-file error"
[[ -e $partial_file_home/.local/share/qvos/desktop/keep-existing ]] ||
  fail "incomplete source-file preserved payload"
pass "missing feature files cannot erase the installed desktop payload"

install -d \
  "$test_root/.local/share/qvos/bin" \
  "$test_root/.local/share/qvos/desktop/context" \
  "$test_root/.local/share/qvos/screensaver" \
  "$test_root/.local/share/qvos/thunar" \
  "$test_root/.local/share/qvos/tmux" \
  "$test_root/.local/share/qvos/waybar"
touch \
  "$test_root/.local/share/qvos/desktop/context/removed-helper" \
  "$test_root/.local/share/qvos/screensaver/removed-launcher" \
  "$test_root/.local/share/qvos/thunar/removed-feature" \
  "$test_root/.local/share/qvos/tmux/removed-feature" \
  "$test_root/.local/share/qvos/waybar/removed-feature"
install -m 0755 /dev/null "$test_root/.local/share/qvos/waybar/prayer-data.sh"
# shellcheck disable=SC2016
printf '%s\n' \
  'source "$HOME/.local/share/omarchy/qv/shell/aliases"' \
  >"$test_root/.bashrc"

HOME="$test_root" OMARCHY_PATH="$root" \
  bash -c 'source "$1"' _ "$root/qv/install/desktop"

cmp -s \
  "$root/qv/menu/extension.sh" \
  "$test_root/.config/omarchy/extensions/qvos-menu.sh" ||
  fail "qvOS menu extension install"
# shellcheck disable=SC2016
grep -Fqx \
  '[[ -f $HOME/.config/omarchy/extensions/qvos-menu.sh ]] && source "$HOME/.config/omarchy/extensions/qvos-menu.sh"' \
  "$test_root/.config/omarchy/extensions/menu.sh" ||
  fail "Omarchy user menu extension seam"
pass "qvOS menu installs through the Omarchy user extension seam"

for provider in \
  omarchy_background_selector.lua \
  omarchy_themes.lua \
  omarchy_unlocks.lua; do
  runtime_provider="$test_root/.local/share/qvos/launcher/elephant/$provider"
  cmp -s "$root/qv/launcher/elephant/$provider" "$runtime_provider" ||
    fail "$provider launcher runtime"
  [[ $(readlink "$test_root/.config/elephant/menus/$provider") == "$runtime_provider" ]] ||
    fail "$provider launcher runtime link"
done
pass "launcher providers install into qvOS-owned runtime"

cmp -s \
  "$root/qv/core/post-update-hook" \
  "$test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore" ||
  fail "qvCORE post-update hook install"
cmp -s \
  "$root/qv/waybar/post-update-hook" \
  "$test_root/.config/omarchy/hooks/post-update.d/qvos-waybar-overrides" ||
  fail "qvOS Waybar post-update hook install"
pass "qvOS post-update hooks install from their feature owners"

cmp -s \
  "$root/qv/codex/capabilities.tsv" \
  "$test_root/.local/share/qvos/codex/capabilities.tsv" ||
  fail "Codex capability runtime"
cmp -s \
  "$root/qv/codex/doctor" \
  "$test_root/.local/share/qvos/codex/doctor" ||
  fail "Codex doctor runtime"
[[ ! -x $test_root/.local/share/qvos/codex/capabilities.tsv ]] ||
  fail "Codex capability data mode"
[[ -x $test_root/.local/share/qvos/codex/doctor ]] ||
  fail "Codex doctor mode"
pass "Codex capability contract and doctor install together"

[[ ! -e $test_root/.local/share/qvos/desktop/context/removed-helper ]] || fail "stale desktop helper cleanup"
[[ ! -e $test_root/.local/share/qvos/screensaver/removed-launcher ]] || fail "stale screensaver cleanup"
[[ ! -e $test_root/.local/share/qvos/thunar/removed-feature ]] || fail "stale Thunar feature cleanup"
[[ ! -e $test_root/.local/share/qvos/tmux/removed-feature ]] || fail "stale tmux feature cleanup"
[[ ! -e $test_root/.local/share/qvos/waybar/removed-feature ]] || fail "stale Waybar feature cleanup"
pass "stale helper payloads are removed"

[[ ! -e $root/qv/scripts ]] || fail "orphaned generic script namespace"
pass "every private helper has a feature owner"

for feature in desktop tmux waybar; do
  expected_feature="$(find "$root/qv/$feature" -type f -printf '%P\n' | sort)"
  installed_feature="$(find "$test_root/.local/share/qvos/$feature" -type f -printf '%P\n' | sort)"
  [[ $installed_feature == "$expected_feature" ]] || fail "$feature feature inventory"
done
installed_thunar_inventory="$(
  find "$test_root/.local/share/qvos/thunar" -type f -printf '%P\n' | sort
)"
[[ $installed_thunar_inventory == $'actions.sh\nlaunch\nopen-here\nreconcile-default-actions\nset-background\ntranscode' ]] ||
  fail "default Thunar feature inventory"
for optional_thunar_feature in codex proton-drive-upload share; do
  [[ ! -e $test_root/.local/share/qvos/thunar/$optional_thunar_feature ]] ||
    fail "optional Thunar $optional_thunar_feature base payload"
done
pass "installed feature payloads match tracked source"

qvcore_state="$test_root/.local/state/qvos/qvcore"
install -d "$qvcore_state"
for component in codex proton share; do
  install -m 0644 /dev/null "$qvcore_state/$component"
done
HOME="$test_root" OMARCHY_PATH="$root" \
  bash -c 'source "$1"' _ "$root/qv/install/desktop"
for optional_thunar_feature in codex proton-drive-upload share; do
  cmp -s \
    "$root/qv/thunar/$optional_thunar_feature" \
    "$test_root/.local/share/qvos/thunar/$optional_thunar_feature" ||
    fail "enabled Thunar $optional_thunar_feature preservation"
done
pass "desktop refresh preserves current helpers for enabled optional setups"

waybar_source_inventory="$(find "$root/qv/waybar" -maxdepth 1 -type f -printf '%f\n' | sort)"
[[ $waybar_source_inventory == $'clock.sh\noverrides.jsonc\npost-update-hook\nprayer-data.sh\nprayerbar.sh\nrefresh' ]] ||
  fail "focused Waybar feature inventory"
pass "retired Waybar helpers stay removed"

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

for command_name in omarchy-system-inhibit-sleep omarchy-system-suspend-if-safe; do
  [[ -x $test_root/.local/share/qvos/bin/$command_name ]] ||
    fail "$command_name runtime installation"
done
pass "power guards are installed with the desktop runtime"

tui_binary="$test_root/.local/share/qvos/tui/qvos-tui"
[[ -x $tui_binary && ! -L $tui_binary ]] ||
  fail "qvOS TUI managed binary"
[[ $(readlink "$test_root/.local/bin/qvos-tui") == "$tui_binary" ]] ||
  fail "qvOS TUI command link"
HOME="$test_root" OMARCHY_PATH="$root" \
  "$root/qv/tui/install" --status ||
  fail "qvOS TUI source parity"
pass "qvOS TUI builds once and installs from its domain owner"

cmp -s \
  "$root/qv/maintenance/essential-packages" \
  "$test_root/.local/share/qvos/maintenance/essential-packages" ||
  fail "recovery essential-package policy installation"
cmp -s \
  "$root/qv/maintenance/qvos-repair" \
  "$test_root/.local/share/qvos/maintenance/qvos-repair" ||
  fail "recovery engine installation"
cmp -s \
  "$root/qv/maintenance/qvos-system" \
  "$test_root/.local/share/qvos/maintenance/qvos-system" ||
  fail "qvOS system hub installation"
cmp -s \
  "$root/qv/maintenance/qv" \
  "$test_root/.local/bin/qv" ||
  fail "qv recovery front door installation"
[[ -x $test_root/.local/share/qvos/maintenance/qvos-repair ]] ||
  fail "recovery engine mode"
[[ -x $test_root/.local/share/qvos/maintenance/qvos-system ]] ||
  fail "qvOS system hub mode"
[[ ! -x $test_root/.local/share/qvos/maintenance/essential-packages ]] ||
  fail "recovery package policy mode"
[[ -x $test_root/.local/bin/qv && ! -L $test_root/.local/bin/qv ]] ||
  fail "qv recovery front door is not a real executable"
pass "recovery engine, system hub, policy, and qv front door install independently"

cmp -s \
  "$root/qv/shell/aliases" \
  "$test_root/.local/share/qvos/shell/aliases" ||
  fail "runtime shell overlay"
# shellcheck disable=SC2016
grep -Fqx \
  'source "$HOME/.local/share/qvos/shell/aliases"' \
  "$test_root/.bashrc" ||
  fail "runtime shell source line"
# shellcheck disable=SC2016
if grep -Fqx \
  'source "$HOME/.local/share/omarchy/qv/shell/aliases"' \
  "$test_root/.bashrc"; then
  fail "source-tree shell source line"
fi
compgen -G "$test_root/.bashrc.bak.*" >/dev/null ||
  fail "legacy Bash source line backup"
pass "Bash loads the source-independent qvOS shell overlay"

[[ "$(stat -c '%a' "$test_root/.local/share/qvos/waybar/prayer-data.sh")" == "644" ]] || fail "data script mode"
[[ -x $test_root/.local/share/qvos/waybar/prayerbar.sh ]] || fail "Waybar command mode"
[[ -x $test_root/.local/share/qvos/waybar/refresh ]] ||
  fail "Waybar refresh mode"
[[ ! -x $test_root/.local/share/qvos/waybar/overrides.jsonc ]] ||
  fail "Waybar override data mode"
[[ ! -x $test_root/.local/share/qvos/waybar/post-update-hook ]] ||
  fail "Waybar hook source mode"
[[ -x $test_root/.local/share/qvos/tmux/qvos-tmux ]] || fail "tmux command mode"
while IFS= read -r helper; do
  [[ -x $helper ]] || fail "desktop helper mode"
done < <(find "$test_root/.local/share/qvos/desktop" -type f)
[[ ! -x $test_root/.local/share/qvos/thunar/actions.sh ]] ||
  fail "Thunar action library mode"
for feature in \
  launch \
  open-here \
  reconcile-default-actions \
  set-background \
  transcode; do
  [[ -x $test_root/.local/share/qvos/thunar/$feature ]] ||
    fail "Thunar $feature mode"
done
pass "tracked script and data modes are preserved"

health_output=$(
  HOME="$test_root" \
    OMARCHY_PATH="$root" \
    "$root/qv/install/desktop-status"
)
[[ -z $health_output ]] || fail "healthy desktop status output"

printf '\n# test drift\n' \
  >>"$test_root/.local/share/qvos/tmux/qvos-tmux"
drift_before=$(sha256sum "$test_root/.local/share/qvos/tmux/qvos-tmux")
set +e
drift_output=$(
  HOME="$test_root" \
    OMARCHY_PATH="$root" \
    "$root/qv/install/desktop-status" 2>&1
)
drift_status=$?
set -e
((drift_status == 1)) || fail "desktop drift health status"
grep -Fq 'tmux runtime differs from tracked qvOS source' <<<"$drift_output" ||
  fail "desktop drift health detail"
[[ $(sha256sum "$test_root/.local/share/qvos/tmux/qvos-tmux") == "$drift_before" ]] ||
  fail "desktop health mutates drifted runtime"
pass "qvOS desktop health detects runtime drift without changing it"
