#!/bin/bash
set -euo pipefail

state_file="$HOME/.local/state/qvos/qvcore/media"
packages=(
  gimp
  inkscape
  krita
  kdenlive
  obs-studio
  audacity
  blender
)
assume_yes=0

usage() {
  echo "Usage: media.sh <install|remove> [--yes]" >&2
}

media_ready() {
  local package

  for package in "${packages[@]}"; do
    omarchy-pkg-present "$package" || return 1
  done
}

install_stack() {
  local missing=()
  local package

  for package in "${packages[@]}"; do
    omarchy-pkg-present "$package" || missing+=("$package")
  done
  if ((${#missing[@]} > 0)); then
    omarchy-pkg-add "${missing[@]}"
  fi
  media_ready || {
    echo "Media verification failed after installation." >&2
    return 1
  }

  install -D -m 0644 /dev/null "$state_file"
  echo "qvCORE Media is installed."
}

remove_stack() {
  local installed=()
  local package

  if [[ ! -f $state_file ]]; then
    echo "qvCORE Media is not enrolled; nothing was changed."
    return
  fi

  for package in "${packages[@]}"; do
    omarchy-pkg-present "$package" && installed+=("$package")
  done
  if ((${#installed[@]} > 0)); then
    for command in pacman omarchy-pkg-drop gum; do
      command -v "$command" >/dev/null 2>&1 || {
        echo "qvCORE Media removal requires: $command" >&2
        return 1
      }
    done
    pacman -Rs --print "${installed[@]}" >/dev/null || {
      echo "Pacman could not prepare the Media removal transaction." >&2
      return 1
    }
  fi

  echo "The seven qvCORE Media applications will be removed."
  echo "Their settings, projects and personal files will be preserved."
  if ((assume_yes == 0)); then
    gum confirm "Remove the enrolled qvCORE Media stack?" || {
      echo "Media removal canceled; nothing was changed."
      return 130
    }
  fi

  if ((${#installed[@]} > 0)); then
    omarchy-pkg-drop "${installed[@]}"
  fi
  media_ready && {
    echo "Media removal failed: one or more applications remain installed." >&2
    return 1
  }
  for package in "${packages[@]}"; do
    omarchy-pkg-missing "$package" || {
      echo "Media removal failed: $package remains installed." >&2
      return 1
    }
  done
  rm -f "$state_file"
  echo "Removed qvCORE Media; settings, projects and personal files were preserved."
}

if (($# < 1 || $# > 2)); then
  usage
  exit 2
fi
if (($# == 2)); then
  [[ $2 == "--yes" && $1 == "remove" ]] || {
    usage
    exit 2
  }
  assume_yes=1
fi

case $1 in
install) install_stack ;;
remove) remove_stack ;;
*)
  usage
  exit 2
  ;;
esac
