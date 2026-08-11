#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
actions="$root/qvcore/config/files/Thunar/uca.xml"
bindings="$root/qvcore/config/files/hypr/bindings.lua"
# shellcheck source=test/qvcore/hyprland-bindings.sh
source "$root/test/qvcore/hyprland-bindings.sh"
feature_dir="$root/qvcore/thunar"
gtk_css="$root/qvcore/config/files/gtk-3.0/gtk.css"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_action() {
  local id=$1
  local name=$2
  local command=$3
  local action="/actions/action[unique-id='$id']"

  [[ $(xmlstarlet sel -t -v "count($action)" "$actions") == "1" ]] ||
    fail "$id action count"
  [[ $(xmlstarlet sel -t -v "$action/name" "$actions") == "$name" ]] ||
    fail "$id action name"
  [[ $(xmlstarlet sel -t -v "count($action/submenu)" "$actions") == "0" ]] ||
    fail "$id top-level placement"
  [[ $(xmlstarlet sel -t -v "$action/command" "$actions") == "$command" ]] ||
    fail "$id feature command"
}

xmlstarlet val -e "$actions" >/dev/null ||
  fail "valid Thunar actions XML"
[[ $(xmlstarlet sel -t -v "count(/actions/action)" "$actions") == "5" ]] ||
  fail "default Thunar action count"
pass "tracked Thunar actions XML is valid and intentionally scoped"

assert_action \
  qvos-terminal-here \
  "Open Terminal Here" \
  "/bin/bash -c '\"\$HOME/.local/lib/qvos/thunar/open-here\" terminal \"\$1\"' qvos-thunar %f"
assert_action \
  qvos-editor-here \
  "Open Editor Here" \
  "/bin/bash -c '\"\$HOME/.local/lib/qvos/thunar/open-here\" editor \"\$1\"' qvos-thunar %f"
assert_action \
  qvos-set-background \
  "Set as Background" \
  "/bin/bash -c '\"\$HOME/.local/lib/qvos/thunar/set-background\" \"\$1\"' qvos-thunar %f"
assert_action \
  qvos-transcode \
  "Transcode" \
  "/bin/bash -c '\"\$HOME/.local/lib/qvos/thunar/transcode\" \"\$1\"' qvos-thunar %f"
assert_action \
  qvos-localsend-share \
  "Send via LocalSend" \
  "/bin/bash -c '\"\$HOME/.local/lib/qvos/thunar/share\" \"\$@\"' qvos-thunar %F"
pass "every default qvOS action is direct in Thunar's custom-action section"

grep -Fqx 'menu separator {' "$gtk_css" ||
  fail "native GTK menu separator selector"
grep -Fqx '  min-height: 1px;' "$gtk_css" ||
  fail "thin GTK menu separator"
grep -Fqx '  background-color: #2a2a2a;' "$gtk_css" ||
  fail "visible GTK menu separator color"
pass "native menu section separators render as thin lines"

expected_features=$'AGENTS.md\nactions.sh\ncodex\ninstall\nlaunch\nopen-here\nproton-drive-upload\nreconcile-default-actions\nset-background\nshare\ntranscode'
actual_features="$(find "$feature_dir" -maxdepth 1 -type f -printf '%f\n' | sort)"
[[ $actual_features == "$expected_features" ]] ||
  fail "Thunar feature script inventory"

[[ ! -x $feature_dir/actions.sh ]] || fail "Thunar action library executable mode"
for feature in \
  codex \
  install \
  launch \
  open-here \
  proton-drive-upload \
  reconcile-default-actions \
  set-background \
  share \
  transcode; do
  [[ -x $feature_dir/$feature ]] || fail "$feature executable mode"
  [[ $(head -n 1 "$feature_dir/$feature") == "#!/bin/bash" ]] ||
    fail "$feature shebang"
done
pass "Thunar features and their shared action library stay in one domain"

grep -Fq 'exec /usr/bin/Thunar "$@"' "$feature_dir/launch" ||
  fail "Thunar launcher bypasses its local compatibility link"
if rg -q 'command -v (t|T)hunar|exec (t|T)hunar ' "$feature_dir/launch"; then
  fail "Thunar launcher can recurse through its local compatibility link"
fi
grep -Fq 'ExecStart=%h/.local/lib/qvos/thunar/launch --daemon' \
  "$feature_dir/install" ||
  fail "Thunar D-Bus service override"
pass "Thunar desktop and D-Bus routes converge without launcher recursion"

if find "$root/qvcore" \
  \( -path "$feature_dir" -o -path "$root/qvcore/config" \) -prune -o -type f \
  \( -iname '*thunar*' -o -name 'qvos-set-background' \) -print |
  grep -q .; then
  fail "Thunar-owned helper remains outside qvcore/thunar"
fi
pass "Thunar-owned scripts stay in one source domain"

qvos_assert_lua_binding "$bindings" \
  "bindd = SUPER, E, Thunar, exec, uwsm-app -- ~/.local/lib/qvos/thunar/launch \"\$HOME\"" ||
  fail "home Thunar binding"
qvos_assert_lua_binding "$bindings" \
  "bindd = SUPER CTRL, E, Thunar here, exec, uwsm-app -- ~/.local/lib/qvos/thunar/launch \"\$(~/.local/lib/qvos/desktop/context/qvos-active-location)\"" ||
  fail "contextual Thunar binding"
pass "Thunar keybindings use the organized launch feature"

test_root=$(mktemp -d)
test_bin="$test_root/bin"
argv_log="$test_root/presentation-argv"
cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT
install -d "$test_bin"

foreign_command_home="$test_root/foreign-command-home"
install -d \
  "$foreign_command_home/.local/bin" \
  "$foreign_command_home/.local/lib/qvos/thunar"
install -m 0755 "$feature_dir/launch" \
  "$foreign_command_home/.local/lib/qvos/thunar/launch"
printf 'foreign command\n' >"$foreign_command_home/.local/bin/thunar"
if HOME="$foreign_command_home" "$feature_dir/install" >/dev/null 2>&1; then
  fail "foreign Thunar command accepted"
fi
[[ $(<"$foreign_command_home/.local/bin/thunar") == "foreign command" ]] ||
  fail "foreign Thunar command preservation"

foreign_unit_home="$test_root/foreign-unit-home"
install -d \
  "$foreign_unit_home/.config/systemd/user/thunar.service.d" \
  "$foreign_unit_home/.local/lib/qvos/thunar"
install -m 0755 "$feature_dir/launch" \
  "$foreign_unit_home/.local/lib/qvos/thunar/launch"
printf 'foreign unit\n' \
  >"$foreign_unit_home/.config/systemd/user/thunar.service.d/qvos.conf"
if HOME="$foreign_unit_home" "$feature_dir/install" >/dev/null 2>&1; then
  fail "foreign Thunar unit override accepted"
fi
[[ $(<"$foreign_unit_home/.config/systemd/user/thunar.service.d/qvos.conf") == \
  "foreign unit" && ! -e $foreign_unit_home/.local/bin/thunar ]] ||
  fail "foreign Thunar unit override preservation"
pass "Thunar installation refuses foreign command and service ownership"

install -m 0755 /dev/stdin "$test_bin/qv-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_PRESENTATION_ARGV_LOG"
SCRIPT
media_file="$test_root/recording final.mp4"
printf 'fixture\n' >"$media_file"
QVOS_TEST_PRESENTATION_ARGV_LOG="$argv_log" \
  PATH="$test_bin:/usr/bin" \
  "$feature_dir/transcode" "$media_file"
[[ $(<"$argv_log") == $'qv-transcode\n'"$media_file" ]] ||
  fail "Transcode presentation argument boundaries"
pass "Thunar Transcode preserves selected filenames as exact arguments"

if rg -n 'qv-launch-floating-terminal-with-presentation "\$[^" ]*command"' "$root/qvcore"; then
  fail "qvOS presentation caller passes a collapsed command string"
fi
pass "qvOS presentation callers preserve argv instead of rebuilding shell commands"
