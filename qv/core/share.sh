#!/bin/bash
# qvcore:lifecycle=1
set -euo pipefail

# Owned paths and state

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
mode="install"

package_ready=0
helper_ready=0
integration_ready=0
firewall_ready_state=0
maintenance_ready=0

# shellcheck source=qv/thunar/actions.sh
source "$thunar_actions_source"

# Integration inventory

usage() {
  echo "Usage: share.sh [--status|--repair|--adopt|--disable]" >&2
}

status_label() {
  if (($1)); then
    printf 'ready\n'
  else
    printf 'missing\n'
  fi
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

firewall_is_ready() {
  [[ -f $firewall_profile_target ]] &&
    cmp -s "$firewall_profile_source" "$firewall_profile_target" &&
    firewall_rules_include_localsend "$firewall_rules_v4" ||
    return 1

  if firewall_ipv6_enabled; then
    firewall_rules_include_localsend "$firewall_rules_v6"
  fi
}

maintenance_is_ready() {
  [[ -f $state_file ]]
}

inventory_components() {
  package_ready=0
  helper_ready=0
  integration_ready=0
  firewall_ready_state=0
  maintenance_ready=0

  omarchy-pkg-present localsend && omarchy-cmd-present localsend &&
    package_ready=1
  [[ -x $thunar_share_runtime ]] &&
    cmp -s "$thunar_share_source" "$thunar_share_runtime" &&
    helper_ready=1
  share_action_matches && integration_ready=1
  firewall_is_ready && firewall_ready_state=1
  maintenance_is_ready && maintenance_ready=1
  return 0
}

print_inventory() {
  local ready_count=$((package_ready +
    helper_ready +
    integration_ready +
    firewall_ready_state +
    maintenance_ready))

  echo ""
  echo "qvCORE Share inventory: $ready_count/5 ready"
  printf '  %-20s %s\n' "LocalSend" "$(status_label "$package_ready")"
  printf '  %-20s %s\n' "Thunar helper" "$(status_label "$helper_ready")"
  printf '  %-20s %s\n' "Thunar integration" \
    "$(status_label "$integration_ready")"
  printf '  %-20s %s\n' "Firewall policy" \
    "$(status_label "$firewall_ready_state")"
  printf '  %-20s %s\n' "Update tracking" \
    "$(status_label "$maintenance_ready")"
}

# Firewall ownership

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

disable_firewall_policy() {
  if [[ -f $firewall_profile_target ]]; then
    sudo ufw delete allow "qvCORE Share" >/dev/null 2>&1 || true
    sudo rm -f "$firewall_profile_target"
  fi

  # Clean the inherited Omarchy rules when qvCORE Share is disabled.
  if firewall_rules_include_localsend "$firewall_rules_v4"; then
    sudo ufw delete allow 53317/tcp >/dev/null 2>&1 || true
    sudo ufw delete allow 53317/udp >/dev/null 2>&1 || true
  fi
}

# User integration lifecycle

install_thunar_helper() {
  install -d "$HOME/.local/share/qvos/thunar"
  install -m 0755 "$thunar_share_source" "$thunar_share_runtime"
}

install_thunar_integration() {
  qvos_thunar_ensure_action \
    "qvos-localsend-share" \
    "localsend" \
    "Send via LocalSend" \
    "$thunar_share_command" \
    "Send the selected files and folders to nearby devices." \
    "*" \
    directories audio-files image-files other-files text-files video-files
}

install_maintenance() {
  install -D -m 0644 /dev/null "$state_file"
}

disable_share() {
  qvos_thunar_remove_action "qvos-localsend-share"
  disable_firewall_policy
  rm -f "$state_file" "$thunar_share_runtime"
  echo "qvCORE Share integration is disabled; LocalSend and personal data were not changed."
}

# Entry point

if (($# > 1)); then
  usage
  exit 2
fi

case ${1:-} in
"") ;;
--status) mode="status" ;;
--integration-status) mode="integration-status" ;;
--repair) mode="repair" ;;
--adopt) mode="adopt" ;;
--disable) mode="disable" ;;
*)
  usage
  exit 2
  ;;
esac

for command in omarchy-qvos-share xmlstarlet ufw; do
  if omarchy-cmd-missing "$command"; then
    echo "qvCORE Share requires the qvOS base command: $command" >&2
    exit 1
  fi
done

for source_file in \
  "$thunar_actions_source" \
  "$thunar_share_source" \
  "$firewall_profile_source"; do
  if [[ ! -f $source_file ]]; then
    echo "qvCORE Share source is missing: $source_file" >&2
    exit 1
  fi
done

inventory_components
print_inventory

if [[ $mode == "status" || $mode == "integration-status" ]]; then
  ((package_ready && helper_ready && integration_ready &&
    firewall_ready_state && maintenance_ready))
  exit
fi

if [[ $mode == "disable" ]]; then
  disable_share
  exit
fi

if [[ $mode == "repair" && ! -f $state_file ]]; then
  echo "qvCORE Share is not enabled; nothing was repaired."
  exit 0
fi

if [[ $mode == "repair" && $package_ready == 0 ]]; then
  disable_share
  exit 0
fi

if [[ $mode == "install" && $package_ready == 0 ]]; then
  echo ""
  echo "Installing LocalSend..."
  omarchy-pkg-add localsend
fi

if omarchy-pkg-missing localsend || omarchy-cmd-missing localsend; then
  echo "LocalSend verification failed after installation." >&2
  exit 1
fi

if ((helper_ready == 0)); then
  install_thunar_helper
fi

if ((integration_ready == 0)); then
  install_thunar_integration
fi

if ((firewall_ready_state == 0)); then
  echo ""
  echo "Authorizing the qvCORE Share firewall policy..."
  install_firewall_policy
fi

install_maintenance

inventory_components
print_inventory

if ((package_ready == 0 || helper_ready == 0 || integration_ready == 0 ||
  firewall_ready_state == 0 || maintenance_ready == 0)); then
  echo "qvCORE Share is incomplete." >&2
  exit 1
fi

echo ""
echo "qvCORE Share is ready: 5/5."
