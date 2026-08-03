#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
applications="$test_root/applications"
editor_file="$test_home/.config/uwsm/default"
terminal_file="$test_home/.config/xdg-terminals.list"
browser_state="$test_root/browser-state"
action_log="$test_root/actions"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$applications" "$(dirname -- "$editor_file")"
for command in nvim ghostty; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
done
install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf 'notify:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/xdg-settings" <<'SCRIPT'
#!/bin/bash
case ${1:-}:${2:-} in
get:default-web-browser)
  cat "$QVOS_TEST_BROWSER_STATE"
  ;;
check:default-web-browser)
  if [[ $(<"$QVOS_TEST_BROWSER_STATE") == "$3" ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
  ;;
set:default-web-browser)
  printf 'browser:%s\n' "$3" >>"$QVOS_TEST_ACTION_LOG"
  if [[ ${QVOS_TEST_FAIL_BROWSER:-} == "$3" && ! -e $QVOS_TEST_FAIL_MARKER ]]; then
    printf 'partial.desktop\n' >"$QVOS_TEST_BROWSER_STATE"
    touch "$QVOS_TEST_FAIL_MARKER"
    exit 1
  fi
  printf '%s\n' "$3" >"$QVOS_TEST_BROWSER_STATE"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

touch \
  "$applications/chromium.desktop" \
  "$applications/firefox.desktop" \
  "$applications/brave-browser.desktop"
printf 'chromium.desktop\n' >"$browser_state"
: >"$action_log"
cat >"$editor_file" <<'EOF'
# preserved
export EDITOR=vim
export VISUAL="$EDITOR"
export EDITOR=emacs
EOF
chmod 0644 "$editor_file"

run_defaults() {
  HOME="$test_home" \
    QVOS_PATH="$root" \
    QVOS_DEFAULTS_APPLICATION_DIRS="$applications" \
    QVOS_DEFAULTS_EDITOR_FILE="$editor_file" \
    QVOS_DEFAULTS_TERMINAL_FILE="$terminal_file" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_BROWSER_STATE="$browser_state" \
    QVOS_TEST_FAIL_MARKER="$test_root/failure-used" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

[[ $(run_defaults "$root/qvcore/defaults/browser") == "chromium" ]] ||
  fail "current browser reporting"
run_defaults "$root/qvcore/defaults/browser" firefox
[[ $(<"$browser_state") == "firefox.desktop" ]] || fail "browser default mutation"
grep -Fqx 'browser:firefox.desktop' "$action_log" || fail "browser owner delegation"

if QVOS_TEST_FAIL_BROWSER=brave-browser.desktop \
  run_defaults "$root/qvcore/defaults/browser" brave >/dev/null 2>&1; then
  fail "failed browser selection accepted"
fi
[[ $(<"$browser_state") == "firefox.desktop" ]] ||
  fail "failed browser selection did not restore the previous default"
if run_defaults "$root/qvcore/defaults/browser" zen >/dev/null 2>&1; then
  fail "unavailable browser accepted"
fi
[[ $(<"$browser_state") == "firefox.desktop" ]] ||
  fail "unavailable browser changed the default"

run_defaults "$root/qvcore/defaults/editor" nvim
[[ $(run_defaults "$root/qvcore/defaults/editor") == "nvim" ]] ||
  fail "editor default readback"
[[ $(grep -Fxc 'export EDITOR=nvim' "$editor_file") == 1 ]] ||
  fail "editor default is not singular"
grep -Fqx '# preserved' "$editor_file" || fail "editor unrelated content preservation"
# shellcheck disable=SC2016
grep -Fqx 'export VISUAL="$EDITOR"' "$editor_file" ||
  fail "editor dependent content preservation"
[[ $(stat -c '%a' "$editor_file") == "644" ]] || fail "editor mode preservation"

outside_editor="$test_root/outside-editor"
printf 'outside\n' >"$outside_editor"
rm -- "$editor_file"
ln -s "$outside_editor" "$editor_file"
if run_defaults "$root/qvcore/defaults/editor" nvim >/dev/null 2>&1; then
  fail "linked editor configuration accepted"
fi
[[ $(<"$outside_editor") == "outside" ]] || fail "linked editor target changed"
rm -- "$editor_file"
printf 'export EDITOR=nvim\n' >"$editor_file"

run_defaults "$root/qvcore/defaults/terminal" ghostty
[[ $(run_defaults "$root/qvcore/defaults/terminal") == "ghostty" ]] ||
  fail "terminal default readback"
grep -Fqx 'com.mitchellh.ghostty.desktop' "$terminal_file" ||
  fail "terminal desktop selection"
[[ $(stat -c '%a' "$terminal_file") == "600" ]] || fail "new terminal mode"

outside_terminal="$test_root/outside-terminal"
printf 'outside\n' >"$outside_terminal"
rm -- "$terminal_file"
ln -s "$outside_terminal" "$terminal_file"
if run_defaults "$root/qvcore/defaults/terminal" ghostty >/dev/null 2>&1; then
  fail "linked terminal configuration accepted"
fi
[[ $(<"$outside_terminal") == "outside" ]] || fail "linked terminal target changed"
rm -- "$terminal_file"

for owner in browser editor terminal; do
  if run_defaults "$root/qvcore/defaults/$owner" one two >/dev/null 2>&1; then
    fail "$owner default accepted extra arguments"
  fi
done

printf 'export EDITOR=nvim\n' >"$editor_file"
native=$(run_defaults "$root/bin/qv-default-editor")
compatible=$(run_defaults "$root/bin/omarchy-default-editor")
[[ $native == "nvim" && $compatible == "$native" ]] ||
  fail "default compatibility adapter parity"

"$root/qvcore/defaults/check"
printf 'ok - qvOS defaults are validated, atomic, rollback-aware, and singular\n'
