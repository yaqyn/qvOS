#!/bin/bash
set -euo pipefail

# Source: https://github.com/ChrisTitusTech/linutil/blob/main/core/tabs/system-setup/gaming-setup.sh
# Reviewed at Linutil commit 842c02770666 (2026-07-21).
# Legacy aliases use current Arch package names; the unavailable
# lib32-gst-plugins-base-libs entry is omitted.
# Hardware-specific Vulkan drivers stay with Omarchy's GPU detection.
gaming_packages=(
  dbus
  git
  gnutls
  lib32-gnutls
  base-devel
  gtk3
  lib32-gtk3
  python-google-auth
  python-protobuf
  libpulse
  lib32-libpulse
  alsa-lib
  lib32-alsa-lib
  alsa-utils
  alsa-plugins
  lib32-alsa-plugins
  giflib
  lib32-giflib
  libpng
  lib32-libpng
  libldap
  lib32-libldap
  openal
  lib32-openal
  libxcomposite
  lib32-libxcomposite
  libxinerama
  lib32-libxinerama
  libgcrypt
  lib32-libgcrypt
  libgpg-error
  lib32-libgpg-error
  ncurses
  lib32-ncurses
  mpg123
  lib32-mpg123
  libjpeg-turbo
  lib32-libjpeg-turbo
  sqlite
  lib32-sqlite
  libva
  lib32-libva
  gst-plugins-base-libs
  sdl2-compat
  lib32-sdl2-compat
  v4l-utils
  lib32-v4l-utils
  vulkan-icd-loader
  lib32-vulkan-icd-loader
  ocl-icd
  lib32-ocl-icd
  libxslt
  lib32-libxslt
  cups
  samba
  lib32-mesa
  gamescope
  mangohud
  lib32-mangohud
  gamemode
  lib32-gamemode
  wine
  goverlay
)

if omarchy-pkg-present pipewire-jack; then
  gaming_packages+=(lib32-pipewire-jack)
elif omarchy-pkg-present jack2; then
  gaming_packages+=(lib32-jack2)
fi

steam_ready=0
ready_dependency_count=0
omarchy-pkg-present steam && steam_ready=1
for package in "${gaming_packages[@]}"; do
  omarchy-pkg-present "$package" &&
    ready_dependency_count=$((ready_dependency_count + 1))
done
total_dependencies=${#gaming_packages[@]}

case ${1:-} in
"") ;;
--status)
  echo ""
  echo "qvCORE Steam inventory"
  if ((steam_ready)); then
    echo "  Steam:               installed"
  else
    echo "  Steam:               not installed"
  fi
  printf '  Gaming package set:  %d/%d present\n' \
    "$ready_dependency_count" "$total_dependencies"
  ((steam_ready))
  exit
  ;;
--state)
  if ((steam_ready == 0)); then
    echo "not-installed"
  elif ((ready_dependency_count == total_dependencies)); then
    echo "ready"
  else
    echo "partial"
  fi
  exit
  ;;
*)
  echo "Usage: steam.sh [--status]" >&2
  exit 2
  ;;
esac

omarchy-install-gaming-steam

echo ""
echo "Installing qvCORE gaming dependencies..."
omarchy-pkg-add "${gaming_packages[@]}"
