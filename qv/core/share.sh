#!/bin/bash
set -euo pipefail

component_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_file="$HOME/.local/state/qvos/qvcore/share"
thunar_actions_source="$component_dir/../thunar/actions.sh"
thunar_share_source="$component_dir/../thunar/share"
thunar_share_runtime="$HOME/.local/share/qvos/thunar/share"
thunar_share_command="/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/share\" \"\$@\"' qvos-thunar %F"
firewall_profile_source="$component_dir/share/ufw.profile"
firewall_profile_target="${QVOS_SHARE_UFW_PROFILE_TARGET:-/etc/ufw/applications.d/qvos-qvcore-share}"
firewall_rules_v4="${QVOS_SHARE_UFW_RULES_V4:-/etc/ufw/user.rules}"
firewall_rules_v6="${QVOS_SHARE_UFW_RULES_V6:-/etc/ufw/user6.rules}"
firewall_defaults="${QVOS_SHARE_UFW_DEFAULTS:-/etc/default/ufw}"
assume_yes=0

# shellcheck source=qv/thunar/actions.sh
source "$thunar_actions_source"

usage() {
  echo "Usage: share.sh <install|remove> [--yes]" >&2
}

share_action_matches() {
  qvos_thunar_action_matches \
    "qvos-localsend-share" \
    "localsend" \
    "Send via LocalSend" \
    "$thunar_share_command" \
    "Send the selected files and folders to nearby devices." \
    "*" \
    directories audio-files image-files other-files text-files video-files
}

firewall_ipv6_enabled() {
  [[ ! -f $firewall_defaults ]] ||
    grep -Eq '^[[:space:]]*IPV6=(yes|true)[[:space:]]*$' "$firewall_defaults"
}

firewall_rules_include_localsend() {
  local rules_file=$1

  [[ -f $rules_file ]] &&
    grep -Eq -- '-p tcp .*--dports?[[:space:]]+53317([[:space:]]|$).*-j ACCEPT' "$rules_file" &&
    grep -Eq -- '-p udp .*--dports?[[:space:]]+53317([[:space:]]|$).*-j ACCEPT' "$rules_file"
}

firewall_ready() {
  [[ -f $firewall_profile_target ]] &&
    cmp -s "$firewall_profile_source" "$firewall_profile_target" &&
    firewall_rules_include_localsend "$firewall_rules_v4" ||
    return 1

  if firewall_ipv6_enabled; then
    firewall_rules_include_localsend "$firewall_rules_v6"
  fi
}

share_ready() {
  omarchy-pkg-present localsend &&
    omarchy-cmd-present localsend &&
    [[ -x $thunar_share_runtime ]] &&
    cmp -s "$thunar_share_source" "$thunar_share_runtime" &&
    share_action_matches &&
    firewall_ready
}

remove_inherited_firewall_rules() {
  firewall_rules_include_localsend "$firewall_rules_v4" || return 0
  [[ -f $firewall_profile_target ]] && return 0

  sudo ufw delete allow 53317/tcp >/dev/null 2>&1 || true
  sudo ufw delete allow 53317/udp >/dev/null 2>&1 || true
}

install_firewall_policy() {
  remove_inherited_firewall_rules
  sudo install -D -m 0644 "$firewall_profile_source" "$firewall_profile_target"
  sudo ufw app update "qvCORE Share" >/dev/null
  sudo ufw allow "qvCORE Share" >/dev/null
}

remove_firewall_policy() {
  if [[ -f $firewall_profile_target ]]; then
    sudo ufw delete allow "qvCORE Share" >/dev/null 2>&1 || true
    sudo rm -f "$firewall_profile_target"
  fi
  if firewall_rules_include_localsend "$firewall_rules_v4"; then
    sudo ufw delete allow 53317/tcp >/dev/null 2>&1 || true
    sudo ufw delete allow 53317/udp >/dev/null 2>&1 || true
  fi
}

install_integration() {
  install -d "$HOME/.local/share/qvos/thunar"
  install -m 0755 "$thunar_share_source" "$thunar_share_runtime"
  qvos_thunar_ensure_action \
    "qvos-localsend-share" \
    "localsend" \
    "Send via LocalSend" \
    "$thunar_share_command" \
    "Send the selected files and folders to nearby devices." \
    "*" \
    directories audio-files image-files other-files text-files video-files
  install_firewall_policy
}

remove_integration() {
  qvos_thunar_remove_action "qvos-localsend-share"
  remove_firewall_policy
  rm -f "$thunar_share_runtime"
}

install_stack() {
  for command in omarchy-qvos-share xmlstarlet ufw; do
    omarchy-cmd-present "$command" || {
      echo "qvCORE Share requires the qvOS base command: $command" >&2
      return 1
    }
  done
  if omarchy-pkg-missing localsend; then
    omarchy-pkg-add localsend
  fi
  install_integration
  share_ready || {
    echo "Share verification failed after installation." >&2
    return 1
  }

  install -D -m 0644 /dev/null "$state_file"
  echo "qvCORE Share is installed."
}

remove_stack() {
  if [[ ! -f $state_file ]]; then
    echo "qvCORE Share is not enrolled; nothing was changed."
    return
  fi

  for command in xmlstarlet ufw pacman gum; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "qvCORE Share removal requires: $command" >&2
      return 1
    }
  done
  if omarchy-pkg-present localsend &&
    ! pacman -Rs --print localsend >/dev/null; then
    echo "Pacman could not prepare the Share removal transaction." >&2
    return 1
  fi

  echo "LocalSend and its qvOS desktop/firewall integration will be removed."
  echo "LocalSend settings and personal files will be preserved."
  if ((assume_yes == 0)); then
    gum confirm "Remove the enrolled qvCORE Share stack?" || {
      echo "Share removal canceled; nothing was changed."
      return 130
    }
  fi

  remove_integration
  if omarchy-pkg-present localsend; then
    omarchy-pkg-drop localsend
  fi
  omarchy-pkg-missing localsend || {
    echo "Share removal failed: LocalSend remains installed." >&2
    return 1
  }
  rm -f "$state_file"
  echo "Removed qvCORE Share; settings and personal files were preserved."
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
