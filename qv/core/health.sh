#!/bin/bash
set -euo pipefail

# Component registry

OMARCHY_PATH=${OMARCHY_PATH:-$HOME/.local/share/omarchy}
component_dir="$OMARCHY_PATH/qv/core"
mode="${1:-status}"
ready_count=0
partial_count=0
missing_count=0

components=(
  warp
  brave-origin
  share
  dev
  codex
  proton
  steam
  media
)

declare -A component_names=(
  [warp]="WARP"
  [brave-origin]="Brave Origin"
  [share]="Share"
  [dev]="Devel"
  [codex]="Codex"
  [proton]="Proton"
  [steam]="Steam"
  [media]="Media"
)
declare -A component_icons=(
  [warp]="󰖂"
  [brave-origin]="󰖟"
  [share]=""
  [dev]="󰵮"
  [codex]="󱚤"
  [proton]="󰌾"
  [steam]=""
  [media]="󰕧"
)
declare -A component_state=()
declare -A component_detail=()

# Health inspection

command_present() {
  if command -v omarchy-cmd-present >/dev/null 2>&1; then
    omarchy-cmd-present "$1"
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

package_present() {
  omarchy-pkg-present "$1"
}

set_component_state() {
  local component=$1
  local state=$2
  local detail=$3

  component_state[$component]=$state
  component_detail[$component]=$detail
  case $state in
  ready) ready_count=$((ready_count + 1)) ;;
  partial) partial_count=$((partial_count + 1)) ;;
  missing) missing_count=$((missing_count + 1)) ;;
  esac
}

inspect_warp() {
  if ! command_present warp-cli; then
    set_component_state warp missing "not installed"
  elif warp-cli --json registration show </dev/null &>/dev/null; then
    set_component_state warp ready "registered; connection remains DNS-controlled"
  else
    set_component_state warp partial "installed but not registered"
  fi
}

inspect_brave() {
  if ! package_present brave-origin-beta-bin; then
    set_component_state brave-origin missing "not installed"
  elif [[ $(omarchy-default-browser 2>/dev/null || true) == "brave-origin" ]]; then
    set_component_state brave-origin ready "installed and default"
  else
    set_component_state brave-origin partial "installed but not default"
  fi
}

inspect_owned_component() {
  local component=$1
  local required_command=$2
  local script="$component_dir/$component.sh"

  if "$script" --status >/dev/null 2>&1; then
    set_component_state "$component" ready "complete integration"
  elif command_present "$required_command"; then
    set_component_state "$component" partial "installed with integration drift"
  else
    set_component_state "$component" missing "not installed"
  fi
}

inspect_dev() {
  local state_file="$HOME/.local/state/qvos/qvcore/dev"
  local hook="$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-dev"
  local source="$component_dir/dev/post-update.sh"

  if [[ -f $state_file && -f $hook ]] && cmp -s "$source" "$hook"; then
    set_component_state dev ready "enabled with post-update refresh"
  elif [[ -f $state_file ]] || command_present bun || command_present node; then
    set_component_state dev partial "installed with unverified or stale maintenance"
  else
    set_component_state dev missing "not installed"
  fi
}

inspect_steam() {
  local windows="$HOME/.config/hypr/qv/windows.conf"
  local bindings="$HOME/.config/hypr/qv/bindings.conf"

  if ! package_present steam; then
    set_component_state steam missing "not installed"
  elif [[ -f $windows && -f $bindings ]] &&
    grep -Fq 'workspace name:G silent' "$windows" &&
    grep -Fq 'SUPER CTRL, grave, Steam' "$bindings"; then
    set_component_state steam ready "installed with workspace G"
  else
    set_component_state steam partial "installed with desktop integration drift"
  fi
}

inspect_media() {
  local media_output

  if media_output=$("$component_dir/media.sh" --status 2>/dev/null); then
    if [[ $media_output =~ qvCORE\ Media\ inventory:\ ([0-9]+)/([0-9]+)\ ready ]]; then
      set_component_state media ready \
        "${BASH_REMATCH[1]}/${BASH_REMATCH[2]} optional applications installed"
    else
      set_component_state media partial "status output could not be read"
    fi
  elif [[ $media_output =~ qvCORE\ Media\ inventory:\ 0/([0-9]+)\ ready ]]; then
    set_component_state media missing "0/${BASH_REMATCH[1]} installed"
  else
    set_component_state media partial "status check failed"
  fi
}

inspect_all() {
  inspect_warp
  inspect_brave
  inspect_owned_component share localsend
  inspect_dev
  inspect_owned_component codex codex

  if "$component_dir/proton.sh" --status >/dev/null 2>&1; then
    set_component_state proton ready "complete local integration"
  elif command_present proton-drive ||
    command_present pass-cli ||
    command_present protonmail-bridge-core; then
    set_component_state proton partial "installed with integration or authentication drift"
  else
    set_component_state proton missing "not installed"
  fi

  inspect_steam
  inspect_media
}

# Status and repair presentation

print_status() {
  local component

  echo "qvCORE health"
  echo ""
  for component in "${components[@]}"; do
    printf '  %s  %-14s %-8s %s\n' \
      "${component_icons[$component]}" \
      "${component_names[$component]}" \
      "${component_state[$component]}" \
      "${component_detail[$component]}"
  done
  echo ""
  echo "Ready: $ready_count  Partial: $partial_count  Missing: $missing_count"
}

repair_component() {
  local options=()
  local component
  local selection

  for component in "${components[@]}"; do
    options+=(
      "${component_icons[$component]}  ${component_names[$component]} — ${component_state[$component]}:${component}"
    )
  done

  selection=$(gum choose \
    --label-delimiter ":" \
    --header "Choose one qvCORE component to install or repair" \
    "${options[@]}") || return $?
  [[ -n $selection ]] || return 130

  exec omarchy-install-qvcore "$selection"
}

# Entry point

case $mode in
status | repair) ;;
*)
  echo "Usage: health.sh [status|repair]" >&2
  exit 2
  ;;
esac

inspect_all
print_status
if [[ $mode == "repair" ]]; then
  repair_component
fi
