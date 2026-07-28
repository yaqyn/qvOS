#!/bin/bash
set -euo pipefail

state_file="$HOME/.local/state/qvos/qvcore/warp"
assume_yes=0

usage() {
  echo "Usage: warp.sh <install|remove> [--yes]" >&2
}

warp_ready() {
  omarchy-cmd-present warp-cli &&
    systemctl is-enabled --quiet warp-svc.service &&
    systemctl is-active --quiet warp-svc.service &&
    warp-cli --json registration show </dev/null &>/dev/null &&
    warp-cli --json status 2>/dev/null |
      jq -e '.status == "Connected"' >/dev/null
}

install_stack() {
  omarchy-qvos-setup-dns WARP
  warp_ready || {
    echo "WARP verification failed after configuration." >&2
    return 1
  }

  install -D -m 0644 /dev/null "$state_file"
  echo "qvCORE WARP is installed."
}

remove_stack() {
  local removal_started=0

  if [[ ! -f $state_file ]]; then
    echo "qvCORE WARP is not enrolled; nothing was changed."
    return
  fi

  for command in omarchy-qvos-setup-dns pacman gum; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "qvCORE WARP removal requires: $command" >&2
      return 1
    }
  done
  if omarchy-pkg-present cloudflare-warp-nox-bin &&
    ! pacman -Rs --print cloudflare-warp-nox-bin >/dev/null; then
    echo "Pacman could not prepare the WARP removal transaction." >&2
    return 1
  fi

  echo "WARP software, service and network integration will be removed."
  echo "Cloudflare account data will not be changed."
  if ((assume_yes == 0)); then
    gum confirm "Remove the enrolled qvCORE WARP stack?" || {
      echo "WARP removal canceled; nothing was changed."
      return 130
    }
  fi

  restore_enrollment() {
    if ((removal_started)); then
      install -D -m 0644 /dev/null "$state_file"
    fi
  }
  trap restore_enrollment ERR
  removal_started=1
  omarchy-qvos-setup-dns DHCP
  if omarchy-pkg-present cloudflare-warp-nox-bin; then
    omarchy-pkg-drop cloudflare-warp-nox-bin
  fi
  omarchy-pkg-missing cloudflare-warp-nox-bin || {
    echo "WARP removal failed: cloudflare-warp-nox-bin remains installed." >&2
    return 1
  }
  removal_started=0
  rm -f "$state_file"
  trap - ERR
  echo "Removed qvCORE WARP; Cloudflare account data was preserved."
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
