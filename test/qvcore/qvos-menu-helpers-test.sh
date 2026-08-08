#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
walker_args="$test_root/walker-args"
walker_input="$test_root/walker-input"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home/Pictures" "$test_home/Videos" "$test_bin"
touch -d '2026-01-01 00:00:00' "$test_home/Pictures/older.png"
touch -d '2026-01-02 00:00:00' "$test_home/Videos/new clip.mp4"
touch "$test_home/Pictures/ignored.txt"

install -m 0755 /dev/stdin "$test_bin/qv-launch-walker" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_WALKER_ARGS"
if [[ -t 0 ]]; then
  : >"$QVOS_TEST_WALKER_INPUT"
else
  cat >"$QVOS_TEST_WALKER_INPUT"
fi
case ${QVOS_TEST_WALKER_RESULT:-} in
"") ;;
*) printf '%s\n' "$QVOS_TEST_WALKER_RESULT" ;;
esac
SCRIPT

run_owner() {
  HOME="$test_home" \
    QVOS_TEST_WALKER_ARGS="$walker_args" \
    QVOS_TEST_WALKER_INPUT="$walker_input" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

output=$(QVOS_TEST_WALKER_RESULT='chosen value' run_owner \
  "$root/qvcore/menu/input" 'Safe prompt' --width 420)
[[ $output == "chosen value" ]] || fail "menu input result"
grep -Fxq 'Safe prompt…' "$walker_args" || fail "menu input prompt"

output=$(QVOS_TEST_WALKER_RESULT=png run_owner \
  "$root/qvcore/menu/select" Format jpg png -- --width 420)
[[ $output == "png" ]] || fail "menu select result"
[[ $(<"$walker_input") == $'jpg\npng' ]] || fail "menu select choices"

output=$(QVOS_TEST_WALKER_RESULT="$test_home/Videos/new clip.mp4" run_owner \
  "$root/qvcore/menu/file" 'Media' \
  "$test_home/Pictures:$test_home/Videos" 'png mp4')
[[ $output == "$test_home/Videos/new clip.mp4" ]] || fail "menu file result"
expected_files="$test_home/Videos/new clip.mp4"$'\n'"$test_home/Pictures/older.png"
[[ $(<"$walker_input") == "$expected_files" ]] || fail "menu file filtering"

if run_owner "$root/qvcore/menu/select" Format $'bad\nchoice' >/dev/null 2>&1; then
  fail "control-bearing menu choice"
fi
if run_owner "$root/qvcore/menu/file" Media "$test_home/Pictures" '../png' \
  >/dev/null 2>&1; then
  fail "unsafe menu file format"
fi
printf 'ok - menu input, selection, and file discovery validate exact boundaries\n'

install -m 0755 /dev/stdin "$test_bin/xkbcli" <<'SCRIPT'
#!/bin/bash
cat <<'KEYMAP'
xkb_keycodes {
  <AD01> = 24;
};
xkb_symbols {
  key <AD01> { [ q, Q ] };
};
KEYMAP
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
if [[ $1 == "binds" ]]; then
  printf 'bind\n\tmodmask: 64\n\tkey: \n\tkeycode: 24\n\tdescription: qvOS Menu\n\tdispatcher: exec\n\targ: ~/.local/share/qvos/bin/qv-menu\n'
else
  printf '[{"focused":true,"height":1200}]\n'
fi
SCRIPT
keybindings=$(PATH="$test_bin:/usr/bin" \
  "$root/qvcore/menu/keybindings" --print)
grep -Fq 'SUPER + q' <<<"$keybindings" || fail "keycode mapping"
grep -Fq 'qvOS Menu' <<<"$keybindings" || fail "keybinding description"
if PATH="$test_bin:/usr/bin" "$root/qvcore/menu/keybindings" bad \
  >/dev/null 2>&1; then
  fail "unexpected keybinding arguments"
fi
printf 'ok - keybinding discovery handles native paths and validated modes\n'

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/walker" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@"
SCRIPT
walker_output=$(PATH="$test_bin:/usr/bin" \
  "$root/qvcore/menu/launch-walker" --dmenu --width 500)
[[ $walker_output == $'--width\n644\n--maxheight\n300\n--minheight\n300\n--dmenu\n--width\n500' ]] ||
  fail "Walker exact argument forwarding"
printf 'ok - Walker launcher preserves caller arguments without shell rebuilding\n'
