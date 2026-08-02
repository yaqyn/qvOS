#!/bin/bash
set -euo pipefail

# qvos:contract=qv/core/qvdev/packages.tsv
# qvos:contract=qv/direct/tool
# qvos:contract=qv/thunar/actions.sh
# qvos:contract=qv/thunar/codex

component_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_manifest="$component_dir/qvdev/packages.tsv"
direct_tool="$component_dir/../direct/tool"
state_file="$HOME/.local/state/qvos/qvcore/qvdev"
thunar_actions_source="$component_dir/../thunar/actions.sh"
thunar_codex_source="$component_dir/../thunar/codex"
thunar_codex_runtime="$HOME/.local/share/qvos/thunar/codex"
thunar_codex_command="/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/codex\" \"\$1\"' qvos-thunar %f"
assume_yes=0

# shellcheck source=qv/thunar/actions.sh
source "$thunar_actions_source"

usage() {
  echo "Usage: qvdev.sh <install|remove> [--yes]" >&2
}

package_ready() {
  local package=$1
  local commands=$2
  local command_name
  local command_list=()

  omarchy-pkg-present "$package" || return 1
  read -r -a command_list <<<"$commands"
  for command_name in "${command_list[@]}"; do
    if [[ $command_name == /* ]]; then
      [[ -x $command_name ]] || return 1
    else
      omarchy-cmd-present "$command_name" || return 1
    fi
  done
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

integration_ready() {
  [[ -x $thunar_codex_runtime ]] &&
    cmp -s "$thunar_codex_source" "$thunar_codex_runtime" &&
    codex_action_matches
}

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
}

remove_integration() {
  qvos_thunar_remove_action "qvos-codex-here"
  rm -f "$thunar_codex_runtime"
}

verify_packages() {
  local source
  local package
  local label
  local commands
  local extra

  while IFS=$'\t' read -r source package label commands extra; do
    [[ -n $source && $source != "#"* ]] || continue
    [[ $source == "pacman" || $source == "aur" ]] &&
      [[ -n $package && -n $label && -n $commands && -z ${extra:-} ]] || {
      echo "Invalid qvDEV package manifest entry: $package" >&2
      return 1
    }
    package_ready "$package" "$commands" || {
      echo "qvDEV package verification failed: $label" >&2
      return 1
    }
  done <"$package_manifest"
}

verify_direct_tools() {
  local tool_id

  while IFS= read -r tool_id; do
    "$direct_tool" verify "$tool_id" || {
      echo "qvDEV direct-tool verification failed: $tool_id" >&2
      return 1
    }
  done < <("$direct_tool" list-scope qvdev)
}

install_stack() {
  local source
  local package
  local label
  local commands
  local extra
  local missing=()
  local tool_id

  [[ -f $package_manifest && -x $direct_tool ]] || {
    echo "qvDEV source is incomplete." >&2
    return 1
  }

  while IFS=$'\t' read -r source package label commands extra; do
    [[ -n $source && $source != "#"* ]] || continue
    if ! package_ready "$package" "$commands"; then
      missing+=("$package")
    fi
  done <"$package_manifest"
  if ((${#missing[@]} > 0)); then
    omarchy-pkg-add "${missing[@]}"
  fi

  while IFS= read -r tool_id; do
    if ! "$direct_tool" installed "$tool_id"; then
      "$direct_tool" install "$tool_id"
    fi
  done < <("$direct_tool" list-scope qvdev)

  install_integration
  verify_packages
  verify_direct_tools
  integration_ready || {
    echo "qvDEV Codex workbench integration verification failed." >&2
    return 1
  }

  install -D -m 0644 /dev/null "$state_file"
  echo "qvCORE qvDEV is installed."
}

remove_stack() {
  local source
  local package
  local label
  local commands
  local extra
  local installed_packages=()
  local direct_tools=()
  local index

  if [[ ! -f $state_file ]]; then
    echo "qvCORE qvDEV is not enrolled; nothing was changed."
    return
  fi

  while IFS=$'\t' read -r source package label commands extra; do
    [[ -n $source && $source != "#"* ]] || continue
    omarchy-pkg-present "$package" && installed_packages+=("$package")
  done <"$package_manifest"
  if ((${#installed_packages[@]} > 0)); then
    for command in pacman omarchy-pkg-drop gum; do
      command -v "$command" >/dev/null 2>&1 || {
        echo "qvDEV removal requires: $command" >&2
        return 1
      }
    done
    pacman -Rs --print "${installed_packages[@]}" >/dev/null || {
      echo "Pacman could not prepare the qvDEV removal transaction." >&2
      return 1
    }
  fi
  mapfile -t direct_tools < <("$direct_tool" list-scope qvdev)

  echo "qvDEV packages, direct tools and Codex workbench integration will be removed."
  echo "qvOS Codex, projects, credentials and personal files will be preserved."
  if ((assume_yes == 0)); then
    gum confirm "Remove the enrolled qvCORE qvDEV stack?" || {
      echo "qvDEV removal canceled; nothing was changed."
      return 130
    }
  fi

  remove_integration
  for ((index = ${#direct_tools[@]} - 1; index >= 0; index--)); do
    "$direct_tool" remove "${direct_tools[$index]}"
  done
  if ((${#installed_packages[@]} > 0)); then
    omarchy-pkg-drop "${installed_packages[@]}"
  fi

  for package in "${installed_packages[@]}"; do
    omarchy-pkg-missing "$package" || {
      echo "qvDEV removal failed: $package remains installed." >&2
      return 1
    }
  done
  for tool_id in "${direct_tools[@]}"; do
    if "$direct_tool" installed "$tool_id"; then
      echo "qvDEV removal failed: $tool_id remains installed." >&2
      return 1
    fi
  done
  rm -f "$state_file"
  echo "Removed qvCORE qvDEV; qvOS Codex, projects, credentials and personal files were preserved."
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
