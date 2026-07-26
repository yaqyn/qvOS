#!/bin/bash
set -euo pipefail

# Component registry

OMARCHY_PATH=${OMARCHY_PATH:-$HOME/.local/share/omarchy}
component_dir="$OMARCHY_PATH/qv/core"
mode="${1:-status}"
ready_count=0
partial_count=0
disabled_count=0
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
lifecycle_components=(
  share
  dev
  codex
  proton
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
declare -A update_issue_detail=()
declare -A update_issue_present=()

legacy_hook_targets=(
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-share"
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-dev"
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-codex"
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-proton"
)

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
  disabled) disabled_count=$((disabled_count + 1)) ;;
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
  local state_file="$HOME/.local/state/qvos/qvcore/$component"

  if "$script" --integration-status >/dev/null 2>&1; then
    set_component_state "$component" ready "complete integration"
  elif [[ -f $state_file ]] && ! command_present "$required_command"; then
    set_component_state "$component" disabled "application removed; integration no longer expected"
  elif [[ -f $state_file ]]; then
    set_component_state "$component" partial "enabled with integration drift"
  elif command_present "$required_command"; then
    set_component_state "$component" disabled "installed; integration disabled"
  else
    set_component_state "$component" missing "not installed"
  fi
}

inspect_dev() {
  local state_file="$HOME/.local/state/qvos/qvcore/dev"

  if "$component_dir/dev.sh" --integration-status >/dev/null 2>&1; then
    set_component_state dev ready "enabled for installed-tool refresh"
  elif [[ -f $state_file ]]; then
    set_component_state dev partial "enabled with unavailable lifecycle owner"
  elif command_present bun || command_present node; then
    set_component_state dev disabled "tools installed; maintenance disabled"
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
  ready_count=0
  partial_count=0
  disabled_count=0
  missing_count=0
  component_state=()
  component_detail=()

  inspect_warp
  inspect_brave
  inspect_owned_component share localsend
  inspect_dev
  inspect_owned_component codex codex

  if "$component_dir/proton.sh" --integration-status >/dev/null 2>&1; then
    set_component_state proton ready "complete local integration"
  elif [[ -f $HOME/.local/state/qvos/qvcore/proton ]] &&
    ! command_present proton-drive; then
    set_component_state proton disabled "Drive removed; desktop integration no longer expected"
  elif [[ -f $HOME/.local/state/qvos/qvcore/proton ]]; then
    set_component_state proton partial "enabled with integration drift"
  elif command_present proton-drive ||
    command_present pass-cli ||
    command_present protonmail-bridge-core; then
    set_component_state proton disabled "services installed; desktop integration disabled"
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
  echo "Ready: $ready_count  Partial: $partial_count  Disabled: $disabled_count  Missing: $missing_count"
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

repair_enabled_components() {
  local component
  local repaired_count=0
  local repair_failed=0

  for component in "${lifecycle_components[@]}"; do
    if [[ ! -f $HOME/.local/state/qvos/qvcore/$component ]]; then
      continue
    fi

    echo "Repairing qvCORE ${component_names[$component]} integration..."
    if "$component_dir/$component.sh" --repair; then
      repaired_count=$((repaired_count + 1))
    else
      repair_failed=1
    fi
  done

  if ((repaired_count == 0 && repair_failed == 0)); then
    echo "No enabled qvCORE integrations need repair."
  fi

  ((repair_failed == 0))
}

disable_integrations() {
  local options=()
  local enabled_components=()
  local component
  local selection

  for component in "${lifecycle_components[@]}"; do
    if [[ -f $HOME/.local/state/qvos/qvcore/$component ]]; then
      enabled_components+=("$component")
      options+=(
        "${component_icons[$component]}  ${component_names[$component]}:$component"
      )
    fi
  done

  if ((${#enabled_components[@]} == 0)); then
    echo "No qvCORE integrations are enabled."
    return
  fi

  options=("󰑐  All enabled integrations:all" "${options[@]}")
  selection=$(gum choose \
    --label-delimiter ":" \
    --header "Disable integrations; installed applications and data stay" \
    "${options[@]}") || return $?
  [[ -n $selection ]] || return 130

  if [[ $selection == "all" ]]; then
    gum confirm \
      "Disable all ${#enabled_components[@]} enabled qvCORE integration(s)?" ||
      return 130
  else
    gum confirm "Disable the qvCORE ${component_names[$selection]} integration?" ||
      return 130
    enabled_components=("$selection")
  fi

  for component in "${enabled_components[@]}"; do
    "$component_dir/$component.sh" --disable
  done

  echo ""
  echo "Installed applications, authentication, network choices, and personal data were preserved."
}

# Quiet update maintenance

component_application_present() {
  local component=$1
  local command

  case $component in
  share)
    command_present localsend
    ;;
  dev)
    for command in \
      node \
      bun \
      mkcert \
      hurl \
      hurlfmt \
      supabase \
      infisical \
      cloudflared \
      sentry-cli \
      act \
      sops \
      age \
      age-keygen \
      gitleaks \
      osv-scanner \
      semgrep; do
      if command_present "$command"; then
        return 0
      fi
    done
    return 1
    ;;
  codex)
    command_present codex
    ;;
  proton)
    command_present proton-drive
    ;;
  esac
}

remove_legacy_component_hooks() {
  local hook

  for hook in "${legacy_hook_targets[@]}"; do
    rm -f "$hook"
  done
}

add_update_issue() {
  local component=$1
  local detail=$2

  [[ -z ${update_issue_present[$component]:-} ]] || return
  update_issues+=("$component")
  update_issue_present[$component]=1
  update_issue_detail[$component]=$detail
}

retire_removed_components() {
  local component
  local output

  for component in "${lifecycle_components[@]}"; do
    [[ -f $HOME/.local/state/qvos/qvcore/$component ]] || continue
    component_application_present "$component" && continue

    if output=$("$component_dir/$component.sh" --disable 2>&1); then
      :
    else
      add_update_issue \
        "$component" \
        "removed application cleanup did not finish"
    fi
  done
}

inspect_enabled_for_update() {
  local component
  local output

  for component in "${lifecycle_components[@]}"; do
    [[ -f $HOME/.local/state/qvos/qvcore/$component ]] || continue

    if [[ $component == "dev" ]]; then
      if ! output=$("$component_dir/$component.sh" --update 2>&1); then
        add_update_issue "$component" "installed-tool refresh did not finish"
      fi
    elif ! output=$(
      "$component_dir/$component.sh" --integration-status 2>&1
    ); then
      add_update_issue "$component" "enabled integration drift"
    fi
  done
}

print_update_issues() {
  local component

  echo ""
  echo "qvCORE needs attention:"
  for component in "${update_issues[@]}"; do
    printf '  %s — %s\n' \
      "${component_names[$component]}" \
      "${update_issue_detail[$component]}"
  done
}

repair_update_issues() {
  local component
  local output
  local repair_action

  remaining_issues=()
  for component in "${update_issues[@]}"; do
    if [[ $component == "dev" ]]; then
      repair_action="--update"
    else
      repair_action="--repair"
    fi

    if output=$("$component_dir/$component.sh" "$repair_action" 2>&1); then
      if [[ ! -f $HOME/.local/state/qvos/qvcore/$component ]] ||
        "$component_dir/$component.sh" --integration-status >/dev/null 2>&1; then
        continue
      fi
      output="The repair command completed, but integration drift remains."
    fi

    remaining_issues+=("$component")
    echo ""
    echo "qvCORE ${component_names[$component]} repair did not finish:"
    if [[ -n $output ]]; then
      while IFS= read -r line; do
        printf '  %s\n' "$line"
      done <<<"$output"
    fi
  done
}

update_enabled_components() {
  local issue_label="issues"

  update_issues=()
  remaining_issues=()
  update_issue_present=()
  remove_legacy_component_hooks
  retire_removed_components

  inspect_enabled_for_update
  if ((${#update_issues[@]} == 0)); then
    echo ""
    echo "qvCORE is ready."
    return
  fi

  print_update_issues
  echo ""
  ((${#update_issues[@]} == 1)) && issue_label="issue"
  if gum confirm "Repair ${#update_issues[@]} qvCORE integration $issue_label now?"; then
    repair_update_issues
    if ((${#remaining_issues[@]} == 0)); then
      echo ""
      echo "qvCORE is ready."
    else
      echo ""
      echo "qvCORE still needs attention. Run \"omarchy qvcore repair\" later."
    fi
  else
    echo "qvCORE repair skipped. Run \"omarchy qvcore repair\" later."
  fi
}

# Entry point

case $mode in
status | repair | repair-enabled | disable | update) ;;
*)
  echo "Usage: health.sh [status|repair|repair-enabled|disable|update]" >&2
  exit 2
  ;;
esac

if [[ $mode == "update" ]]; then
  update_enabled_components
  exit
fi

inspect_all
print_status
case $mode in
repair)
  repair_component
  ;;
repair-enabled)
  repair_enabled_components
  inspect_all
  print_status
  ;;
disable)
  disable_integrations
  inspect_all
  print_status
  ;;
esac
