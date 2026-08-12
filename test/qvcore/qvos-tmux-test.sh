#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
command_path="$root/qvcore/tmux/qvos-tmux"
test_root="$(mktemp -d)"

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export TMUX_TMPDIR="$test_root/tmux-sockets"
unset TMUX

config_dir="$XDG_CONFIG_HOME/qvos/tmux"
recipes_file="$config_dir/sessions.json"
last_file="$XDG_STATE_HOME/qvos/tmux/last-session"
project_dir="$test_root/project"
launch_log="$test_root/launches"

cleanup() {
  tmux kill-server 2>/dev/null || true
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

for frontend in qv omarchy; do
  adapter="$root/bin/$frontend-refresh-tmux"
  [[ -x $adapter ]] || fail "$frontend refresh adapter mode"
  # shellcheck disable=SC2016
  grep -Fqx \
    'exec "$QVOS_PATH/qvcore/tmux/refresh" "$@"' \
    "$adapter" || fail "$frontend refresh adapter owner"
done
rg -q '^# qv:summary=' "$root/bin/qv-refresh-tmux" ||
  fail "native refresh adapter metadata"
if rg -q '^# (qv|omarchy):' "$root/bin/omarchy-refresh-tmux"; then
  fail "compatibility refresh adapter metadata"
fi
[[ $(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
  "$root/qvcore/tmux/native-paths") == "bin/omarchy-refresh-tmux" ]] ||
  fail "Tmux native path inventory"
# shellcheck disable=SC2016
grep -Fq 'Tmux session and configuration lifecycle: `qvcore/tmux/AGENTS.md`' \
  "$root/AGENTS.md" || fail "Tmux workflow route"

refresh_home="$test_root/refresh-home"
refresh_source="$test_root/refresh-source"
refresh_log="$test_root/refresh-log"
install -D -m 0644 "$root/qvcore/config/files/tmux/tmux.conf" \
  "$refresh_source/qvcore/config/files/tmux/tmux.conf"
install -D -m 0755 "$root/qvcore/config/refresh" \
  "$refresh_source/qvcore/config/refresh"
install -D -m 0755 "$root/qvcore/tmux/refresh" \
  "$refresh_source/qvcore/tmux/refresh"
install -D -m 0755 /dev/stdin \
  "$refresh_source/qvcore/desktop/restart/tmux" <<'RESTART'
#!/bin/bash
printf 'reload\n' >>"$QVOS_TEST_REFRESH_LOG"
RESTART
install -D -m 0644 /dev/stdin \
  "$refresh_home/.config/tmux/tmux.conf" <<'CONFIG'
personal tmux config
CONFIG
HOME="$refresh_home" \
  QVOS_PATH="$refresh_source" \
  QVOS_TEST_REFRESH_LOG="$refresh_log" \
  "$refresh_source/qvcore/tmux/refresh"
cmp -s "$root/qvcore/config/files/tmux/tmux.conf" \
  "$refresh_home/.config/tmux/tmux.conf" || fail "Tmux config refresh"
grep -Fqx 'reload' "$refresh_log" || fail "Tmux reload after refresh"
refresh_backup_root="$refresh_home/.local/state/qvos/config-backups/refresh"
mapfile -t refresh_backups < <(
  for path_file in "$refresh_backup_root"/*/path; do
    [[ -f $path_file ]] || continue
    [[ $(<"$path_file") == "tmux/tmux.conf" ]] || continue
    printf '%s/value\n' "${path_file%/path}"
  done
)
((${#refresh_backups[@]} == 1)) || fail "one private Tmux config backup"
refresh_backup=${refresh_backups[0]}
[[ $(<"$refresh_backup") == "personal tmux config" ]] ||
  fail "Tmux config backup"
if compgen -G "$refresh_home/.config/tmux/*.bak.*" >/dev/null; then
  fail "Tmux backup polluted active configuration"
fi
if HOME="$refresh_home" QVOS_PATH="$refresh_source" \
  "$refresh_source/qvcore/tmux/refresh" unexpected >/dev/null 2>&1; then
  fail "Tmux refresh accepted unexpected arguments"
fi
[[ $(wc -l <"$refresh_log") == "1" ]] ||
  fail "invalid Tmux refresh reloaded the server"
pass "Tmux refresh is native, backed up, strict, and reload-aware"

line_count() {
  if [[ -f $launch_log ]]; then
    wc -l <"$launch_log"
  else
    printf '0\n'
  fi
}

wait_for_lines() {
  local expected="$1"

  for _ in {1..100}; do
    (("$(line_count)" >= expected)) && return 0
    sleep 0.05
  done
  return 1
}

wait_for_command() {
  local pane="$1"
  local expected="$2"

  for _ in {1..100}; do
    [[ "$(tmux display-message -p -t "$pane" '#{pane_current_command}')" == "$expected" ]] && return 0
    sleep 0.05
  done
  return 1
}

install -d "$config_dir" "$TMUX_TMPDIR" "$project_dir/dev" "$project_dir/right" "$project_dir/ops"

# shellcheck disable=SC1090,SC1091
source "$command_path"
PATH="$test_root/stale:$HOME/.local/bin:/usr/bin"
reconcile_tmux_path
[[ ${PATH%%:*} == "$HOME/.local/bin" ]] ||
  fail "manager process PATH canonicalization"
[[ $(awk -F: -v local_bin="$HOME/.local/bin" '
  {
    count = 0
    for (field_index = 1; field_index <= NF; field_index++) {
      if ($field_index == local_bin) {
        count++
      }
    }
    print count
  }
' <<<"$PATH") == "1" ]] ||
  fail "manager process PATH deduplication"
tmux new-session -d -s PathTest
tmux set-environment -g PATH "$test_root/stale:$HOME/.local/bin:/usr/bin"
reconcile_tmux_path
server_path="$(tmux show-environment -g PATH)"
[[ ${server_path#PATH=} == "$HOME/.local/bin:$test_root/stale:/usr/bin" ]] ||
  fail "tmux server PATH canonicalization"
tmux kill-server
pass "manager and tmux server prefer the canonical local bin"

clear_last_session
pass "missing last-session state clears cleanly"

set +e
"$command_path" save Unsafe >/dev/null 2>&1
save_status=$?
set -e
((save_status == 2)) || fail "unreviewed public save command is accepted"
pass "layouts can only be saved through the reviewed manager flow"

ui_width=0
ui_left=0
ui_top=0
ui_columns=0
TERM=xterm-256color ui_layout 22
((ui_width > 0 && ui_left >= 0 && ui_top >= 1)) || fail "TUI layout calculation"
((ui_columns - (2 * (ui_left + 2)) == ui_width - 4)) || fail "TUI editor width calculation"
pass "TUI centering calculation succeeds under strict mode"

temporary_bin="$test_root/node_modules/.bin"
install -d "$temporary_bin"
ln -s /bin/sleep "$temporary_bin/codex"
"$temporary_bin/codex" 30 &
temporary_command_pid=$!
temporary_executable=""
for _ in {1..100}; do
  temporary_executable="$(tr '\0' '\n' 2>/dev/null <"/proc/$temporary_command_pid/cmdline" | head -n 1 || true)"
  [[ $temporary_executable == "$temporary_bin/codex" ]] && break
  sleep 0.01
done
[[ $temporary_executable == "$temporary_bin/codex" ]] || fail "temporary package executable startup"
detected_command="$(process_command_line "$temporary_command_pid")"
kill "$temporary_command_pid"
wait "$temporary_command_pid" 2>/dev/null || true
[[ $detected_command == "codex 30" ]] || fail "temporary package executable cleanup"
pass "temporary package paths display as reusable commands"

vanished_process_stderr="$test_root/vanished-process.stderr"
process_command_line 99999999 2>"$vanished_process_stderr" >/dev/null
[[ ! -s $vanished_process_stderr ]] || fail "vanished process emitted a procfs error"
pass "vanished foreground processes degrade without procfs diagnostics"

rm "$temporary_bin/codex"
install -m 0644 /dev/stdin "$temporary_bin/codex" <<'SCRIPT'
setTimeout(() => {}, 30000)
SCRIPT
node "$temporary_bin/codex" --yolo &
temporary_command_pid=$!
for _ in {1..100}; do
  if tr '\0' '\n' 2>/dev/null <"/proc/$temporary_command_pid/cmdline" |
    grep -Fqx "$temporary_bin/codex"; then
    break
  fi
  sleep 0.01
done
detected_command="$(process_command_line "$temporary_command_pid")"
kill "$temporary_command_pid"
wait "$temporary_command_pid" 2>/dev/null || true
[[ $detected_command == "codex --yolo" ]] ||
  fail "npm Codex process capture normalization"
pass "npm Codex process paths save as the canonical command"

codex_command="node /tmp/node_modules/.bin/codex --yolo"
protected_command="$(protect_startup_command "$codex_command")"
[[ $protected_command == *".local/lib/qvos/bin/qv-system-inhibit-sleep"* &&
  $protected_command == *"Codex"* &&
  $protected_command != *"node /tmp/node_modules"* ]] ||
  fail "Codex startup sleep protection"
[[ "$(protect_startup_command "bun run dev")" == "bun run dev" ]] ||
  fail "non-Codex startup command preservation"

protected_log="$test_root/protected-command"
install -d "$HOME/.local/bin" "$HOME/.local/lib/qvos/bin" "$test_root/test-bin"
install -m 0755 /dev/stdin "$HOME/.local/lib/qvos/bin/qv-system-inhibit-sleep" <<'SCRIPT'
#!/bin/bash
printf 'reason=%s\n' "$QVOS_SLEEP_INHIBIT_REASON" >>"$QVOS_TEST_PROTECTED_LOG"
exec "$@"
SCRIPT
install -m 0755 /dev/stdin "$HOME/.local/bin/codex" <<'SCRIPT'
#!/bin/bash
[[ -z ${CODEX_MANAGED_PACKAGE_ROOT+x} &&
  -z ${CODEX_MANAGED_BY_NPM+x} ]] ||
  exit 91
printf 'canonical-codex' >>"$QVOS_TEST_PROTECTED_LOG"
printf ' %q' "$@" >>"$QVOS_TEST_PROTECTED_LOG"
printf '\n' >>"$QVOS_TEST_PROTECTED_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_root/test-bin/codex" <<'SCRIPT'
#!/bin/bash
printf 'stale-codex\n' >>"$QVOS_TEST_PROTECTED_LOG"
exit 92
SCRIPT
protected_command="$(protect_startup_command "codex --message 'two words'")"
QVOS_TEST_PROTECTED_LOG="$protected_log" \
  CODEX_MANAGED_PACKAGE_ROOT=/tmp/npm-codex \
  CODEX_MANAGED_BY_NPM=1 \
  PATH="$test_root/test-bin:/usr/bin" \
  /bin/bash -c "$protected_command"
grep -Fqx 'reason=Codex session is active' "$protected_log" ||
  fail "Codex startup inhibitor reason"
grep -Fqx 'canonical-codex --message two\ words' "$protected_log" ||
  fail "Codex startup command preservation"
if grep -Fq 'stale-codex' "$protected_log"; then
  fail "Codex startup resolved the stale tmux PATH"
fi
pass "Codex startup uses the canonical CLI with focused sleep protection"

tile_log="$test_root/tile-dispatch"
tile_bin="$test_root/tile-bin"
install -d "$tile_bin"
install -m 0755 /dev/stdin "$tile_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_TILE_LOG"
case ${1:-} in
-j)
  [[ ${2:-} == "activewindow" ]]
  printf '{"class":"org.qvos.tmux-manager"}\n'
  ;;
dispatch)
  [[ ${QVOS_TEST_TILE_FAIL:-false} != "true" ]]
  ;;
*) exit 64 ;;
esac
SCRIPT
QVOS_TEST_TILE_LOG="$tile_log" \
  HYPRLAND_INSTANCE_SIGNATURE="test" \
  PATH="$tile_bin:/usr/bin" \
  tile_manager_terminal
grep -Fqx -- '-j activewindow' "$tile_log" ||
  fail "manager terminal class query"
grep -Fqx -- 'dispatch hl.dsp.window.float({ action = "disable" })' \
  "$tile_log" || fail "manager terminal tiling"
: >"$tile_log"
QVOS_TEST_TILE_FAIL=true \
  QVOS_TEST_TILE_LOG="$tile_log" \
  HYPRLAND_INSTANCE_SIGNATURE="test" \
  PATH="$tile_bin:/usr/bin" \
  tile_manager_terminal 2>/dev/null ||
  fail "secondary tiling failure closed the manager terminal"
pass "opening a session tiles through the native bridge without blocking tmux"

jq -n --arg cwd "$project_dir" '
  {
    version: 1,
    sessions: [{
      name: "Legacy",
      cwd: $cwd,
      windows: [{name: "shell", cwd: ".", command: ""}]
    }]
  }
' >"$recipes_file"
"$command_path" ensure Legacy
jq -e '
  .version == 2 and
  .sessions[0].active_window == 0 and
  .sessions[0].windows[0] == {
    name: "shell",
    layout: "",
    zoomed: false,
    active_pane: 0,
    panes: [{cwd: ".", command: ""}]
  }
' "$recipes_file" >/dev/null || fail "version 1 recipe migration"
pass "version 1 recipes migrate once to pane layouts"
"$command_path" delete Legacy

"$command_path" new Detect "$project_dir"
detect_pane="$(tmux list-panes -t =Detect -F '#{pane_id}')"
tmux send-keys -t "$detect_pane" -l -- "sleep 30"
tmux send-keys -t "$detect_pane" Enter
wait_for_command "$detect_pane" sleep || fail "foreground command starts"
detected_recipe="$(capture_session_recipe Detect)"
detected_command="$(jq -r '.windows[0].panes[0].command' <<<"$detected_recipe")"
[[ $detected_command == *sleep* && $detected_command == *30* ]] || fail "foreground command detection"
pass "manager capture detects the foreground command for review"
"$command_path" stop Detect

"$command_path" new Custom "$project_dir"
initial_window="$(tmux list-windows -t =Custom -F '#{window_id}')"
tmux rename-window -t "$initial_window" editor
editor_left="$(tmux display-message -p -t =Custom:editor '#{pane_id}')"
editor_right="$(tmux split-window -h -p 35 -P -F '#{pane_id}' -t "$editor_left" -c "$project_dir/right")"
tmux split-window -v -p 40 -t "$editor_right" -c "$project_dir/dev"
services_record="$(tmux new-window -d -P -F $'#{window_id}\t#{pane_id}' -t =Custom -n services -c "$project_dir/dev")"
IFS=$'\t' read -r services_window services_top <<<"$services_record"
services_bottom="$(tmux split-window -v -p 30 -P -F '#{pane_id}' -t "$services_top" -c "$project_dir/ops")"

tmux select-window -t "$services_window"
tmux select-pane -t "$services_bottom"
tmux resize-pane -Z -t "$services_bottom"

original_editor_geometry="$(tmux list-panes -t =Custom:editor -F '#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | paste -sd ';' -)"
original_editor_layout="$(tmux display-message -p -t =Custom:editor '#{window_layout}')"

printf -v quoted_log '%q' "$launch_log"
mapfile -t custom_panes < <(tmux list-panes -s -t =Custom -F '#{pane_id}')
for pane_index in "${!custom_panes[@]}"; do
  pane_number="$((pane_index + 1))"
  pane_command="printf 'pane-$pane_number\\n' >> $quoted_log"
  tmux set-option -p -t "${custom_panes[$pane_index]}" @qvos-command "$pane_command"
done

custom_recipe="$(capture_session_recipe Custom)"
save_running_recipe Custom "$custom_recipe"
jq -e '
  .version == 2 and
  (.sessions | length == 1) and
  .sessions[0].name == "Custom" and
  .sessions[0].active_window == 1 and
  (.sessions[0].windows | length == 2) and
  .sessions[0].windows[0].name == "editor" and
  (.sessions[0].windows[0].panes | length == 3) and
  .sessions[0].windows[1].name == "services" and
  (.sessions[0].windows[1].panes | length == 2) and
  .sessions[0].windows[1].active_pane == 1 and
  .sessions[0].windows[1].zoomed == true and
  all(.sessions[0].windows[].panes[]; .command != "")
' "$recipes_file" >/dev/null || fail "custom layout capture"
[[ "$(jq -r '.sessions[0].windows[0].layout' "$recipes_file")" == "$original_editor_layout" ]] || fail "exact layout capture"
pass "save captures arbitrary windows, panes, sizes, focus, and zoom"

[[ "$(line_count)" == "0" ]] || fail "save executes startup commands"
"$command_path" ensure Custom
[[ "$(line_count)" == "0" ]] || fail "existing session reruns startup commands"
pass "save and existing-session open do not rerun commands"

recipe="$(jq -c '.sessions[0]' "$recipes_file")"
command_sheet=$'1.1 | codex --yolo | tee /tmp/codex.log\n1.2 | nvim .\n1.3 | bun run dev\n2.1 | lazygit\n2.2 | '
reviewed_recipe=""
parse_command_sheet "$recipe" "$command_sheet" || fail "command sheet parser"
jq -e '
  .windows[0].panes[0].command == "codex --yolo | tee /tmp/codex.log" and
  .windows[1].panes[1].command == ""
' <<<"$reviewed_recipe" >/dev/null || fail "command sheet values"
pass "startup-command editor preserves pipes and blank panes"

reviewed_recipe="$(jq -c '
  .windows[0].panes[0].command =
    "node /tmp/node_modules/.bin/codex --yolo | tee /tmp/codex.log"
' <<<"$recipe")"
save_running_recipe Custom "$reviewed_recipe"
[[ $(jq -r '.sessions[0].windows[0].panes[0].command' "$recipes_file") == \
  "codex --yolo | tee /tmp/codex.log" ]] ||
  fail "saved npm Codex recipe normalization"
pass "saved recipes cannot retain an ephemeral npm Codex path"
save_running_recipe Custom "$recipe"

"$command_path" stop Custom
"$command_path" ensure Custom
wait_for_lines 5 || fail "fresh startup commands execute"
[[ "$(line_count)" == "5" ]] || fail "fresh startup commands execute once"
restored_editor_geometry="$(tmux list-panes -t =Custom:editor -F '#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | paste -sd ';' -)"
[[ $restored_editor_geometry == "$original_editor_geometry" ]] || fail "exact pane geometry restore"
[[ "$(tmux display-message -p -t =Custom: '#{window_name}')" == "services" ]] || fail "active window restore"
[[ "$(tmux display-message -p -t =Custom:services '#{window_zoomed_flag}')" == "1" ]] || fail "zoomed window restore"
mapfile -t services_active_flags < <(tmux list-panes -t =Custom:services -F '#{pane_active}')
[[ ${services_active_flags[1]} == "1" ]] || fail "active pane restore"
pass "stopped session rebuilds exact geometry and runs commands once"

mapfile -t restored_paths < <(tmux list-panes -s -t =Custom -F '#{pane_current_path}')
[[ ${restored_paths[0]} == "$project_dir" ]] || fail "first pane directory restore"
[[ ${restored_paths[1]} == "$project_dir/right" ]] || fail "second pane directory restore"
[[ ${restored_paths[2]} == "$project_dir/dev" ]] || fail "third pane directory restore"
[[ ${restored_paths[3]} == "$project_dir/dev" ]] || fail "fourth pane directory restore"
[[ ${restored_paths[4]} == "$project_dir/ops" ]] || fail "fifth pane directory restore"
pass "every pane returns to its saved working directory"

"$command_path" ensure Custom
sleep 0.2
[[ "$(line_count)" == "5" ]] || fail "second ensure reruns commands"
pass "running sessions attach without command replay"

printf -v last_command '%q last' "$command_path"
TERM=xterm-256color script -q -c "$last_command" /dev/null >/dev/null &
attached_pid=$!
client_name=""
for _ in {1..100}; do
  client_name="$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -n 1)"
  [[ -n $client_name ]] && break
  sleep 0.05
done
[[ -n $client_name ]] || fail "last command attaches"
tmux detach-client -t "$client_name"
wait "$attached_pid"
[[ "$(line_count)" == "5" ]] || fail "last command reruns startup commands"
pass "last-session shortcut attaches without rerunning commands"

tmux resize-pane -Z -t =Custom:services
tmux select-window -t =Custom:editor
tmux select-layout -t =Custom:editor even-vertical >/dev/null
changed_editor_geometry="$(tmux list-panes -t =Custom:editor -F '#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | paste -sd ';' -)"
[[ $changed_editor_geometry != "$original_editor_geometry" ]] || fail "test layout change"
updated_recipe="$(capture_session_recipe Custom)"
save_running_recipe Custom "$updated_recipe"
"$command_path" stop Custom
"$command_path" ensure Custom
wait_for_lines 10 || fail "resaved layout rebuild"
[[ "$(line_count)" == "10" ]] || fail "resaved layout command count"
[[ "$(tmux list-panes -t =Custom:editor -F '#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | paste -sd ';' -)" == "$changed_editor_geometry" ]] || fail "resaved geometry restore"
[[ "$(tmux display-message -p -t =Custom: '#{window_name}')" == "editor" ]] || fail "resaved active window restore"
pass "save current replaces the old geometry with the new customization"

[[ "$(<"$last_file")" == "Custom" ]] || fail "last session state"
[[ "$(stat -c '%a' "$recipes_file")" == "600" ]] || fail "recipes file permissions"
[[ "$(stat -c '%a' "$last_file")" == "600" ]] || fail "last-session permissions"
pass "saved commands and last-session state remain private"

"$command_path" rename Custom Renamed
tmux has-session -t =Renamed 2>/dev/null || fail "rename running session"
jq -e '.sessions | length == 1 and .[0].name == "Renamed"' "$recipes_file" >/dev/null || fail "rename recipe"
[[ "$(<"$last_file")" == "Renamed" ]] || fail "rename last session"
[[ "$(line_count)" == "10" ]] || fail "rename reruns commands"
pass "rename updates runtime, recipe, and last-session state"

"$command_path" delete Renamed
jq -e '.sessions | length == 0' "$recipes_file" >/dev/null || fail "delete recipe"
[[ ! -f $last_file ]] || fail "delete last session"
tmux has-session -t =Renamed 2>/dev/null && fail "delete running session"
pass "delete removes the saved and running session"

race_command="printf 'race\\n' >> $quoted_log"
temporary="$config_dir/sessions.tmp"
jq -n --arg cwd "$project_dir" --arg command "$race_command" '
  {
    version: 2,
    sessions: [{
      name: "Race",
      cwd: $cwd,
      active_window: 0,
      windows: [{
        name: "shell",
        layout: "",
        zoomed: false,
        active_pane: 0,
        panes: [{cwd: ".", command: $command}]
      }]
    }]
  }
' >"$temporary"
mv "$temporary" "$recipes_file"

"$command_path" ensure Race &
first_pid=$!
"$command_path" ensure Race &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
wait_for_lines 11 || fail "concurrent ensure starts session"
[[ "$(line_count)" == "11" ]] || fail "concurrent ensure reruns command"
[[ "$(tmux list-sessions -F '#S' | rg -cx 'Race')" == "1" ]] || fail "concurrent ensure creates duplicates"
pass "concurrent opens create one session and run once"

set +e
"$command_path" rename Race invalid.name >/dev/null 2>&1
invalid_status=$?
set -e
((invalid_status != 0)) || fail "invalid session name succeeds"
pass "invalid session names are rejected"

"$command_path" delete Race
pass "cleanup command succeeds"
