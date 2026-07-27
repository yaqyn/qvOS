#!/bin/bash
set -euo pipefail

mode="install"
remove_assume_yes=0
remove_check=0
brave_package_installed=0
brave_ready=0
omarchy-pkg-present brave-origin-beta-bin &&
  brave_package_installed=1
((brave_package_installed)) &&
  omarchy-cmd-present brave-origin-beta &&
  brave_ready=1

usage() {
  echo "Usage: brave-origin.sh [--status|--state|--remove [--check|--yes]]" >&2
}

remove_brave_origin() {
  local command

  if ((brave_package_installed)); then
    for command in omarchy-pkg-drop omarchy-remove-browser pacman sudo; do
      if ! command -v "$command" >/dev/null 2>&1; then
        echo "qvCORE Brave removal requires: $command" >&2
        return 1
      fi
    done
    if ! pacman -Rs --print brave-origin-beta-bin >/dev/null; then
      echo "Pacman could not prepare the Brave Origin removal transaction." >&2
      return 1
    fi
  fi
  if ((remove_assume_yes == 0 && remove_check == 0)) &&
    ! command -v gum >/dev/null 2>&1; then
    echo "qvCORE Brave removal requires: gum" >&2
    return 1
  fi
  if ((remove_check)); then
    return 0
  fi
  if ((brave_package_installed == 0)); then
    echo "qvCORE Brave Origin is not installed; nothing was changed."
    return 0
  fi

  echo "Remove Brave Origin and its qvOS/Omarchy browser integration."
  echo "The browser profile and personal data will be preserved."
  if ((remove_assume_yes == 0)); then
    gum confirm "Remove Brave Origin while preserving its profile and data?" ||
      {
        echo "qvCORE Brave removal canceled; nothing was changed."
        return 130
      }
  fi

  omarchy-remove-browser brave-origin
  if omarchy-pkg-present brave-origin-beta-bin; then
    echo "qvCORE Brave removal failed: brave-origin-beta-bin remains installed." >&2
    return 1
  fi
  echo "Removed Brave Origin; its browser profile and personal data were preserved."
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
--status | --state)
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

case $mode in
install)
  omarchy-install-browser brave-origin
  omarchy-default-browser brave-origin
  ;;
status)
  if ((brave_ready)); then
    echo "qvCORE Brave is installed."
  else
    echo "qvCORE Brave is not installed."
  fi
  ((brave_ready))
  ;;
state)
  if ((brave_ready)); then
    echo "ready"
  else
    echo "not-installed"
  fi
  ;;
remove)
  remove_brave_origin
  ;;
esac
