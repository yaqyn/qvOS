#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
launch_root="$root/qvcore/desktop/launch"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
setsid_log="$test_root/setsid.log"
focus_log="$test_root/focus.log"
rfkill_log="$test_root/rfkill.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_args() {
  local log=$1
  shift
  local expected_index
  local index
  local -a actual=()

  mapfile -t actual <"$log"
  ((${#actual[@]} == $#)) ||
    fail "argument count for $log: ${#actual[@]} != $#"
  for index in "${!actual[@]}"; do
    expected_index=$((index + 1))
    [[ ${actual[$index]} == "${!expected_index}" ]] ||
      fail "argument $index for $log"
  done
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_SETSID_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
clients) printf '%s\n' "${QVOS_TEST_CLIENTS_JSON:-[]}" ;;
dispatch)
  shift
  printf '%s\n' "$@" >"$QVOS_TEST_FOCUS_LOG"
  ;;
*) exit 64 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/xdg-settings" <<'SCRIPT'
#!/bin/bash
[[ $* == "get default-web-browser" ]] || exit 64
printf '%s\n' "${QVOS_TEST_BROWSER_DESKTOP:-chromium.desktop}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/rfkill" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_RFKILL_LOG"
exit "${QVOS_TEST_RFKILL_STATUS:-0}"
SCRIPT
for command in \
  bash \
  bluetui \
  btop \
  brave \
  chromium \
  code \
  fastfetch \
  firefox \
  impala \
  nvim \
  uwsm-app \
  wiremix \
  xdg-terminal-exec; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
done

export PATH="$test_bin:/usr/bin"
export QVOS_TEST_SETSID_LOG=$setsid_log
export QVOS_TEST_FOCUS_LOG=$focus_log
export QVOS_TEST_RFKILL_LOG=$rfkill_log

declare -A owners=(
  [about]=about
  [audio]=audio
  [bluetooth]=bluetooth
  [browser]=browser
  [editor]=editor
  [or-focus]=or-focus
  [or-focus-tui]=or-focus-tui
  [or-focus-webapp]=or-focus-webapp
  [tui]=tui
  [webapp]=webapp
  [wifi]=wifi
)
for route in "${!owners[@]}"; do
  owner=${owners[$route]}
  native="$root/bin/qv-launch-$route"
  compatibility="$root/bin/omarchy-launch-$route"
  [[ -x $launch_root/$owner && -x $native && -x $compatibility ]] ||
    fail "launch owner or adapter mode: $route"
  (($(wc -l <"$native") <= 12 && $(wc -l <"$compatibility") <= 5)) ||
    fail "launch adapter contains implementation: $route"
  rg -q '^# qv:summary=' "$native" || fail "native launch metadata: $route"
  ! rg -q '^# (qv|omarchy):' "$compatibility" ||
    fail "launch compatibility metadata: $route"
  for adapter in "$native" "$compatibility"; do
    grep -Fqx "exec \"\$QVOS_PATH/qvcore/desktop/launch/$owner\" \"\$@\"" \
      "$adapter" || fail "launch adapter delegation: $route"
  done
  grep -Fqx "bin/omarchy-launch-$route" "$root/qvcore/desktop/native-paths" ||
    fail "launch native-path ownership: $route"
done
[[ -f $launch_root/lib && ! -L $launch_root/lib &&
  $(stat -c '%a' "$launch_root/lib") == "644" ]] ||
  fail "launch library mode"
if rg -n '\beval\b|bash[[:space:]]+-c[[:space:]]+.*\$' "$launch_root"; then
  fail "launch owner shell-parses caller input"
fi
pass "desktop launch owners and compatibility adapters are singular"

export QVOS_TEST_CLIENTS_JSON='[{"address":"0xabc","class":"Org.QvOS.Wiremix","title":null}]'
unlink -- "$setsid_log" 2>/dev/null || true
"$launch_root/or-focus" wiremix fixture-command 'argument with spaces'
assert_args "$focus_log" focuswindow address:0xabc
[[ ! -e $setsid_log ]] || fail "matching launch started a duplicate"
pass "focus-or-launch validates and focuses an exact existing client"

export QVOS_TEST_CLIENTS_JSON='[]'
"$launch_root/or-focus" missing fixture-command 'argument with spaces' '; touch unsafe'
assert_args "$setsid_log" -- fixture-command 'argument with spaces' '; touch unsafe'
[[ ! -e $test_root/unsafe ]] || fail "launch arguments were shell-evaluated"
pass "focus-or-launch preserves exact arguments without shell evaluation"

export QVOS_TEST_CLIENTS_JSON='[{"address":"unsafe","class":"bad","title":"bad"}]'
unlink -- "$setsid_log" 2>/dev/null || true
set +e
"$launch_root/or-focus" bad fixture-command >/dev/null 2>&1
invalid_clients_status=$?
"$launch_root/or-focus" $'bad\npattern' fixture-command >/dev/null 2>&1
invalid_pattern_status=$?
set -e
((invalid_clients_status == 1 && invalid_pattern_status == 2)) ||
  fail "invalid focus input status"
[[ ! -e $setsid_log ]] || fail "invalid focus input launched a command"
pass "invalid compositor data and control-bearing patterns fail before launch"

export QVOS_TEST_CLIENTS_JSON='[]'
"$launch_root/tui" btop 'argument with spaces'
assert_args "$setsid_log" \
  -- uwsm-app -- xdg-terminal-exec --app-id=org.qvos.btop -e btop 'argument with spaces'
"$launch_root/or-focus-tui" wiremix 'argument with spaces'
assert_args "$setsid_log" \
  -- uwsm-app -- xdg-terminal-exec --app-id=org.qvos.wiremix -e wiremix 'argument with spaces'
pass "terminal launchers use qvOS application IDs and preserve arguments"

export QVOS_TEST_BROWSER_DESKTOP=custom-browser.desktop
"$launch_root/browser" 'https://example.com/a?b=1'
assert_args "$setsid_log" -- uwsm-app -- custom-browser.desktop 'https://example.com/a?b=1'
export QVOS_TEST_BROWSER_DESKTOP=chromium.desktop
"$launch_root/browser" --private 'https://example.com/private'
assert_args "$setsid_log" -- uwsm-app -- chromium --incognito 'https://example.com/private'
export QVOS_TEST_BROWSER_DESKTOP=firefox.desktop
"$launch_root/browser" --private
assert_args "$setsid_log" -- uwsm-app -- firefox --private-window
pass "browser launch supports custom entries and exact known private modes"

export QVOS_TEST_BROWSER_DESKTOP=custom-browser.desktop
unlink -- "$setsid_log" 2>/dev/null || true
set +e
"$launch_root/browser" --private >/dev/null 2>&1
unknown_private_status=$?
QVOS_TEST_BROWSER_DESKTOP='../unsafe.desktop' "$launch_root/browser" >/dev/null 2>&1
invalid_browser_status=$?
set -e
((unknown_private_status == 1 && invalid_browser_status == 1)) ||
  fail "unsupported browser status"
[[ ! -e $setsid_log ]] || fail "unsafe browser state launched"
pass "unsupported private modes and malformed desktop IDs fail before launch"

export QVOS_TEST_BROWSER_DESKTOP=firefox.desktop
"$launch_root/webapp" 'https://example.com/app?x=1' '--start-maximized'
assert_args "$setsid_log" -- uwsm-app -- chromium '--app=https://example.com/app?x=1' '--start-maximized'
unlink -- "$setsid_log" 2>/dev/null || true
set +e
"$launch_root/webapp" 'javascript:unsafe' >/dev/null 2>&1
invalid_url_status=$?
"$launch_root/webapp" 'https://user:pass@example.com' >/dev/null 2>&1
credentials_url_status=$?
"$launch_root/webapp" 'https://example..com' >/dev/null 2>&1
hostname_url_status=$?
"$launch_root/webapp" 'https://example.com:0' >/dev/null 2>&1
port_url_status=$?
"$launch_root/webapp" 'https://[::1]' >/dev/null 2>&1
ipv6_url_status=$?
"$launch_root/webapp" $'https://example.com/\303\251' >/dev/null 2>&1
non_ascii_url_status=$?
set -e
((invalid_url_status == 2 &&
  credentials_url_status == 2 &&
  hostname_url_status == 2 &&
  port_url_status == 2 &&
  ipv6_url_status == 2 &&
  non_ascii_url_status == 2)) || fail "invalid web-app URL status"
[[ ! -e $setsid_log ]] || fail "invalid web-app URL launched"
pass "web-app launch rejects malformed, credential-bearing, and ambiguous URLs"

export QVOS_TEST_CLIENTS_JSON='[{"address":"0xdef","class":"Example App","title":"Example"}]'
"$launch_root/or-focus-webapp" 'example app' 'https://example.com/app'
assert_args "$focus_log" focuswindow address:0xdef
[[ ! -e $setsid_log ]] || fail "existing web app launched a duplicate"
pass "web-app focus reuses validated client matching"

export QVOS_TEST_CLIENTS_JSON='[]'
EDITOR=nvim "$launch_root/editor" "$test_root/file with spaces"
assert_args "$setsid_log" \
  -- uwsm-app -- xdg-terminal-exec --app-id=org.qvos.nvim -e nvim "$test_root/file with spaces"
EDITOR=code "$launch_root/editor" "$test_root/file with spaces"
assert_args "$setsid_log" -- uwsm-app -- code "$test_root/file with spaces"
pass "default editor launch distinguishes terminal and graphical applications"

QVOS_TEST_RFKILL_STATUS=1 "$launch_root/wifi" >/dev/null 2>"$test_root/wifi.stderr"
assert_args "$rfkill_log" unblock wifi
grep -Fq 'opening its controls anyway' "$test_root/wifi.stderr" ||
  fail "Wi-Fi unblock degradation warning"
assert_args "$setsid_log" \
  -- uwsm-app -- xdg-terminal-exec --app-id=org.qvos.impala -e impala
"$launch_root/bluetooth" >/dev/null
assert_args "$rfkill_log" unblock bluetooth
"$launch_root/audio" >/dev/null
assert_args "$setsid_log" \
  -- uwsm-app -- xdg-terminal-exec --app-id=org.qvos.wiremix -e wiremix
pass "radio and audio controls remain accessible with exact native launchers"

"$launch_root/about" >/dev/null
mapfile -t about_args <"$setsid_log"
[[ ${about_args[*]} == *org.qvos.bash* && ${about_args[*]} == *fastfetch* ]] ||
  fail "native About launcher"
pass "About uses fixed qvOS terminal launch behavior"

for frontend in qv omarchy; do
  commands=$("$root/bin/$frontend" commands --json)
  for route in "${!owners[@]}"; do
    jq -e --arg binary "qv-launch-$route" --arg prefix "$frontend launch " '
      [.commands[] | select(.binary == $binary and (.route | startswith($prefix)))] |
      length == 1
    ' <<<"$commands" >/dev/null || fail "$frontend native launch route: $route"
  done
done
pass "both CLI frontends resolve every launch command to qvOS metadata"

"$root/qvcore/desktop/check" >/dev/null
pass "desktop launch ownership contract passes"
