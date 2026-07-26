#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"

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
  bash -c 'source "$1"' _ "$root/install/config/qvos-scripts.sh" \
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
for feature in desktop screensaver thunar tmux waybar; do
  cp -a "$root/qv/$feature" "$partial_file_root/qv/$feature"
done
install -d "$partial_file_home/.local/share/qvos/desktop"
touch "$partial_file_home/.local/share/qvos/desktop/keep-existing"
unlink "$partial_file_root/qv/thunar/transcode"

if HOME="$partial_file_home" OMARCHY_PATH="$partial_file_root" \
  bash -c 'source "$1"' _ "$root/install/config/qvos-scripts.sh" \
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
  "$test_root/.local/share/qvos/branding" \
  "$test_root/.local/share/qvos/defaults" \
  "$test_root/.local/share/qvos/desktop/context" \
  "$test_root/.local/share/qvos/domains" \
  "$test_root/.local/share/qvos/hyprland" \
  "$test_root/.local/share/qvos/screensaver" \
  "$test_root/.local/share/qvos/source" \
  "$test_root/.local/share/qvos/thunar" \
  "$test_root/.local/share/qvos/tmux" \
  "$test_root/.local/share/qvos/tui" \
  "$test_root/.local/share/qvos/waybar"
touch \
  "$test_root/.local/share/qvos/branding/removed-helper" \
  "$test_root/.local/share/qvos/defaults/qvos-launch-thunar" \
  "$test_root/.local/share/qvos/desktop/context/removed-helper" \
  "$test_root/.local/share/qvos/hyprland/removed-helper" \
  "$test_root/.local/share/qvos/screensaver/removed-launcher" \
  "$test_root/.local/share/qvos/thunar/removed-feature" \
  "$test_root/.local/share/qvos/tmux/removed-feature" \
  "$test_root/.local/share/qvos/waybar/removed-feature"
touch "$test_root/.local/share/qvos/README.md" "$test_root/.local/share/qvos/VERSION"
touch "$test_root/.local/share/qvos/bin/omarchy-qvos-doctor" "$test_root/.local/share/qvos/bin/omarchy-qvos-reconcile" "$test_root/.local/share/qvos/bin/omarchy-qvos-update" "$test_root/.local/share/qvos/bin/qvos-show-logo"
touch "$test_root/.local/share/qvos/domains/retired-domain" "$test_root/.local/share/qvos/source/retired-runtime"
ln -s "$root/qv/apps/home" "$test_root/.local/share/qvos/home-dev"
touch "$test_root/.local/share/qvos/tui/retired-runtime-copy"
install -m 0755 /dev/null "$test_root/.local/share/qvos/waybar/prayer-data.sh"

HOME="$test_root" OMARCHY_PATH="$root" bash -c 'source "$1"' _ "$root/install/config/qvos-scripts.sh"

[[ ! -e $test_root/.local/share/qvos/hyprland/removed-helper ]] || fail "stale Hyprland helper cleanup"
[[ ! -e $test_root/.local/share/qvos/branding/removed-helper ]] || fail "stale branding helper cleanup"
[[ ! -e $test_root/.local/share/qvos/desktop/context/removed-helper ]] || fail "stale desktop helper cleanup"
[[ ! -e $test_root/.local/share/qvos/screensaver/removed-launcher ]] || fail "stale screensaver cleanup"
[[ ! -e $test_root/.local/share/qvos/thunar/removed-feature ]] || fail "stale Thunar feature cleanup"
[[ ! -e $test_root/.local/share/qvos/tmux/removed-feature ]] || fail "stale tmux feature cleanup"
[[ ! -e $test_root/.local/share/qvos/waybar/removed-feature ]] || fail "stale Waybar feature cleanup"
[[ ! -e $test_root/.local/share/qvos/defaults/qvos-launch-thunar ]] || fail "retired Thunar launcher cleanup"
pass "stale helper payloads are removed"

[[ ! -e $test_root/.local/share/qvos/home-dev && ! -L $test_root/.local/share/qvos/home-dev ]] ||
  fail "retired qvPLAY development link cleanup"
[[ ! -e $test_root/.local/share/qvos/source ]] || fail "retired standalone source cleanup"
[[ ! -e $test_root/.local/share/qvos/domains ]] || fail "retired standalone domain cleanup"
[[ ! -e $test_root/.local/share/qvos/tui ]] || fail "retired desktop TUI payload cleanup"
[[ ! -e $test_root/.local/share/qvos/README.md ]] || fail "retired helper readme cleanup"
[[ ! -e $test_root/.local/share/qvos/branding ]] || fail "retired branding helper cleanup"
[[ ! -e $test_root/.local/share/qvos/VERSION ]] || fail "retired standalone version cleanup"
for retired_command in omarchy-qvos-doctor omarchy-qvos-reconcile omarchy-qvos-update qvos-show-logo; do
  [[ ! -e $test_root/.local/share/qvos/bin/$retired_command ]] || fail "retired $retired_command cleanup"
done
pass "retired applications and ISO tooling stay out of the desktop payload"

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

waybar_source_inventory="$(find "$root/qv/waybar" -maxdepth 1 -type f -printf '%f\n' | sort)"
[[ $waybar_source_inventory == $'clock.sh\nprayer-data.sh\nprayerbar.sh' ]] ||
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

[[ "$(stat -c '%a' "$test_root/.local/share/qvos/waybar/prayer-data.sh")" == "644" ]] || fail "data script mode"
[[ -x $test_root/.local/share/qvos/waybar/prayerbar.sh ]] || fail "Waybar command mode"
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

migration="$root/migrations/1785020679.sh"
migration_log="$test_root/migration.log"
install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/omarchy-refresh-config" <<'SCRIPT'
#!/bin/bash
printf 'refresh %s\n' "$*" >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

QVOS_TEST_MIGRATION_LOG="$migration_log" \
  QVOS_SYSTEM_ROOT="$test_root/system-empty" \
  HOME="$test_root" \
  OMARCHY_PATH="$root" \
  PATH="$test_bin:$PATH" \
  bash "$migration"

grep -Fqx 'refresh hypr/qv/bindings.conf' "$migration_log" ||
  fail "organized binding migration refresh"
grep -Fqx 'hyprctl reload' "$migration_log" ||
  fail "organized binding migration reload"
pass "existing systems migrate to the organized desktop payload"
