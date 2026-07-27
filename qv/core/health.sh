#!/bin/bash
set -euo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-$HOME/.local/share/omarchy}
component_dir="$OMARCHY_PATH/qv/core"
mode="${1:-status}"
target_component="${2:-}"

lifecycle_components=(
  warp
  share
  dev
  codex
  proton
)
catalog_components=(
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
  ["brave-origin"]="Brave"
  [share]="Share"
  [dev]="Devel"
  [codex]="Codex"
  [proton]="Proton"
  [steam]="Steam"
  [media]="Media"
)
declare -A component_icons=(
  [warp]="󰖂"
  ["brave-origin"]="󰖟"
  [share]=""
  [dev]="󰵮"
  [codex]="󱚤"
  [proton]="󰌾"
  [steam]=""
  [media]="󰕧"
)
declare -A issue_action=()
declare -A issue_detail=()
declare -A issue_present=()
declare -A catalog_detail=()
declare -A catalog_state=()
enabled_components=()
issues=()
remaining_issues=()

# Enabled setup discovery

command_present() {
  if command -v omarchy-cmd-present >/dev/null 2>&1; then
    omarchy-cmd-present "$1"
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

component_is_tracked() {
  [[ -f $HOME/.local/state/qvos/qvcore/$1 ]]
}

component_application_present() {
  local component=$1
  local command

  case $component in
  warp)
    command_present warp-cli
    ;;
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

collect_enabled_components() {
  local component

  enabled_components=()
  for component in "${lifecycle_components[@]}"; do
    if component_is_tracked "$component" &&
      component_application_present "$component"; then
      enabled_components+=("$component")
    fi
  done
}

print_enabled_count() {
  collect_enabled_components
  printf '%d\n' "${#enabled_components[@]}"
}

# Shared maintenance engine

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

retire_removed_components() {
  local component

  for component in "${lifecycle_components[@]}"; do
    component_is_tracked "$component" || continue
    component_application_present "$component" && continue

    if ! "$component_dir/$component.sh" --disable >/dev/null 2>&1; then
      add_issue \
        "$component" \
        "removed application cleanup did not finish" \
        "--disable"
    fi
  done
}

inspect_enabled_components() {
  local refresh_tools=$1
  local component
  local output

  for component in "${enabled_components[@]}"; do
    if ((refresh_tools)) && [[ $component == "dev" ]]; then
      if ! output=$("$component_dir/$component.sh" --update 2>&1); then
        add_issue \
          "$component" \
          "installed-tool refresh did not finish" \
          "--update"
      fi
    elif ! output=$(
      "$component_dir/$component.sh" --integration-status 2>&1
    ); then
      add_issue \
        "$component" \
        "enabled setup integration drift" \
        "--repair"
    fi
  done
}

print_issues() {
  local component

  echo ""
  echo "Enabled qvCORE setups need attention:"
  for component in "${issues[@]}"; do
    printf '  %s — %s\n' \
      "${component_names[$component]}" \
      "${issue_detail[$component]}"
  done
}

repair_issues() {
  local component
  local action
  local output
  local repaired=0

  remaining_issues=()
  for component in "${issues[@]}"; do
    action=${issue_action[$component]}
    output=""
    repaired=0

    if output=$("$component_dir/$component.sh" "$action" 2>&1); then
      if [[ $action == "--disable" ]]; then
        component_is_tracked "$component" || repaired=1
      elif ! component_is_tracked "$component" ||
        "$component_dir/$component.sh" --integration-status >/dev/null 2>&1; then
        repaired=1
      fi
    fi

    if ((repaired)); then
      continue
    fi

    remaining_issues+=("$component")
    echo ""
    echo "qvCORE ${component_names[$component]} repair did not finish:"
    if [[ -n $output ]]; then
      while IFS= read -r line; do
        printf '  %s\n' "$line"
      done <<<"$output"
    else
      echo "  The owner completed without restoring the enabled setup."
    fi
  done

  ((${#remaining_issues[@]} == 0))
}

print_ready_summary() {
  local empty_policy=$1

  collect_enabled_components
  if ((${#enabled_components[@]} > 0)); then
    echo ""
    echo "Enabled qvCORE setups are ready."
  elif [[ $empty_policy == "show" ]]; then
    echo ""
    echo "No qvCORE setups are enabled."
  fi
}

print_repair_result() {
  local empty_policy=$1

  if ((${#remaining_issues[@]} > 0)); then
    echo ""
    echo "Enabled qvCORE setups still need attention."
    echo 'Run "omarchy qvcore repair" later.'
    return 1
  fi

  collect_enabled_components
  if ((${#enabled_components[@]} > 0)); then
    echo ""
    echo "Enabled qvCORE setups are ready."
  elif [[ $empty_policy == "show" ]]; then
    echo ""
    echo "No qvCORE setups are enabled."
  else
    echo ""
    echo "qvCORE cleanup is complete."
  fi
}

# Full optional catalog

catalog_status_label() {
  case $1 in
  ready) printf 'Ready\n' ;;
  needs-repair) printf 'Needs repair\n' ;;
  available) printf 'Available\n' ;;
  removed) printf 'Removed\n' ;;
  partial) printf 'Partial\n' ;;
  not-installed) printf 'Not installed\n' ;;
  *) printf 'Unknown\n' ;;
  esac
}

inspect_lifecycle_catalog_component() {
  local component=$1

  if component_is_tracked "$component"; then
    if ! component_application_present "$component"; then
      catalog_state[$component]="removed"
      catalog_detail[$component]="application removed; qvOS cleanup remains"
    elif "$component_dir/$component.sh" \
      --integration-status >/dev/null 2>&1; then
      catalog_state[$component]="ready"
      catalog_detail[$component]="enabled integration is healthy"
    else
      catalog_state[$component]="needs-repair"
      catalog_detail[$component]="enabled integration drift"
    fi
  elif component_application_present "$component"; then
    catalog_state[$component]="available"
    catalog_detail[$component]="application present; integration disabled"
  else
    catalog_state[$component]="not-installed"
    catalog_detail[$component]="optional setup is not installed"
  fi
}

inspect_application_catalog_component() {
  local component=$1
  local state

  if ! state=$("$component_dir/$component.sh" --state 2>/dev/null); then
    state="unknown"
  fi
  case $state in
  ready)
    catalog_state[$component]="ready"
    if [[ $component == "brave-origin" ]]; then
      catalog_detail[$component]="installed; default-browser choice is preserved"
    else
      catalog_detail[$component]="selected software is installed"
    fi
    ;;
  partial)
    catalog_state[$component]="partial"
    catalog_detail[$component]="some optional software is installed"
    ;;
  not-installed)
    catalog_state[$component]="not-installed"
    catalog_detail[$component]="optional software is not installed"
    ;;
  *)
    catalog_state[$component]="needs-repair"
    catalog_detail[$component]="component inventory could not be read"
    ;;
  esac
}

inspect_catalog() {
  local component

  catalog_detail=()
  catalog_state=()
  for component in "${catalog_components[@]}"; do
    case $component in
    brave-origin | steam | media)
      inspect_application_catalog_component "$component"
      ;;
    *)
      inspect_lifecycle_catalog_component "$component"
      ;;
    esac
  done
}

print_catalog() {
  local component

  echo ""
  echo "qvCORE Health / Repair"
  echo "Optional software that is absent is not considered broken."
  echo ""
  for component in "${catalog_components[@]}"; do
    printf '  %s  %-10s %-14s %s\n' \
      "${component_icons[$component]}" \
      "${component_names[$component]}" \
      "$(catalog_status_label "${catalog_state[$component]}")" \
      "${catalog_detail[$component]}"
  done
}

catalog_needs_attention() {
  local component

  for component in "${catalog_components[@]}"; do
    case ${catalog_state[$component]} in
    needs-repair | removed) return 0 ;;
    esac
  done
  return 1
}

choose_catalog_component() {
  local component
  local options=()
  local selection

  for component in "${catalog_components[@]}"; do
    options+=(
      "${component_icons[$component]}  ${component_names[$component]} — $(catalog_status_label "${catalog_state[$component]}"):$component"
    )
  done

  if ! selection=$(
    gum choose \
      --label-delimiter ":" \
      --header "Choose one qvCORE component" \
      "${options[@]}"
  ); then
    return 130
  fi
  [[ -n $selection ]] || return 130
  printf '%s\n' "$selection"
}

confirm_component_action() {
  local prompt=$1

  if ! gum confirm "$prompt"; then
    echo "qvCORE repair canceled."
    return 130
  fi
}

repair_catalog_component() {
  local component=$1
  local removed_action
  local state=${catalog_state[$component]}

  case $state in
  ready)
    echo ""
    echo "qvCORE ${component_names[$component]} is already ready; no changes were made."
    return
    ;;
  needs-repair)
    confirm_component_action \
      "Repair the enabled qvCORE ${component_names[$component]} integration?" ||
      return $?
    "$component_dir/$component.sh" --repair
    ;;
  available)
    if [[ $component == "warp" ]]; then
      confirm_component_action \
        "Enable qvCORE maintenance for the existing WARP setup?" ||
        return $?
      if ! "$component_dir/$component.sh" --adopt; then
        confirm_component_action \
          "WARP is installed but not ready. Configure it now?" ||
          return $?
        "$component_dir/install" "$component"
      fi
    else
      confirm_component_action \
        "Enable the qvCORE ${component_names[$component]} integration for the installed application?" ||
        return $?
      "$component_dir/$component.sh" --adopt
    fi
    ;;
  removed)
    if ! removed_action=$(
      gum choose \
        --header "${component_names[$component]} was removed" \
        "Keep it removed and clean qvOS integration state" \
        "Reinstall ${component_names[$component]}" \
        "Cancel"
    ); then
      return 130
    fi
    case $removed_action in
    "Keep it removed"*)
      "$component_dir/$component.sh" --disable
      ;;
    "Reinstall "*)
      "$component_dir/$component.sh" --disable
      "$component_dir/install" "$component"
      ;;
    *)
      echo "qvCORE repair canceled."
      return 130
      ;;
    esac
    ;;
  partial)
    if [[ $component == "media" ]]; then
      confirm_component_action \
        "Open Media to choose which missing applications to install?" ||
        return $?
    else
      confirm_component_action \
        "Restore the missing optional ${component_names[$component]} package set?" ||
        return $?
    fi
    "$component_dir/install" "$component"
    ;;
  not-installed)
    confirm_component_action \
      "Install the optional qvCORE ${component_names[$component]} component?" ||
      return $?
    "$component_dir/install" "$component"
    ;;
  *)
    echo "Unknown qvCORE component state: $state" >&2
    return 1
    ;;
  esac
}

status_catalog() {
  inspect_catalog
  print_catalog
  ! catalog_needs_attention
}

repair_catalog_interactive() {
  local component=$target_component

  inspect_catalog
  print_catalog
  if [[ -z $component ]]; then
    component=$(choose_catalog_component) || return $?
  fi
  if [[ -z ${component_names[$component]+known} ]]; then
    echo "Unknown qvCORE component: $component" >&2
    return 2
  fi

  repair_catalog_component "$component"
  inspect_catalog
  print_catalog
}

# User-facing operations

repair_enabled_components_automatic() {
  reset_maintenance_state
  retire_removed_components
  collect_enabled_components
  inspect_enabled_components 0

  if ((${#issues[@]} == 0)); then
    print_ready_summary silent
    return
  fi

  print_issues
  repair_issues || true
  print_repair_result silent
}

update_enabled_components() {
  local issue_label="issues"

  reset_maintenance_state
  retire_removed_components
  collect_enabled_components
  inspect_enabled_components 1

  if ((${#issues[@]} == 0)); then
    print_ready_summary silent
    return
  fi

  print_issues
  ((${#issues[@]} == 1)) && issue_label="issue"
  echo ""
  if gum confirm \
    "Repair ${#issues[@]} enabled qvCORE setup $issue_label now?"; then
    repair_issues || true
    print_repair_result silent || true
  else
    echo 'qvCORE repair skipped. Run "omarchy qvcore repair" later.'
  fi
}

disable_integrations() {
  local options=()
  local tracked_components=()
  local component
  local selection

  for component in "${lifecycle_components[@]}"; do
    if component_is_tracked "$component"; then
      tracked_components+=("$component")
      options+=(
        "${component_icons[$component]}  ${component_names[$component]}:$component"
      )
    fi
  done

  if ((${#tracked_components[@]} == 0)); then
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
      "Disable all ${#tracked_components[@]} enabled qvCORE integration(s)?" ||
      return 130
  else
    gum confirm "Disable the qvCORE ${component_names[$selection]} integration?" ||
      return 130
    tracked_components=("$selection")
  fi

  for component in "${tracked_components[@]}"; do
    "$component_dir/$component.sh" --disable
  done

  echo ""
  echo "Installed applications, authentication, network choices, and personal data were preserved."
}

# Entry point

if (($# > 2)) ||
  [[ -n $target_component && $mode != "repair" ]]; then
  echo "Usage: health.sh [status|repair [component]|repair-enabled|disable|update|enabled-count]" >&2
  exit 2
fi

case $mode in
status)
  status_catalog
  ;;
repair)
  repair_catalog_interactive
  ;;
repair-enabled)
  repair_enabled_components_automatic
  ;;
disable)
  disable_integrations
  ;;
update)
  update_enabled_components
  ;;
enabled-count)
  print_enabled_count
  ;;
*)
  echo "Usage: health.sh [status|repair [component]|repair-enabled|disable|update|enabled-count]" >&2
  exit 2
  ;;
esac
