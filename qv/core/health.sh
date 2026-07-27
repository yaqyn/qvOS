#!/bin/bash
set -euo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-$HOME/.local/share/omarchy}
component_dir="$OMARCHY_PATH/qv/core"
catalog="$component_dir/catalog.tsv"
mode="${1:-status}"
target_component="${2:-}"
setup_components=()
integrated_setups=()
issues=()
remaining_issues=()
expected_repair_state="ready"

declare -A component_name=()
declare -A component_icon=()
declare -A catalog_component=()
declare -A setup_state=()
declare -A setup_detail=()
declare -A issue_action=()
declare -A issue_detail=()
declare -A issue_present=()

usage() {
  echo "Usage: health.sh [status [--check]|check|repair [warp|share|proton|steam]|maintain|disable]" >&2
}

load_setups() {
  local type component label icon extra
  local required_setup
  local required_setups=(warp share proton steam)

  [[ -f $catalog ]] || {
    echo "Missing qvCORE catalog: $catalog" >&2
    return 1
  }
  while IFS=$'\t' read -r type component label icon extra; do
    [[ -n $type && $type != "#"* ]] || continue
    if [[ $type != "app" && $type != "setup" ]] ||
      [[ -z $component || -z $label || -z $icon || -n $extra ]] ||
      [[ -n ${catalog_component[$component]+known} ]]; then
      echo "Invalid qvCORE catalog entry." >&2
      return 1
    fi
    catalog_component[$component]=1
    [[ $type == "setup" ]] || continue
    setup_components+=("$component")
    component_name[$component]=$label
    component_icon[$component]=$icon
  done <"$catalog"

  integrated_setups=(warp share proton)
  if ((${#setup_components[@]} != ${#required_setups[@]})); then
    echo "qvCORE catalog must define exactly four managed setups." >&2
    return 1
  fi
  for required_setup in "${required_setups[@]}"; do
    if [[ -z ${component_name[$required_setup]+known} ]]; then
      echo "Missing managed qvCORE setup in catalog: $required_setup" >&2
      return 1
    fi
  done
  for component in "${setup_components[@]}"; do
    if [[ ! -x $component_dir/$component.sh ]]; then
      echo "Missing managed qvCORE setup owner: $component" >&2
      return 1
    fi
  done
}

command_present() {
  if command -v omarchy-cmd-present >/dev/null 2>&1; then
    omarchy-cmd-present "$1"
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

setup_is_tracked() {
  [[ -f $HOME/.local/state/qvos/qvcore/$1 ]]
}

setup_application_present() {
  case $1 in
  warp) command_present warp-cli ;;
  share) command_present localsend ;;
  proton) command_present proton-drive ;;
  *) return 1 ;;
  esac
}

status_label() {
  case $1 in
  ready) printf 'Ready\n' ;;
  needs-repair) printf 'Partial\n' ;;
  available) printf 'Disabled\n' ;;
  removed) printf 'Missing\n' ;;
  partial) printf 'Partial\n' ;;
  not-installed) printf 'Missing\n' ;;
  *) printf 'Unknown\n' ;;
  esac
}

inspect_integrated_setup() {
  local component=$1

  if setup_is_tracked "$component"; then
    if ! setup_application_present "$component"; then
      setup_state[$component]="removed"
      setup_detail[$component]="software removed; integration cleanup remains"
    elif "$component_dir/$component.sh" \
      --integration-status >/dev/null 2>&1; then
      setup_state[$component]="ready"
      setup_detail[$component]="enabled setup is healthy"
    else
      setup_state[$component]="needs-repair"
      setup_detail[$component]="enabled setup integration drift"
    fi
  elif setup_application_present "$component"; then
    setup_state[$component]="available"
    setup_detail[$component]="software present; setup integration disabled"
  else
    setup_state[$component]="not-installed"
    setup_detail[$component]="setup is not installed"
  fi
}

inspect_steam_setup() {
  local state

  if ! state=$("$component_dir/steam.sh" --state 2>/dev/null); then
    state="unknown"
  fi
  case $state in
  ready)
    setup_state[steam]="ready"
    setup_detail[steam]="Steam and curated gaming dependencies are installed"
    ;;
  partial)
    setup_state[steam]="partial"
    setup_detail[steam]="Steam is installed; gaming dependencies are incomplete"
    ;;
  not-installed)
    setup_state[steam]="not-installed"
    setup_detail[steam]="Steam setup is not installed"
    ;;
  *)
    setup_state[steam]="needs-repair"
    setup_detail[steam]="Steam setup inventory could not be read"
    ;;
  esac
}

inspect_setups() {
  local component

  setup_state=()
  setup_detail=()
  for component in "${setup_components[@]}"; do
    case $component in
    steam) inspect_steam_setup ;;
    *) inspect_integrated_setup "$component" ;;
    esac
  done
}

print_setups() {
  local component

  echo ""
  echo "qvCORE Managed Setups"
  echo "qvCORE apps are normal personal software and are not graded here."
  echo ""
  for component in "${setup_components[@]}"; do
    printf '  %s  %-14s %-14s %s\n' \
      "${component_icon[$component]}" \
      "${component_name[$component]}" \
      "$(status_label "${setup_state[$component]}")" \
      "${setup_detail[$component]}"
  done
}

setups_need_attention() {
  local component

  for component in "${setup_components[@]}"; do
    case ${setup_state[$component]} in
    needs-repair | removed | partial) return 0 ;;
    esac
  done
  return 1
}

choose_setup() {
  local component selection
  local options=()

  for component in "${setup_components[@]}"; do
    options+=(
      "${component_icon[$component]}  ${component_name[$component]} — $(status_label "${setup_state[$component]}"):$component"
    )
  done
  selection=$(
    gum choose \
      --label-delimiter ":" \
      --header "Choose one managed qvCORE setup" \
      "${options[@]}"
  ) || return 130
  [[ -n $selection ]] || return 130
  printf '%s\n' "$selection"
}

confirm_action() {
  local prompt=$1

  if ! gum confirm "$prompt"; then
    echo "qvCORE setup repair canceled."
    return 130
  fi
}

repair_setup() {
  local component=$1
  local removed_action
  local state=${setup_state[$component]}

  expected_repair_state="ready"
  case $state in
  ready)
    echo ""
    echo "${component_name[$component]} is already ready; no changes were made."
    ;;
  needs-repair)
    confirm_action "Repair the ${component_name[$component]} setup?" ||
      return $?
    if [[ $component == "steam" ]]; then
      "$component_dir/install" steam
    else
      "$component_dir/$component.sh" --repair
    fi
    ;;
  available)
    if [[ $component == "warp" ]]; then
      confirm_action "Adopt the existing WARP setup?" || return $?
      if ! "$component_dir/warp.sh" --adopt; then
        confirm_action "WARP is installed but not ready. Configure it now?" ||
          return $?
        "$component_dir/install" warp
      fi
    else
      confirm_action \
        "Enable the ${component_name[$component]} setup integration?" ||
        return $?
      "$component_dir/$component.sh" --adopt
    fi
    ;;
  removed)
    removed_action=$(
      gum choose \
        --header "${component_name[$component]} software was removed" \
        "Keep it removed and clean setup integration" \
        "Reinstall ${component_name[$component]}" \
        "Cancel"
    ) || return 130
    case $removed_action in
    "Keep it removed"*)
      "$component_dir/$component.sh" --disable
      expected_repair_state="not-installed"
      ;;
    "Reinstall "*)
      "$component_dir/$component.sh" --disable
      "$component_dir/install" "$component"
      ;;
    *)
      echo "qvCORE setup repair canceled."
      return 130
      ;;
    esac
    ;;
  partial)
    confirm_action \
      "Restore the missing ${component_name[$component]} dependencies?" ||
      return $?
    "$component_dir/install" "$component"
    ;;
  not-installed)
    confirm_action "Install the ${component_name[$component]} setup?" ||
      return $?
    "$component_dir/install" "$component"
    ;;
  *)
    echo "Unknown managed setup state: $state" >&2
    return 1
    ;;
  esac
}

status_setups() {
  inspect_setups
  print_setups
}

check_setups() {
  inspect_setups
  print_setups
  ! setups_need_attention
}

repair_setups() {
  local component=$target_component

  inspect_setups
  print_setups
  if [[ -z $component ]]; then
    component=$(choose_setup) || return $?
  fi
  if [[ -z ${component_name[$component]+known} ]]; then
    echo "Unknown managed qvCORE setup: $component" >&2
    return 2
  fi

  repair_setup "$component"
  inspect_setups
  print_setups
  if [[ ${setup_state[$component]} != "$expected_repair_state" ]]; then
    echo "${component_name[$component]} did not reach its expected setup state." >&2
    return 1
  fi
}

reset_maintenance_state() {
  issue_action=()
  issue_detail=()
  issue_present=()
  issues=()
  remaining_issues=()
}

add_issue() {
  local component=$1
  local detail=$2
  local action=$3

  [[ -z ${issue_present[$component]:-} ]] || return
  issues+=("$component")
  issue_present[$component]=1
  issue_detail[$component]=$detail
  issue_action[$component]=$action
}

inspect_enabled_integrations() {
  local component

  for component in "${integrated_setups[@]}"; do
    setup_is_tracked "$component" || continue
    if ! setup_application_present "$component"; then
      add_issue "$component" "removed software cleanup" "--disable"
    elif ! "$component_dir/$component.sh" \
      --integration-status >/dev/null 2>&1; then
      add_issue "$component" "integration drift" "--repair"
    fi
  done
}

maintenance_action_succeeded() {
  local component=$1
  local action=$2

  if [[ $action == "--disable" ]]; then
    if setup_is_tracked "$component"; then
      return 1
    fi
    return 0
  else
    setup_is_tracked "$component" &&
      setup_application_present "$component" &&
      "$component_dir/$component.sh" \
        --integration-status >/dev/null 2>&1
  fi
}

maintain_enabled_setups() {
  local action component output

  reset_maintenance_state
  inspect_enabled_integrations
  ((${#issues[@]} > 0)) || return 0

  echo ""
  echo "Maintaining enabled qvCORE setups:"
  for component in "${issues[@]}"; do
    action=${issue_action[$component]}
    printf '  %s — %s\n' \
      "${component_name[$component]}" \
      "${issue_detail[$component]}"
    if output=$("$component_dir/$component.sh" "$action" 2>&1) &&
      maintenance_action_succeeded "$component" "$action"; then
      continue
    fi
    remaining_issues+=("$component")
    printf '  %s maintenance did not finish.\n' \
      "${component_name[$component]}" >&2
    [[ -z $output ]] || printf '%s\n' "$output" >&2
  done

  if ((${#remaining_issues[@]} > 0)); then
    echo 'Run "omarchy qvcore repair" to review the remaining setup.' >&2
    return 1
  fi
  echo "Enabled qvCORE setup maintenance is complete."
}

disable_integrations() {
  local component selection
  local options=()
  local tracked=()

  for component in "${integrated_setups[@]}"; do
    setup_is_tracked "$component" || continue
    tracked+=("$component")
    options+=(
      "${component_icon[$component]}  ${component_name[$component]}:$component"
    )
  done

  if ((${#tracked[@]} == 0)); then
    echo "No managed qvCORE setup integrations are enabled."
    return
  fi

  options=("󰑐  All enabled setup integrations:all" "${options[@]}")
  selection=$(
    gum choose \
      --label-delimiter ":" \
      --header "Disable setup integration; software and data stay" \
      "${options[@]}"
  ) || return $?
  [[ -n $selection ]] || return 130

  if [[ $selection == "all" ]]; then
    gum confirm \
      "Disable all ${#tracked[@]} enabled setup integration(s)?" ||
      return 130
  else
    gum confirm \
      "Disable the ${component_name[$selection]} setup integration?" ||
      return 130
    tracked=("$selection")
  fi

  for component in "${tracked[@]}"; do
    "$component_dir/$component.sh" --disable
  done

  echo ""
  echo "Installed software, authentication, network choices, and personal data were preserved."
}

if [[ $mode == "status" && $target_component == "--check" ]]; then
  mode="check"
  target_component=""
fi

if (($# > 2)) ||
  [[ -n $target_component && $mode != "repair" ]]; then
  usage
  exit 2
fi

load_setups

case $mode in
status) status_setups ;;
check) check_setups ;;
repair) repair_setups ;;
maintain) maintain_enabled_setups ;;
disable) disable_integrations ;;
*)
  usage
  exit 2
  ;;
esac
