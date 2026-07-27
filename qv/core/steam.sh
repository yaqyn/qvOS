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

mode="install"
remove_assume_yes=0
remove_check=0
state_file="$HOME/.local/state/qvos/qvcore/steam"

usage() {
  echo "Usage: steam.sh [--status|--state|--disable|--remove [--check|--yes]]" >&2
}

if (($# > 2)); then
  usage
  exit 2
fi

case ${1:-} in
"")
  (($# == 0)) || {
    usage
    exit 2
  }
  ;;
--status | --state | --disable)
  (($# == 1)) || {
    usage
    exit 2
  }
  mode=${1#--}
  ;;
--remove)
  mode="remove"
  case ${2:-} in
  "") ;;
  --check) remove_check=1 ;;
  --yes) remove_assume_yes=1 ;;
  *)
    usage
    exit 2
    ;;
  esac
  ;;
*)
  usage
  exit 2
  ;;
esac

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

remove_steam() {
  local command
  local setup_tracked=0

  [[ -f $state_file ]] && setup_tracked=1

  if ((steam_ready)); then
    for command in omarchy-pkg-drop pacman sudo; do
      if ! command -v "$command" >/dev/null 2>&1; then
        echo "qvCORE Steam removal requires: $command" >&2
        return 1
      fi
    done
    if ! pacman -Rs --print steam >/dev/null; then
      echo "Pacman could not prepare the Steam removal transaction." >&2
      return 1
    fi
  fi
  if ((remove_assume_yes == 0 && remove_check == 0)) &&
    ! command -v gum >/dev/null 2>&1; then
    echo "qvCORE Steam removal requires: gum" >&2
    return 1
  fi
  if ((remove_check)); then
    return 0
  fi
  if ((steam_ready == 0)); then
    if ((setup_tracked)); then
      rm -f "$state_file"
      echo "Steam is not installed; removed its stale qvCORE setup ownership."
    else
      echo "qvCORE Steam is not installed; nothing was changed."
    fi
    return 0
  fi

  echo "Remove the Steam package from qvCORE."
  echo "Game libraries, configuration, and shared gaming dependencies will be preserved."
  if ((remove_assume_yes == 0)); then
    gum confirm "Remove Steam while preserving its data and shared dependencies?" ||
      {
        echo "qvCORE Steam removal canceled; nothing was changed."
        return 130
      }
  fi

  omarchy-pkg-drop steam
  if omarchy-pkg-present steam; then
    echo "qvCORE Steam removal failed: steam remains installed." >&2
    return 1
  fi
  rm -f "$state_file"
  echo "Removed Steam; game data and shared gaming dependencies were preserved."
}

case $mode in
status)
  echo ""
  echo "qvCORE Gaming Dependencies inventory"
  if ((steam_ready)); then
    echo "  Steam:               installed"
  else
    echo "  Steam:               not installed"
  fi
  printf '  Gaming package set:  %d/%d present\n' \
    "$ready_dependency_count" "$total_dependencies"
  if [[ -f $state_file ]]; then
    echo "  qvCORE ownership:     enabled"
  else
    echo "  qvCORE ownership:     disabled"
  fi
  [[ -f $state_file ]]
  exit
  ;;
state)
  if [[ ! -f $state_file ]] && ((steam_ready)); then
    echo "available"
  elif [[ ! -f $state_file ]]; then
    echo "not-installed"
  elif ((steam_ready == 0)); then
    echo "removed"
  elif ((ready_dependency_count == total_dependencies)); then
    echo "ready"
  else
    echo "partial"
  fi
  exit
  ;;
disable)
  rm -f "$state_file"
  echo "qvCORE Gaming Dependencies ownership is disabled; Steam, dependencies, and game data were preserved."
  exit
  ;;
remove)
  remove_steam
  exit
  ;;
esac

omarchy-install-gaming-steam

echo ""
echo "Installing qvCORE gaming dependencies..."
omarchy-pkg-add "${gaming_packages[@]}"
install -D -m 0644 /dev/null "$state_file"
