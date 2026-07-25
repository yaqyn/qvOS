#!/bin/bash
set -euo pipefail

component_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
thunar_config="$HOME/.config/Thunar/uca.xml"
thunar_share_source="$component_dir/../thunar/share"
thunar_share_runtime="$HOME/.local/share/qvos/thunar/share"
thunar_share_command="/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/share\" \"\$@\"' qvos-thunar %F"
thunar_config_temp=""

package_ready=0
helper_ready=0
integration_ready=0

cleanup() {
  if [[ -n $thunar_config_temp && -f $thunar_config_temp ]]; then
    rm -f "$thunar_config_temp"
  fi
}
trap cleanup EXIT

thunar_integration_ready() {
  local action="/actions/action[unique-id='qvos-localsend-share']"
  local state

  [[ -f $thunar_config ]] || return 1

  state=$(
    xmlstarlet sel -t \
      -v "count($action)" -o "|" \
      -v "normalize-space($action/icon)" -o "|" \
      -v "normalize-space($action/name)" -o "|" \
      -v "count($action/submenu)" -o "|" \
      -v "normalize-space($action/command)" -o "|" \
      -v "normalize-space($action/description)" -o "|" \
      -v "normalize-space($action/patterns)" -o "|" \
      -v "count($action/*[
        self::directories or
        self::audio-files or
        self::image-files or
        self::other-files or
        self::text-files or
        self::video-files
      ])" \
      "$thunar_config" 2>/dev/null
  ) || return 1

  [[ $state == "1|localsend|Send via LocalSend|0|$thunar_share_command|Send the selected files and folders to nearby devices.|*|6" ]]
}

inventory_components() {
  package_ready=0
  helper_ready=0
  integration_ready=0

  omarchy-pkg-present localsend && package_ready=1
  [[ -x $thunar_share_runtime ]] &&
    cmp -s "$thunar_share_source" "$thunar_share_runtime" &&
    helper_ready=1
  thunar_integration_ready && integration_ready=1

  return 0
}

status_label() {
  local state=$1

  if ((state)); then
    printf 'ready\n'
  else
    printf 'missing\n'
  fi
}

print_inventory() {
  local ready_count=$((package_ready + helper_ready + integration_ready))

  echo ""
  echo "qvCORE Share inventory: $ready_count/3 ready"
  printf '  %-20s %s\n' "LocalSend" "$(status_label "$package_ready")"
  printf '  %-20s %s\n' "Thunar helper" "$(status_label "$helper_ready")"
  printf '  %-20s %s\n' "Thunar integration" \
    "$(status_label "$integration_ready")"
}

if omarchy-cmd-missing omarchy-menu-share; then
  echo "qvCORE Share requires the qvOS command: omarchy-menu-share" >&2
  exit 1
fi

if omarchy-cmd-missing xmlstarlet; then
  echo "qvCORE Share requires the qvOS base command: xmlstarlet" >&2
  exit 1
fi

if [[ ! -x $thunar_share_source ]]; then
  echo "qvCORE Share requires the qvOS Thunar helper: $thunar_share_source" >&2
  exit 1
fi

install_thunar_helper() {
  install -d "$HOME/.local/share/qvos/thunar"
  install -m 0755 "$thunar_share_source" "$thunar_share_runtime"
}

install_thunar_integration() {
  local action="/actions/action[unique-id='qvos-localsend-share']"
  local thunar_config_backup=""
  local thunar_config_existed=0

  install -d -m 0700 "$(dirname -- "$thunar_config")"
  if [[ -f $thunar_config ]]; then
    thunar_config_existed=1
  else
    install -m 0600 /dev/stdin "$thunar_config" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<actions/>
XML
  fi

  thunar_config_temp=$(mktemp)
  xmlstarlet ed \
    -d "$action" \
    -s "/actions" -t elem -n action -v "" \
    -s "/actions/action[last()]" -t elem -n icon -v "localsend" \
    -s "/actions/action[last()]" -t elem -n name -v "Send via LocalSend" \
    -s "/actions/action[last()]" -t elem -n unique-id \
    -v "qvos-localsend-share" \
    -s "/actions/action[last()]" -t elem -n command \
    -v "$thunar_share_command" \
    -s "/actions/action[last()]" -t elem -n description \
    -v "Send the selected files and folders to nearby devices." \
    -s "/actions/action[last()]" -t elem -n range -v "" \
    -s "/actions/action[last()]" -t elem -n patterns -v "*" \
    -s "/actions/action[last()]" -t elem -n directories -v "" \
    -s "/actions/action[last()]" -t elem -n audio-files -v "" \
    -s "/actions/action[last()]" -t elem -n image-files -v "" \
    -s "/actions/action[last()]" -t elem -n other-files -v "" \
    -s "/actions/action[last()]" -t elem -n text-files -v "" \
    -s "/actions/action[last()]" -t elem -n video-files -v "" \
    "$thunar_config" >"$thunar_config_temp"
  xmlstarlet val -e "$thunar_config_temp" >/dev/null

  if ((thunar_config_existed)); then
    thunar_config_backup="$thunar_config.bak.$(date +%s)"
    cp --preserve=mode,timestamps "$thunar_config" "$thunar_config_backup"
  fi
  install -m 0600 "$thunar_config_temp" "$thunar_config"
  rm -f "$thunar_config_temp"
  thunar_config_temp=""

  if [[ -n $thunar_config_backup ]]; then
    echo "Backed up the previous Thunar actions to $thunar_config_backup"
  fi
}

inventory_components
print_inventory

if ((package_ready == 0)); then
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

inventory_components
print_inventory

if ((package_ready == 0 || helper_ready == 0 || integration_ready == 0)); then
  echo "qvCORE Share is incomplete." >&2
  exit 1
fi

echo ""
echo "qvCORE Share is ready: 3/3."
