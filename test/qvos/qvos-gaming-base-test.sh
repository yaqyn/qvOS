#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="$root/qv/install/packaging/base.packages"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

expected_packages=$'dbus\ngit\ngnutls\nlib32-gnutls\nbase-devel\ngtk3\nlib32-gtk3\npython-google-auth\npython-protobuf'
expected_packages+=$'\nlibpulse\nlib32-libpulse\nalsa-lib\nlib32-alsa-lib\nalsa-utils\nalsa-plugins\nlib32-alsa-plugins'
expected_packages+=$'\ngiflib\nlib32-giflib\nlibpng\nlib32-libpng\nlibldap\nlib32-libldap\nopenal\nlib32-openal'
expected_packages+=$'\nlibxcomposite\nlib32-libxcomposite\nlibxinerama\nlib32-libxinerama\nlibgcrypt\nlib32-libgcrypt'
expected_packages+=$'\nlibgpg-error\nlib32-libgpg-error\nncurses\nlib32-ncurses\nmpg123\nlib32-mpg123'
expected_packages+=$'\nlibjpeg-turbo\nlib32-libjpeg-turbo\nsqlite\nlib32-sqlite\nlibva\nlib32-libva'
expected_packages+=$'\ngst-plugins-base-libs\nsdl2-compat\nlib32-sdl2-compat\nv4l-utils\nlib32-v4l-utils'
expected_packages+=$'\nvulkan-icd-loader\nlib32-vulkan-icd-loader\nocl-icd\nlib32-ocl-icd\nlibxslt\nlib32-libxslt'
expected_packages+=$'\ncups\nsamba\nlib32-mesa\ngamescope\nmangohud\nlib32-mangohud\ngamemode\nlib32-gamemode'
expected_packages+=$'\nwine\ngoverlay\nlib32-pipewire-jack'

actual_packages=$(
  sed -n \
    '/^# qvos:gaming-base:start$/,/^# qvos:gaming-base:end$/p' \
    "$manifest" |
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d'
)

[[ $actual_packages == "$expected_packages" ]] ||
  fail "reviewed gaming base package snapshot"
pass "qvOS base owns the complete reviewed gaming runtime"

duplicate_packages=$(
  sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$manifest" |
    sort |
    uniq -d
)
[[ -z $duplicate_packages ]] ||
  fail "base package manifest contains duplicates: $duplicate_packages"
pass "gaming promotion keeps every base package singular"

cross_manifest_duplicates=$(
  comm -12 \
    <(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$manifest" | sort -u) \
    <(
      sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' \
        "$root/qv/install/packaging/other.packages" |
        sort -u
    )
)
[[ -z $cross_manifest_duplicates ]] ||
  fail "base packages remain duplicated in the offline-only manifest: $cross_manifest_duplicates"
pass "promoted gaming packages have one packaging owner"

grep -Fq 'Reviewed at Linutil commit ' "$manifest" ||
  fail "gaming package review provenance"
if grep -Eq '^(steam|lib32-jack2|lib32-gst-plugins-base-libs|lib32-vulkan-(intel|radeon)|lib32-nvidia)' \
  <<<"$actual_packages"; then
  fail "gaming base crosses the Steam or hardware-specific ownership boundary"
fi
pass "Steam and hardware-specific GPU drivers remain with Omarchy"
