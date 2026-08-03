#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
fixture="$test_root/source"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_home/.config/environment.d" \
  "$fixture/bin" \
  "$fixture/config" \
  "$fixture/default/firefox" \
  "$fixture/qvcore/browser" \
  "$test_bin"
install -m 0755 "$root/bin/omarchy-install-browser" "$fixture/bin/"
install -m 0755 "$root/bin/omarchy-remove-browser" "$fixture/bin/"
install -m 0755 "$root/bin/qv-install-browser" "$fixture/bin/"
install -m 0755 "$root/bin/qv-remove-browser" "$fixture/bin/"
install -m 0755 "$root/qvcore/browser/install" "$fixture/qvcore/browser/"
install -m 0755 "$root/qvcore/browser/migrate-runtime-root" "$fixture/qvcore/browser/"
install -m 0755 "$root/qvcore/browser/remove" "$fixture/qvcore/browser/"
printf '%s\n' '--enable-features=UseOzonePlatform' >"$fixture/config/chromium-flags.conf"
printf '%s\n' '{"policies":{}}' >"$fixture/default/firefox/policies.json"
touch "$action_log"

install -m 0755 /dev/stdin "$fixture/qvcore/browser/setup-policy" <<'STUB'
#!/bin/bash
printf 'policy:%s\n' "$1" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-aur-add" <<'STUB'
#!/bin/bash
printf 'aur-add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg-add:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-drop" <<'STUB'
#!/bin/bash
printf 'pkg-drop:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-missing" <<'STUB'
#!/bin/bash
exit 0
STUB
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'STUB'
#!/bin/bash
exit 0
STUB
install -m 0755 /dev/stdin "$test_bin/qv-theme-set-browser" <<'STUB'
#!/bin/bash
printf 'theme\n' >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/xdg-settings" <<'STUB'
#!/bin/bash
if [[ $1 == "get" ]]; then
  printf '%s\n' "${QVOS_TEST_DEFAULT_BROWSER:-chromium.desktop}"
else
  printf 'xdg-settings:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
fi
STUB
install -m 0755 /dev/stdin "$test_bin/xdg-mime" <<'STUB'
#!/bin/bash
printf 'xdg-mime:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB

run_browser() {
  HOME="$test_home" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$@"
}

run_browser "$fixture/bin/qv-install-browser" chrome >/dev/null
grep -Fqx 'aur-add:google-chrome' "$action_log" || fail "Chrome package owner"
grep -Fqx 'policy:/etc/opt/chrome/policies/managed' "$action_log" ||
  fail "Chrome policy owner"
cmp -s \
  "$fixture/config/chromium-flags.conf" \
  "$test_home/.config/chrome-flags.conf" ||
  fail "Chrome flag installation"

if run_browser "$fixture/bin/omarchy-install-browser" unknown >/dev/null 2>&1; then
  fail "unsupported browser install"
fi

printf '%s\n' 'MOZ_ENABLE_WAYLAND=1' \
  >"$test_home/.config/environment.d/omarchy-firefox-wayland.conf"
run_browser "$fixture/bin/qv-install-browser" firefox >/dev/null
grep -Fqx 'pkg-add:firefox' "$action_log" || fail "Firefox package owner"
grep -Fqx 'policy:/usr/lib/firefox/distribution' "$action_log" ||
  fail "Firefox policy owner"
grep -Fqx 'MOZ_ENABLE_WAYLAND=1' \
  "$test_home/.config/environment.d/qvos-firefox-wayland.conf" ||
  fail "Firefox Wayland configuration"
[[ ! -e $test_home/.config/environment.d/omarchy-firefox-wayland.conf ]] ||
  fail "retired Firefox Wayland configuration"

QVOS_TEST_DEFAULT_BROWSER=brave-browser.desktop \
  run_browser "$fixture/bin/qv-remove-browser" brave >/dev/null
grep -Fqx 'pkg-drop:brave-bin' "$action_log" || fail "Brave package removal"
grep -Fqx 'sudo:rm -f -- /etc/brave/policies/managed/color.json' "$action_log" ||
  fail "Brave exact policy cleanup"
if grep -Eq 'sudo:rm .*-(r|rf|fr).* /etc/brave' "$action_log"; then
  fail "Brave removal recursively deletes shared policy"
fi

QVOS_TEST_DEFAULT_BROWSER=firefox.desktop \
  run_browser "$fixture/bin/qv-remove-browser" firefox >/dev/null
[[ ! -e $test_home/.config/environment.d/qvos-firefox-wayland.conf ]] ||
  fail "unused Firefox-family Wayland cleanup"
grep -Fqx 'xdg-settings:set default-web-browser chromium.desktop' "$action_log" ||
  fail "removed active browser fallback"

printf '%s\n' 'CUSTOM_FIREFOX_SETTING=1' \
  >"$test_home/.config/environment.d/omarchy-firefox-wayland.conf"
run_browser "$fixture/qvcore/browser/migrate-runtime-root" --remove 2>/dev/null
grep -Fqx 'CUSTOM_FIREFOX_SETTING=1' \
  "$test_home/.config/environment.d/omarchy-firefox-wayland.conf" ||
  fail "modified legacy Firefox environment preservation"

"$root/qvcore/browser/check"
printf 'ok - optional browser installs and removals are exact and non-destructive\n'
