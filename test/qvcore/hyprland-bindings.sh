# shellcheck shell=bash

qvos_binding_trim() {
  local value=$1

  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s\n' "$value"
}

# Accept the compact semantic tuple used by the former Hyprland syntax and
# assert its exact typed Lua representation. This keeps binding tests readable
# while making the production source and parser entirely Lua-native.
qvos_assert_lua_binding() {
  local bindings=$1
  local tuple=$2
  local bind_type=${tuple%% = *}
  local fields=${tuple#* = }
  local modifiers
  local key
  local description
  local dispatcher
  local argument
  local keys
  local suffix=""
  local expected

  IFS=',' read -r modifiers key description dispatcher argument <<<"$fields"
  modifiers=$(qvos_binding_trim "$modifiers")
  key=$(qvos_binding_trim "$key")
  description=$(qvos_binding_trim "$description")
  dispatcher=$(qvos_binding_trim "$dispatcher")
  argument=$(qvos_binding_trim "${argument:-}")
  argument=${argument%% \#*}
  if [[ -n $modifiers ]]; then
    keys="${modifiers// / + } + $key"
  else
    keys=$key
  fi
  case $bind_type in
  bindd) ;;
  binddr) suffix=', release = true' ;;
  bindld) suffix=', locked = true' ;;
  bindeld) suffix=', repeating = true, locked = true' ;;
  *) return 2 ;;
  esac
  expected="qv.bind({ keys = [[$keys]], description = [[$description]], dispatcher = [[$dispatcher]]"
  if [[ -n $argument ]]; then
    expected+=", argument = [[$argument]]"
  fi
  expected+="$suffix })"
  grep -Fq -- "$expected" "$bindings"
}
