#!/bin/bash

# Preservation-safe management for qvOS-owned Thunar custom actions.

qvos_thunar_config="${QVOS_THUNAR_CONFIG:-$HOME/.config/Thunar/uca.xml}"

# Configuration safety

qvos_thunar_require_valid_config() {
  if [[ ! -f $qvos_thunar_config ]]; then
    return 0
  fi

  if ! xmlstarlet val -e "$qvos_thunar_config" >/dev/null 2>&1; then
    echo "Refusing to change malformed Thunar actions: $qvos_thunar_config" >&2
    return 1
  fi
}

qvos_thunar_action_matches() {
  local id=$1
  local icon=$2
  local name=$3
  local command=$4
  local description=$5
  local patterns=$6
  shift 6
  local action="/actions/action[unique-id='$id']"
  local selected_types=("$@")
  local all_type_predicate="self::directories or self::audio-files or self::image-files or self::other-files or self::text-files or self::video-files"
  local type
  local type_predicate=""
  local state

  [[ -f $qvos_thunar_config ]] || return 1
  ((${#selected_types[@]} > 0)) || return 1

  for type in "${selected_types[@]}"; do
    if [[ -n $type_predicate ]]; then
      type_predicate+=" or "
    fi
    type_predicate+="self::$type"
  done

  state=$(
    xmlstarlet sel -t \
      -v "count($action)" -o "|" \
      -v "normalize-space($action/icon)" -o "|" \
      -v "normalize-space($action/name)" -o "|" \
      -v "count($action/submenu)" -o "|" \
      -v "normalize-space($action/command)" -o "|" \
      -v "normalize-space($action/description)" -o "|" \
      -v "normalize-space($action/patterns)" -o "|" \
      -v "count($action/*[$type_predicate])" -o "|" \
      -v "count($action/*[$all_type_predicate])" \
      "$qvos_thunar_config" 2>/dev/null
  ) || return 1

  [[ $state == "1|$icon|$name|0|$command|$description|$patterns|${#selected_types[@]}|${#selected_types[@]}" ]] ||
    return 1

  for type in "${selected_types[@]}"; do
    [[ $(xmlstarlet sel -t -v "count($action/$type)" "$qvos_thunar_config") == "1" ]] ||
      return 1
  done
}

qvos_thunar_backup_config() {
  local backup

  backup="$qvos_thunar_config.bak.$(date +%s%N)"

  cp --preserve=mode,timestamps "$qvos_thunar_config" "$backup"
}

# qvOS-owned action lifecycle

qvos_thunar_ensure_action() {
  local id=$1
  local icon=$2
  local name=$3
  local command=$4
  local description=$5
  local patterns=$6
  shift 6
  local selected_types=("$@")
  local action="/actions/action[unique-id='$id']"
  local config_existed=0
  local temporary
  local type
  local edit_args=(
    -d "$action"
    -s "/actions" -t elem -n action -v ""
    -s "/actions/action[last()]" -t elem -n icon -v "$icon"
    -s "/actions/action[last()]" -t elem -n name -v "$name"
    -s "/actions/action[last()]" -t elem -n unique-id -v "$id"
    -s "/actions/action[last()]" -t elem -n command -v "$command"
    -s "/actions/action[last()]" -t elem -n description -v "$description"
    -s "/actions/action[last()]" -t elem -n range -v ""
    -s "/actions/action[last()]" -t elem -n patterns -v "$patterns"
  )

  qvos_thunar_require_valid_config || return 1
  qvos_thunar_action_matches \
    "$id" "$icon" "$name" "$command" "$description" "$patterns" \
    "${selected_types[@]}" &&
    return 0

  install -d -m 0700 "$(dirname -- "$qvos_thunar_config")"
  if [[ -f $qvos_thunar_config ]]; then
    config_existed=1
  else
    install -m 0600 /dev/stdin "$qvos_thunar_config" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<actions/>
XML
  fi

  for type in "${selected_types[@]}"; do
    edit_args+=(
      -s "/actions/action[last()]" -t elem -n "$type" -v ""
    )
  done

  temporary=$(mktemp "$(dirname -- "$qvos_thunar_config")/.uca.xml.XXXXXX")
  if ! xmlstarlet ed "${edit_args[@]}" "$qvos_thunar_config" >"$temporary" ||
    ! xmlstarlet val -e "$temporary" >/dev/null; then
    rm -f "$temporary"
    return 1
  fi

  if ((config_existed)); then
    qvos_thunar_backup_config
  fi
  install -m 0600 "$temporary" "$qvos_thunar_config"
  rm -f "$temporary"
}

qvos_thunar_remove_action() {
  local id=$1
  local action="/actions/action[unique-id='$id']"
  local temporary

  qvos_thunar_require_valid_config || return 1
  [[ -f $qvos_thunar_config ]] || return 0
  [[ $(xmlstarlet sel -t -v "count($action)" "$qvos_thunar_config") != "0" ]] ||
    return 0

  temporary=$(mktemp "$(dirname -- "$qvos_thunar_config")/.uca.xml.XXXXXX")
  if ! xmlstarlet ed -d "$action" "$qvos_thunar_config" >"$temporary" ||
    ! xmlstarlet val -e "$temporary" >/dev/null; then
    rm -f "$temporary"
    return 1
  fi

  qvos_thunar_backup_config
  install -m 0600 "$temporary" "$qvos_thunar_config"
  rm -f "$temporary"
}
