#!/bin/bash
set -euo pipefail

omarchy-install-gaming-steam

# Source: https://github.com/ChrisTitusTech/linutil/blob/main/core/tabs/system-setup/gaming-setup.sh
# Reviewed at Linutil commit 33cb81e245ca (2026-07-17).
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

echo ""
echo "Installing qvCORE gaming dependencies..."
omarchy-pkg-add "${gaming_packages[@]}"
