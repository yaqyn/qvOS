#!/bin/bash
set -euo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-$HOME/.local/share/omarchy}
component_dir="$OMARCHY_PATH/qv/core"
mode="${1:-status}"

lifecycle_components=(
  share
  dev
  codex
  proton
)

declare -A component_names=(
  [share]="Share"
  [dev]="Devel"
  [codex]="Codex"
  [proton]="Proton"
)
declare -A component_icons=(
  [share]=""
  [dev]="󰵮"
  [codex]="󱚤"
  [proton]="󰌾"
)
declare -A issue_action=()
declare -A issue_detail=()
declare -A issue_present=()
enabled_components=()
issues=()
remaining_issues=()

legacy_hook_targets=(
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-share"
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-dev"
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-codex"
  "$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-proton"
)

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

remove_legacy_component_hooks() {
  local hook

  for hook in "${legacy_hook_targets[@]}"; do
    rm -f "$hook"
  done
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

# User-facing operations

status_enabled_components() {
  reset_maintenance_state
  collect_enabled_components
  if ((${#enabled_components[@]} == 0)); then
    print_ready_summary show
    return
  fi

  inspect_enabled_components 0
  if ((${#issues[@]} == 0)); then
    print_ready_summary show
  else
    print_issues
    return 1
  fi
}

repair_enabled_components_interactive() {
  local issue_label="issues"

  reset_maintenance_state
  remove_legacy_component_hooks
  retire_removed_components
  collect_enabled_components
  inspect_enabled_components 0

  if ((${#issues[@]} == 0)); then
    print_ready_summary show
    return
  fi

  print_issues
  ((${#issues[@]} == 1)) && issue_label="issue"
  echo ""
  if ! gum confirm \
    "Repair ${#issues[@]} enabled qvCORE setup $issue_label now?"; then
    echo "qvCORE repair canceled."
    return 130
  fi

  repair_issues || true
  print_repair_result show
}

repair_enabled_components_automatic() {
  reset_maintenance_state
  remove_legacy_component_hooks
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
  remove_legacy_component_hooks
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

case $mode in
status)
  status_enabled_components
  ;;
repair)
  repair_enabled_components_interactive
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
  echo "Usage: health.sh [status|repair|repair-enabled|disable|update|enabled-count]" >&2
  exit 2
  ;;
esac
