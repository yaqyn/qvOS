#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

prepare_home() {
  local home=$1

  install -d -m 0755 "$home/.config/hypr" "$home/.local/share"
  ln -s "$root" "$home/.local/share/qvos"
}

test_home="$test_root/home"
prepare_home "$test_home"
install -m 0644 /dev/stdin "$test_home/.config/hypr/monitors.conf" <<'CONFIG'
# See https://wiki.hypr.land/Configuring/Basics/Monitors/
# List current monitors and resolutions possible: hyprctl monitors
# Format: monitor = [port], resolution, position, scale

# Optimized for retina-class 2x displays, like 13" 2.8K, 27" 5K, 32" 6K.
# env = GDK_SCALE,2
# monitor=,preferred,auto,auto

# Good compromise for 27" or 32" 4K monitors (but fractional!)
# env = GDK_SCALE,1.75
# monitor=,preferred,auto,1.6

# Straight 1x setup for low-resolution displays like 1080p or 1440p
# Or for ultrawide monitors like 34" 3440x1440 or 49" 5120x1440
env = GDK_SCALE,1
monitor=,preferred,auto,1

# Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°)
# monitor = DP-2, preferred, auto, 1, transform, 1

# Example for Framework 13 w/ 6K XDR Apple display
# monitor = DP-5, 6016x3384@60, auto, 2
# monitor = eDP-1, 2880x1920@120, auto, 2

# Disable the second ghost monitor on an Apple 6K XDR over Thunderbolt
# monitor=DP-2,disable
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/hypr/envs.conf" <<'CONFIG'

# NVIDIA (Maxwell/Pascal/Volta without GSP firmware)
env = NVD_BACKEND,egl
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
CONFIG
install -d -m 0700 "$test_home/.local/state/qvos/toggles/hypr"
install -m 0600 /dev/stdin \
  "$test_home/.local/state/qvos/toggles/hypr/flags.conf" <<'CONFIG'
# This directory is intended for permanent config toggle flags.
# Do not remove this file (as the directory always needs at least one file).
CONFIG
install -d -m 0755 "$test_home/.config/qvos/current/theme"
printf 'Yaqyn\n' >"$test_home/.config/qvos/current/theme.name"
install -m 0644 /dev/stdin \
  "$test_home/.config/qvos/current/theme/hyprland.conf" <<'CONFIG'
# Preserved legacy theme fragment.
source = ~/.config/qvos/current/theme/hyprland/*.conf
CONFIG

[[ $(sha256sum "$test_home/.config/hypr/monitors.conf" | cut -d' ' -f1) == \
  "f13168312547b788db1245f42dd7e1ecd19fabfd0e2fddf3782ec58eb848731a" ]] ||
  fail "fixed 1x fixture drifted"

HOME="$test_home" QVOS_PATH="$root" \
  "$root/qvcore/config/migrate-hyprland-lua" >/dev/null

for name in autostart bindings envs hyprland input looknfeel monitors; do
  [[ -f $test_home/.config/hypr/$name.lua &&
    ! -e $test_home/.config/hypr/$name.conf ]] ||
    fail "config format did not converge: $name"
done
cmp -s "$root/qvcore/config/migration/hyprland/monitors-one-x.lua" \
  "$test_home/.config/hypr/monitors.lua" || fail "fixed monitor policy was lost"
cmp -s "$root/qvcore/config/migration/hyprland/envs-nvidia-maxwell.lua" \
  "$test_home/.config/hypr/envs.lua" || fail "NVIDIA environment was lost"
cmp -s "$root/qvcore/config/toggles/flags.lua" \
  "$test_home/.local/state/qvos/toggles/hypr/flags.lua" ||
  fail "toggle state did not converge"
[[ ! -e $test_home/.local/state/qvos/toggles/hypr/flags.conf ]] ||
  fail "legacy toggle remained active"
for backup in \
  config/monitors.conf \
  config/envs.conf \
  theme/hyprland.conf \
  toggles/flags.conf; do
  [[ -f $test_home/.local/state/qvos/hyprland/legacy-conf/$backup &&
    $(stat -c '%a' "$test_home/.local/state/qvos/hyprland/legacy-conf/$backup") == "600" ]] ||
    fail "private legacy backup is missing: $backup"
done
[[ -f $test_home/.config/qvos/current/theme/hyprland.lua &&
  ! -e $test_home/.config/qvos/current/theme/hyprland.conf ]] ||
  fail "active theme did not converge on native Lua"

# The completed migration is idempotent and preserves the same result.
before=$(find "$test_home/.config/hypr" "$test_home/.local/state/qvos/hyprland" \
  -type f -exec sha256sum {} + | sort)
HOME="$test_home" QVOS_PATH="$root" \
  "$root/qvcore/config/migrate-hyprland-lua" >/dev/null
after=$(find "$test_home/.config/hypr" "$test_home/.local/state/qvos/hyprland" \
  -type f -exec sha256sum {} + | sort)
[[ $after == "$before" ]] || fail "rerun changed the migrated config or backup"

# Unknown legacy code stops before qvOS creates migration state or Lua output.
custom_home="$test_root/custom-home"
prepare_home "$custom_home"
printf 'input { sensitivity = 0.75 }\n' |
  install -m 0644 /dev/stdin "$custom_home/.config/hypr/input.conf"
if HOME="$custom_home" QVOS_PATH="$root" \
  "$root/qvcore/config/migrate-hyprland-lua" >/dev/null 2>&1; then
  fail "custom legacy config was silently replaced"
fi
[[ -f $custom_home/.config/hypr/input.conf ]] ||
  fail "custom legacy config was not preserved"
[[ ! -e $custom_home/.config/hypr/input.lua &&
  ! -e $custom_home/.local/state/qvos ]] ||
  fail "custom-config rejection mutated migration state"

# A parser failure leaves the reviewed legacy entrypoint and its theme fragment
# active, while preserving a private exact backup for a safe retry.
rejected_home="$test_root/rejected-home"
rejected_bin="$test_root/rejected-bin"
prepare_home "$rejected_home"
install -d \
  "$rejected_bin" \
  "$rejected_home/.config/qvos/current/theme"
install -m 0644 /dev/stdin "$rejected_home/.config/hypr/hyprland.conf" <<'CONFIG'
# Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/

# Use the native qvOS base (do not edit these source-owned files directly).
source = ~/.local/share/qvos/qvcore/config/base/hypr/autostart.conf
source = ~/.local/share/qvos/qvcore/config/base/hypr/envs.conf
source = ~/.local/share/qvos/qvcore/config/base/hypr/looknfeel.conf
source = ~/.local/share/qvos/qvcore/config/base/hypr/windows.conf
source = ~/.config/qvos/current/theme/hyprland.conf

# Change your own setup in these files (and overwrite any settings from defaults!)
source = ~/.config/hypr/monitors.conf
source = ~/.config/hypr/input.conf
source = ~/.config/hypr/bindings.conf
source = ~/.config/hypr/looknfeel.conf
source = ~/.config/hypr/autostart.conf

# Toggle qvOS config flags dynamically
source = ~/.local/state/qvos/toggles/hypr/*.conf

# Add any other personal Hyprland configuration below
# windowrule = workspace 5, match:class qemu
CONFIG
printf 'Yaqyn\n' >"$rejected_home/.config/qvos/current/theme.name"
install -m 0644 /dev/stdin \
  "$rejected_home/.config/qvos/current/theme/hyprland.conf" <<'CONFIG'
# Legacy theme remains active on verification failure.
CONFIG
install -m 0755 /dev/stdin "$rejected_bin/Hyprland" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
if HOME="$rejected_home" QVOS_PATH="$root" PATH="$rejected_bin:/usr/bin" \
  "$root/qvcore/config/migrate-hyprland-lua" >/dev/null 2>&1; then
  fail "rejected Lua configuration was published"
fi
[[ -f $rejected_home/.config/hypr/hyprland.conf &&
  ! -e $rejected_home/.config/hypr/hyprland.lua ]] ||
  fail "parser failure replaced the legacy entrypoint"
[[ -f $rejected_home/.config/qvos/current/theme/hyprland.conf ]] ||
  fail "parser failure retired the active legacy theme fragment"
cmp -s \
  "$rejected_home/.config/qvos/current/theme/hyprland.conf" \
  "$rejected_home/.local/state/qvos/hyprland/legacy-conf/theme/hyprland.conf" ||
  fail "parser failure did not preserve the legacy theme backup"

printf 'ok - Hyprland Lua migration preserves reviewed state and fails closed\n'
