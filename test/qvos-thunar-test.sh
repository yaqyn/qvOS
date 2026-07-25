#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
actions="$root/config/Thunar/uca.xml"
bindings="$root/config/hypr/qv/bindings.conf"
feature_dir="$root/qv/thunar"
gtk_css="$root/config/gtk-3.0/gtk.css"

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
[[ $(xmlstarlet sel -t -v "count(/actions/action)" "$actions") == "3" ]] ||
  fail "default Thunar action count"
pass "tracked Thunar actions XML is valid and intentionally scoped"

assert_action \
  qvos-terminal-here \
  "Open Terminal Here" \
  "/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/open-here\" terminal \"\$1\"' qvos-thunar %f"
assert_action \
  qvos-editor-here \
  "Open Editor Here" \
  "/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/open-here\" editor \"\$1\"' qvos-thunar %f"
assert_action \
  qvos-set-background \
  "Set as Background" \
  "/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/set-background\" \"\$1\"' qvos-thunar %f"
pass "every default qvOS action is direct in Thunar's custom-action section"

grep -Fqx 'menu separator {' "$gtk_css" ||
  fail "native GTK menu separator selector"
grep -Fqx '  min-height: 1px;' "$gtk_css" ||
  fail "thin GTK menu separator"
grep -Fqx '  background-color: #2a2a2a;' "$gtk_css" ||
  fail "visible GTK menu separator color"
pass "native menu section separators render as thin lines"

expected_features=$'launch\nopen-here\nset-background\nshare'
actual_features="$(find "$feature_dir" -maxdepth 1 -type f -printf '%f\n' | sort)"
[[ $actual_features == "$expected_features" ]] ||
  fail "Thunar feature script inventory"

for feature in launch open-here set-background share; do
  [[ -x $feature_dir/$feature ]] || fail "$feature executable mode"
  [[ $(head -n 1 "$feature_dir/$feature") == "#!/bin/bash" ]] ||
    fail "$feature shebang"
done
pass "Thunar feature scripts are named and executable in one domain"

if find "$root/qv/scripts" -type f \
  \( -iname '*thunar*' -o -name 'qvos-set-background' \) |
  grep -q .; then
  fail "Thunar-owned helper remains outside qv/thunar"
fi
pass "Thunar-owned scripts stay in one source domain"

grep -Fqx "bindd = SUPER, E, Thunar, exec, uwsm-app -- ~/.local/share/qvos/thunar/launch \"\$HOME\"" "$bindings" ||
  fail "home Thunar binding"
grep -Fqx "bindd = SUPER SHIFT, E, Thunar here, exec, uwsm-app -- ~/.local/share/qvos/thunar/launch \"\$(~/.local/share/qvos/hyprland/qvos-active-location)\"" "$bindings" ||
  fail "contextual Thunar binding"
pass "Thunar keybindings use the organized launch feature"
