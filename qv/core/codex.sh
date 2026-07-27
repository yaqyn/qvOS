#!/bin/bash
# qvcore:app-integration=1
set -euo pipefail

# Owned paths and state

component_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_file="$HOME/.local/state/qvos/qvcore/codex"
thunar_actions_source="$component_dir/../thunar/actions.sh"
thunar_codex_source="$component_dir/../thunar/codex"
thunar_codex_runtime="$HOME/.local/share/qvos/thunar/codex"
thunar_codex_command="/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/codex\" \"\$1\"' qvos-thunar %f"
codex_binary="$HOME/.local/bin/codex"
mode="install"
metadata_proxy_dir=""

codex_ready=0
helper_ready=0
integration_ready=0
maintenance_ready=0

# shellcheck source=qv/thunar/actions.sh
source "$thunar_actions_source"

# Integration inventory

cleanup() {
  if [[ -n $metadata_proxy_dir && -d $metadata_proxy_dir ]]; then
    rm -rf "$metadata_proxy_dir"
  fi
}
trap cleanup EXIT

usage() {
  echo "Usage: codex.sh [--status|--repair|--adopt|--disable|--prepare-remove]" >&2
}

status_label() {
  if (($1)); then
    printf 'ready\n'
  else
    printf 'missing\n'
  fi
}

codex_action_matches() {
  qvos_thunar_action_matches \
    "qvos-codex-here" \
    "utilities-terminal" \
    "Open Codex Here" \
    "$thunar_codex_command" \
    "Start Codex safely in this folder." \
    "*" \
    directories
}

maintenance_is_ready() {
  [[ -f $state_file ]]
}

inventory_components() {
  codex_ready=0
  helper_ready=0
  integration_ready=0
  maintenance_ready=0

  [[ -x $codex_binary ]] && "$codex_binary" --version >/dev/null 2>&1 &&
    codex_ready=1
  [[ -x $thunar_codex_runtime ]] &&
    cmp -s "$thunar_codex_source" "$thunar_codex_runtime" &&
    helper_ready=1
  codex_action_matches && integration_ready=1
  maintenance_is_ready && maintenance_ready=1
  return 0
}

print_inventory() {
  local ready_count=$((codex_ready +
    helper_ready +
    integration_ready +
    maintenance_ready))

  echo ""
  echo "qvCORE Codex inventory: $ready_count/4 ready"
  printf '  %-20s %s\n' "Codex CLI" "$(status_label "$codex_ready")"
  printf '  %-20s %s\n' "Thunar helper" "$(status_label "$helper_ready")"
  printf '  %-20s %s\n' "Thunar integration" \
    "$(status_label "$integration_ready")"
  printf '  %-20s %s\n' "Desktop ownership" \
    "$(status_label "$maintenance_ready")"
}

# Installation and user integration

install_integration() {
  install -d "$HOME/.local/share/qvos/thunar"
  install -m 0755 "$thunar_codex_source" "$thunar_codex_runtime"
  qvos_thunar_ensure_action \
    "qvos-codex-here" \
    "utilities-terminal" \
    "Open Codex Here" \
    "$thunar_codex_command" \
    "Start Codex safely in this folder." \
    "*" \
    directories
  install -D -m 0644 /dev/null "$state_file"
}

disable_integration() {
  qvos_thunar_remove_action "qvos-codex-here"
  rm -f "$state_file" "$thunar_codex_runtime"
  echo "qvCORE Codex desktop integration is disabled; Codex and personal data were not changed."
}

install_codex() {
  local curl_path

  if omarchy-cmd-missing curl; then
    omarchy-pkg-add curl
  fi

  curl_path=$(command -v curl)
  if omarchy-cmd-present gh &&
    gh auth status --hostname github.com >/dev/null 2>&1; then
    metadata_proxy_dir=$(mktemp -d)
    install -m 0755 /dev/stdin "$metadata_proxy_dir/curl" <<EOF
#!/bin/bash
for argument in "\$@"; do
  case \$argument in
  https://api.github.com/*)
    exec gh api "\${argument#https://api.github.com/}"
    ;;
  esac
done

exec "$curl_path" "\$@"
EOF
  fi

  echo "Installing Codex from OpenAI..."
  "$curl_path" -fsSL https://chatgpt.com/codex/install.sh |
    PATH="${metadata_proxy_dir:+$metadata_proxy_dir:}$PATH" \
      CODEX_INSTALL_DIR="$HOME/.local/bin" \
      CODEX_NON_INTERACTIVE=1 \
      sh

  "$codex_binary" --version
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
--prepare-remove) mode="prepare-remove" ;;
*)
  usage
  exit 2
  ;;
esac

inventory_components
print_inventory

if [[ $mode == "status" || $mode == "integration-status" ]]; then
  ((codex_ready && helper_ready && integration_ready && maintenance_ready))
  exit
fi

if [[ $mode == "disable" || $mode == "prepare-remove" ]]; then
  disable_integration
  if [[ $mode == "prepare-remove" ]]; then
    echo "Codex desktop integration is ready for software removal."
  fi
  exit
fi

if [[ $mode == "repair" && ! -f $state_file ]]; then
  echo "qvCORE Codex is not enabled; nothing was repaired."
  exit 0
fi

if [[ $mode != "install" && $codex_ready == 0 ]]; then
  disable_integration
  if [[ $mode == "repair" ]]; then
    exit 0
  fi
  exit 1
fi

if [[ $mode == "install" ]]; then
  install_codex
fi

install_integration
inventory_components
print_inventory

if ((codex_ready == 0 || helper_ready == 0 ||
  integration_ready == 0 || maintenance_ready == 0)); then
  echo "qvCORE Codex is incomplete." >&2
  exit 1
fi

echo ""
echo "qvCORE Codex is ready: 4/4."
