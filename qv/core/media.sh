#!/bin/bash
set -Eeuo pipefail

failure_context="preflight"
changes_started=0
current_step=0
ready_count=0
missing_count=0

# Component registry

component_ids=(
  gimp
  inkscape
  krita
  kdenlive
  obs-studio
  audacity
  blender
)
total_components=${#component_ids[@]}

declare -A component_names=(
  [gimp]="GIMP"
  [inkscape]="Inkscape"
  [krita]="Krita"
  [kdenlive]="Kdenlive"
  ["obs-studio"]="OBS Studio"
  [audacity]="Audacity"
  [blender]="Blender"
)
declare -A component_descriptions=(
  [gimp]="Raster image editing"
  [inkscape]="Vector graphics"
  [krita]="Digital painting"
  [kdenlive]="Video editing"
  ["obs-studio"]="Recording and streaming"
  [audacity]="Audio editing"
  [blender]="3D creation"
)
declare -A component_state=()

# Inventory and status

inventory_components() {
  local id

  ready_count=0
  missing_count=0

  for id in "${component_ids[@]}"; do
    if omarchy-pkg-present "$id"; then
      component_state[$id]="ready"
      ready_count=$((ready_count + 1))
    else
      component_state[$id]="missing"
      missing_count=$((missing_count + 1))
    fi
  done
}

print_inventory() {
  local id

  echo ""
  echo "qvCORE Media inventory: $ready_count/$total_components ready"
  echo "  Missing: $missing_count"
  echo ""
  for id in "${component_ids[@]}"; do
    printf '  %-12s %s\n' \
      "${component_names[$id]}" \
      "${component_state[$id]}"
  done
}

if (($# > 1)); then
  echo "Usage: media.sh [--status]" >&2
  exit 2
fi

case ${1:-} in
"") ;;
--status)
  inventory_components
  print_inventory
  ((ready_count > 0))
  exit
  ;;
--state)
  inventory_components
  if ((ready_count == total_components)); then
    echo "ready"
  elif ((ready_count > 0)); then
    echo "partial"
  else
    echo "not-installed"
  fi
  exit
  ;;
*)
  echo "Usage: media.sh [--status]" >&2
  exit 2
  ;;
esac

# Interactive installation

report_failure() {
  local status=$?
  local failed_command=$BASH_COMMAND

  trap - ERR INT TERM
  echo ""
  echo "qvCORE Media stopped during $failure_context." >&2
  echo "Command failed with exit $status: $failed_command" >&2
  if ((changes_started)); then
    echo "Completed application installs and Pacman downloads were preserved." >&2
  else
    echo "No package changes were started." >&2
  fi
  echo "Run Media again; ready applications will be kept and missing ones can resume." >&2

  inventory_components
  print_inventory >&2
  exit "$status"
}
trap report_failure ERR

report_interrupt() {
  local signal=$1
  local status=130

  [[ $signal == "TERM" ]] && status=143
  trap - ERR INT TERM
  echo ""
  echo "qvCORE Media was interrupted during $failure_context." >&2
  if ((changes_started)); then
    echo "Completed application installs and Pacman downloads were preserved." >&2
  else
    echo "No package changes were started." >&2
  fi
  echo "Run Media again; ready applications will be kept and missing ones can resume." >&2

  inventory_components
  print_inventory >&2
  exit "$status"
}
trap 'report_interrupt INT' INT
trap 'report_interrupt TERM' TERM

inventory_components
print_inventory

media_options=()
for id in "${component_ids[@]}"; do
  media_options+=(
    "${component_names[$id]} — ${component_descriptions[$id]} [${component_state[$id]}]:$id"
  )
done

failure_context="application selection"
if selections=$(gum choose \
  --no-limit \
  --height 10 \
  --label-delimiter ":" \
  --header "Space: select • Enter: install • Esc: cancel" \
  "${media_options[@]}"); then
  :
else
  status=$?
  echo "qvCORE Media selection canceled; no package changes were started."
  exit "$status"
fi

selected_components=()
declare -A selected_component=()
while IFS= read -r selection; do
  [[ -n $selection ]] || continue

  if [[ -z ${component_names[$selection]+known} ]]; then
    echo "Unknown qvCORE Media selection: $selection" >&2
    exit 1
  fi

  if [[ -z ${selected_component[$selection]+selected} ]]; then
    selected_components+=("$selection")
    selected_component[$selection]=1
  fi
done <<<"$selections"

selected_count=${#selected_components[@]}
if ((selected_count == 0)); then
  echo "No qvCORE Media applications selected; nothing was installed."
  exit 0
fi

pending_count=0
for id in "${selected_components[@]}"; do
  if omarchy-pkg-missing "$id"; then
    pending_count=$((pending_count + 1))
  fi
done

if ((pending_count > 0)); then
  failure_context="package authorization"
  echo ""
  echo "Authorizing $pending_count missing qvCORE Media application(s)..."
  echo "Pacman will reuse cached packages and resumable partial downloads."
  sudo -v
fi

echo ""
echo "Applying qvCORE Media selection..."
for id in "${selected_components[@]}"; do
  current_step=$((current_step + 1))

  if omarchy-pkg-present "$id"; then
    printf '[%d/%d] %s is already ready; keeping it.\n' \
      "$current_step" "$selected_count" "${component_names[$id]}"
    continue
  fi

  changes_started=1
  failure_context="${component_names[$id]} installation"
  printf '[%d/%d] Installing %s...\n' \
    "$current_step" "$selected_count" "${component_names[$id]}"
  omarchy-pkg-add "$id"

  failure_context="${component_names[$id]} verification"
  if ! omarchy-pkg-present "$id"; then
    echo "${component_names[$id]} verification failed after installation." >&2
    false
  fi
  echo "${component_names[$id]} is ready."
done

failure_context="final verification"
inventory_components
print_inventory

selected_ready_count=0
for id in "${selected_components[@]}"; do
  if [[ ${component_state[$id]} == "ready" ]]; then
    selected_ready_count=$((selected_ready_count + 1))
  fi
done

if ((selected_ready_count != selected_count)); then
  echo "qvCORE Media selection is incomplete." >&2
  false
fi

echo ""
echo "qvCORE Media selection is ready: $selected_ready_count/$selected_count selected."
