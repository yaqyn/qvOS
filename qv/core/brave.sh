#!/bin/bash
set -euo pipefail

state_file="$HOME/.local/state/qvos/qvcore/brave"
assume_yes=0

usage() {
  echo "Usage: brave.sh <install|remove> [--yes]" >&2
}

package_ready() {
  omarchy-pkg-present brave-origin-beta-bin &&
    omarchy-cmd-present brave-origin-beta
}

install_stack() {
  if ! package_ready; then
    omarchy-install-browser brave-origin
  fi
  package_ready || {
    echo "Brave verification failed after installation." >&2
    return 1
  }

  omarchy-default-browser brave-origin
  install -D -m 0644 /dev/null "$state_file"
  echo "qvCORE Brave is installed."
}

remove_stack() {
  if [[ ! -f $state_file ]]; then
    echo "qvCORE Brave is not enrolled; nothing was changed."
    return
  fi

  for command in omarchy-remove-browser pacman gum; do
    if ! command -v "$command" >/dev/null 2>&1; then
      echo "qvCORE Brave removal requires: $command" >&2
      return 1
    fi
  done
  if omarchy-pkg-present brave-origin-beta-bin &&
    ! pacman -Rs --print brave-origin-beta-bin >/dev/null; then
    echo "Pacman could not prepare the Brave removal transaction." >&2
    return 1
  fi

  echo "Brave software and qvOS browser integration will be removed."
  echo "The Brave profile and personal files will be preserved."
  if ((assume_yes == 0)); then
    gum confirm "Remove the enrolled qvCORE Brave stack?" || {
      echo "Brave removal canceled; nothing was changed."
      return 130
    }
  fi

  if omarchy-pkg-present brave-origin-beta-bin; then
    omarchy-remove-browser brave-origin
  fi
  omarchy-pkg-missing brave-origin-beta-bin || {
    echo "Brave removal failed: brave-origin-beta-bin remains installed." >&2
    return 1
  }
  rm -f "$state_file"
  echo "Removed qvCORE Brave; its profile and personal files were preserved."
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
