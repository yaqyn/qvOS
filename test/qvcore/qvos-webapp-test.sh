#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner_root="$root/qvcore/desktop/webapp"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
event_log="$test_root/events.log"

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

install -d "$test_home" "$test_bin"
: >"$event_log"

install -m 0755 /dev/stdin "$test_bin/qv-restart-walker" <<'SCRIPT'
#!/bin/bash
printf 'restart-walker\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/update-desktop-database" <<'SCRIPT'
#!/bin/bash
printf 'desktop-database:%s\n' "$*" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
output=""
while (($# > 0)); do
  if [[ $1 == "--output" ]]; then
    output=$2
    shift 2
  else
    shift
  fi
done
[[ -n $output ]] || exit 2
[[ ${QVOS_TEST_CURL_FAIL:-0} == "0" ]] || exit 22
if [[ ${QVOS_TEST_CURL_OVERSIZED_DIMENSIONS:-0} == "1" ]]; then
  printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\023\210\000\000\023\210fixture' >"$output"
else
  printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\001\000\000\000\001fixture' >"$output"
fi
SCRIPT

run_owner() {
  HOME="$test_home" \
    QVOS_PATH="$root" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

declare -A owners=(
  [install]=install
  [remove]=remove
)
for route in "${!owners[@]}"; do
  native="$root/bin/qv-webapp-$route"
  compatibility="$root/bin/omarchy-webapp-$route"
  [[ -x $owner_root/${owners[$route]} && -x $native && -x $compatibility ]] ||
    fail "Web App owner or adapter mode: $route"
  (($(wc -l <"$native") <= 10 && $(wc -l <"$compatibility") <= 5)) ||
    fail "Web App adapter contains implementation: $route"
  rg -q '^# qv:summary=' "$native" || fail "native Web App metadata: $route"
  ! rg -q '^# (qv|omarchy):' "$compatibility" ||
    fail "Web App compatibility metadata: $route"
done
for adapter in "$root/bin/qv-webapp-remove-all" "$root/bin/omarchy-webapp-remove-all"; do
  [[ -x $adapter ]] || fail "Web App remove-all adapter mode"
done
[[ -f $owner_root/lib && ! -L $owner_root/lib &&
  $(stat -c '%a' "$owner_root/lib") == "644" ]] || fail "Web App library mode"
pass "Web App commands have singular native owners and thin compatibility adapters"

if run_owner "$owner_root/install" '../escape' https://example.com "" >/dev/null 2>&1; then
  fail "Web App installer accepted path traversal"
fi
if run_owner "$owner_root/install" Unsafe 'https://example.com/%ZZ' "" >/dev/null 2>&1; then
  fail "Web App installer accepted an invalid percent escape"
fi
if run_owner "$owner_root/install" Unsafe https://example.com "" \
  'sh -c unsafe' "" >/dev/null 2>&1; then
  fail "Web App installer accepted an arbitrary Exec command"
fi
[[ ! -e $test_home/.local ]] || fail "invalid Web App input created user state"
pass "Web App input is validated before filesystem or network mutation"

# shellcheck disable=SC2016 # literal dollar verifies desktop Exec escaping
run_owner "$owner_root/install" \
  'My App' 'example.com/path?next=%2F&cash=$5' "" >/dev/null
app_dir="$test_home/.local/share/applications"
icon_dir="$app_dir/icons"
my_app="$app_dir/My App.desktop"
[[ -f $my_app && ! -L $my_app && $(stat -c '%a' "$my_app") == "644" ]] ||
  fail "safe Web App desktop publication"
# shellcheck disable=SC2016 # expected desktop file contains an escaped dollar
grep -Fqx 'Exec=qv-launch-webapp "https://example.com/path?next=%%2F&cash=\$5"' \
  "$my_app" || fail "desktop Exec escaping"
grep -Fqx 'Icon=web-browser' "$my_app" || fail "generic Web App icon"
grep -Fqx 'X-qvOS-WebApp-IconOwned=false' "$my_app" ||
  fail "generic Web App icon ownership"
original_hash=$(sha256sum "$my_app")
if run_owner "$owner_root/install" 'My App' https://changed.example "" \
  >/dev/null 2>&1; then
  fail "Web App installer overwrote an existing desktop entry"
fi
[[ $(sha256sum "$my_app") == "$original_hash" ]] ||
  fail "existing Web App desktop entry changed"
pass "Web App desktop files are atomic, escaped, private-state-free, and no-clobber"

if run_owner "$owner_root/install" \
  BadZoom https://zoom.us "" \
  'omarchy-webapp-handler-zoom %u' 'text/plain' >/dev/null 2>&1; then
  fail "Web App installer accepted a retired service-specific handler"
fi
pass "Web App installation accepts no service-specific handler ABI"

run_owner "$owner_root/install" \
  'Icon App' https://icons.example \
  https://icons.example/icon.png >/dev/null
icon_app="$app_dir/Icon App.desktop"
icon_path="$icon_dir/Icon App.png"
[[ -f $icon_path && ! -L $icon_path && $(stat -c '%a' "$icon_path") == "644" ]] ||
  fail "downloaded Web App icon publication"
grep -Fqx "Icon=$icon_path" "$icon_app" || fail "downloaded Web App icon path"
grep -Fqx 'X-qvOS-WebApp-IconOwned=true' "$icon_app" ||
  fail "downloaded Web App icon ownership"
if QVOS_TEST_CURL_FAIL=1 run_owner "$owner_root/install" \
  Failed https://failed.example https://failed.example/icon.png \
  >/dev/null 2>&1; then
  fail "failed icon download reported success"
fi
[[ ! -e $app_dir/Failed.desktop && ! -e $icon_dir/Failed.png ]] ||
  fail "failed icon download left partial state"
if QVOS_TEST_CURL_OVERSIZED_DIMENSIONS=1 run_owner "$owner_root/install" \
  Oversized https://oversized.example https://oversized.example/icon.png \
  >/dev/null 2>&1; then
  fail "oversized icon dimensions reported success"
fi
[[ ! -e $app_dir/Oversized.desktop && ! -e $icon_dir/Oversized.png ]] ||
  fail "oversized icon dimensions left partial state"
pass "explicit HTTPS PNG icons are bounded, validated, and rollback-safe"

listed=$(run_owner "$owner_root/remove" --list)
[[ $listed == $'Icon App\nMy App' ]] || fail "Web App managed inventory"
install -m 0644 /dev/stdin "$app_dir/Foreign.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=/usr/bin/true
DESKTOP
install -m 0644 /dev/stdin "$app_dir/Manual qv.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=qv-launch-webapp "https://manual.example"
DESKTOP
install -m 0644 /dev/stdin "$app_dir/Historical.desktop" <<'DESKTOP'
[Desktop Entry]
Exec=omarchy-launch-webapp https://historical.example
DESKTOP
if run_owner "$owner_root/remove" Foreign >/dev/null 2>&1; then
  fail "Web App removal accepted a foreign desktop entry"
fi
if run_owner "$owner_root/remove" 'Manual qv' >/dev/null 2>&1; then
  fail "Web App removal accepted an unmarked manual qv launcher"
fi
if run_owner "$owner_root/remove" Historical >/dev/null 2>&1; then
  fail "Web App removal accepted a historical Omarchy launcher"
fi
[[ -f $app_dir/Foreign.desktop ]] || fail "foreign desktop entry was removed"
[[ -f "$app_dir/Manual qv.desktop" ]] || fail "manual qv launcher was removed"
[[ -f $app_dir/Historical.desktop ]] ||
  fail "historical Omarchy launcher was removed"
run_owner "$owner_root/remove" 'Icon App' >/dev/null
[[ ! -e $icon_app && ! -e $icon_path ]] ||
  fail "owned Web App desktop and icon removal"
pass "Web App removal proves ownership and preserves foreign desktop entries"

run_owner "$owner_root/remove" --all >/dev/null
[[ -f $app_dir/Foreign.desktop ]] || fail "remove-all deleted a foreign desktop entry"
[[ -f "$app_dir/Manual qv.desktop" ]] ||
  fail "remove-all deleted an unmarked manual qv launcher"
[[ -f $app_dir/Historical.desktop ]] ||
  fail "remove-all deleted a historical Omarchy launcher"
if [[ -n $(run_owner "$owner_root/remove" --list) ]]; then
  fail "remove-all left a managed Web App"
fi
pass "remove-all is bounded to the singular managed Web App inventory"

for frontend in qv omarchy; do
  commands=$("$root/bin/$frontend" commands --json)
  for route in "${!owners[@]}" remove-all; do
    jq -e --arg binary "qv-webapp-$route" --arg prefix "$frontend webapp " '
      [.commands[] | select(.binary == $binary and (.route | startswith($prefix)))] |
      length == 1
    ' <<<"$commands" >/dev/null || fail "$frontend native Web App route: $route"
  done
done
for handler in hey zoom; do
  for path in \
    "$root/bin/qv-webapp-handler-$handler" \
    "$root/bin/omarchy-webapp-handler-$handler" \
    "$owner_root/handler-$handler"; do
    [[ ! -e $path && ! -L $path ]] ||
      fail "retired Web App handler remains: ${path#"$root/"}"
  done
done
"$root/qvcore/desktop/check" >/dev/null
pass "both CLI frontends expose only generic user-created Web App routes"
