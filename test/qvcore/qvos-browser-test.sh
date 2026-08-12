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
  "$fixture/qvcore/browser" \
  "$fixture/qvcore/config/files" \
  "$test_bin"
install -m 0755 "$root/bin/omarchy-install-browser" "$fixture/bin/"
install -m 0755 "$root/bin/omarchy-refresh-chromium" "$fixture/bin/"
install -m 0755 "$root/bin/omarchy-remove-browser" "$fixture/bin/"
install -m 0755 "$root/bin/qv-install-browser" "$fixture/bin/"
install -m 0755 "$root/bin/qv-refresh-chromium" "$fixture/bin/"
install -m 0755 "$root/bin/qv-remove-browser" "$fixture/bin/"
install -m 0755 "$root/qvcore/browser/install" "$fixture/qvcore/browser/"
install -m 0755 "$root/qvcore/browser/refresh-chromium" "$fixture/qvcore/browser/"
install -m 0755 "$root/qvcore/browser/remove" "$fixture/qvcore/browser/"
install -m 0644 "$root/qvcore/browser/firefox-policies.json" \
  "$fixture/qvcore/browser/firefox-policies.json"
cp -a "$root/qvcore/browser/extensions" "$fixture/qvcore/browser/"
install -D -m 0755 "$root/qvcore/config/refresh" "$fixture/qvcore/config/refresh"
install -m 0644 "$root/qvcore/config/files/chromium-flags.conf" \
  "$fixture/qvcore/config/files/chromium-flags.conf"
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
install -m 0755 /dev/stdin "$test_bin/qv-default-browser" <<'STUB'
#!/bin/bash
printf 'default-browser:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
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
    XDG_CONFIG_HOME="$test_home/.config" \
    QVOS_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$@"
}

chromium_flags="$test_home/.config/chromium-flags.conf"
printf '%s\n' '--custom-browser-flag' >"$chromium_flags"
invalid_snapshot=$(sha256sum "$chromium_flags")
if run_browser "$fixture/bin/omarchy-install-browser" unknown >/dev/null 2>&1; then
  fail "unsupported browser install"
fi
[[ $(sha256sum "$chromium_flags") == "$invalid_snapshot" ]] ||
  fail "invalid browser install changed configuration"
run_browser "$fixture/bin/qv-refresh-chromium" >/dev/null
cmp -s "$fixture/qvcore/config/files/chromium-flags.conf" "$chromium_flags" ||
  fail "native Chromium refresh"
chromium_backup_root="$test_home/.local/state/qvos/config-backups/refresh"
mapfile -t chromium_backups < <(
  for path_file in "$chromium_backup_root"/*/path; do
    [[ -f $path_file ]] || continue
    [[ $(<"$path_file") == "chromium-flags.conf" ]] || continue
    printf '%s/value\n' "${path_file%/path}"
  done
)
((${#chromium_backups[@]} == 1)) || fail "one private Chromium refresh backup"
grep -Fqx -- '--custom-browser-flag' "${chromium_backups[0]}" ||
  fail "Chromium refresh backup content"
if compgen -G "$test_home/.config/chromium-flags.conf.bak.*" >/dev/null; then
  fail "Chromium refresh backup polluted active configuration"
fi
if run_browser "$fixture/bin/qv-refresh-chromium" unexpected \
  >/dev/null 2>&1; then
  fail "Chromium refresh accepted unexpected arguments"
fi

run_browser "$fixture/bin/qv-install-browser" chrome >/dev/null
grep -Fqx 'aur-add:google-chrome' "$action_log" || fail "Chrome package owner"
grep -Fqx 'policy:/etc/opt/chrome/policies/managed' "$action_log" ||
  fail "Chrome policy owner"
cmp -s \
  "$fixture/qvcore/config/files/chromium-flags.conf" \
  "$test_home/.config/chrome-flags.conf" ||
  fail "Chrome flag installation"

run_browser "$fixture/bin/qv-install-browser" brave-origin >/dev/null
grep -Fqx 'aur-add:brave-origin-beta-bin' "$action_log" ||
  fail "Brave Origin package owner"
cmp -s \
  "$fixture/qvcore/config/files/chromium-flags.conf" \
  "$test_home/.config/brave-origin-beta-flags.conf" ||
  fail "Brave Origin shares the native Chromium flags"

run_browser "$fixture/bin/qv-install-browser" firefox >/dev/null
grep -Fqx 'pkg-add:firefox' "$action_log" || fail "Firefox package owner"
grep -Fqx 'policy:/usr/lib/firefox/distribution' "$action_log" ||
  fail "Firefox policy owner"
grep -Fqx \
  "sudo:install -m 0644 $fixture/qvcore/browser/firefox-policies.json /usr/lib/firefox/distribution/policies.json" \
  "$action_log" || fail "Firefox native policy source"
grep -Fqx 'MOZ_ENABLE_WAYLAND=1' \
  "$test_home/.config/environment.d/qvos-firefox-wayland.conf" ||
  fail "Firefox Wayland configuration"

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
grep -Fqx 'default-browser:chromium' "$action_log" ||
  fail "removed active browser fallback"

printf '%s\n' 'CUSTOM_FIREFOX_SETTING=1' \
  >"$test_home/.config/environment.d/qvos-firefox-wayland.conf"
preservation_warning=$(run_browser \
  "$fixture/bin/qv-remove-browser" firefox 2>&1 >/dev/null)
grep -Fqx 'CUSTOM_FIREFOX_SETTING=1' \
  "$test_home/.config/environment.d/qvos-firefox-wayland.conf" ||
  fail "modified native Firefox environment preservation"
grep -Fq 'Preserving modified Firefox Wayland environment:' \
  <<<"$preservation_warning" ||
  fail "modified native Firefox environment warning"

external_wayland="$test_root/external-firefox-wayland"
printf '%s\n' 'EXTERNAL_FIREFOX_SETTING=1' >"$external_wayland"
unlink -- "$test_home/.config/environment.d/qvos-firefox-wayland.conf"
ln -s "$external_wayland" \
  "$test_home/.config/environment.d/qvos-firefox-wayland.conf"
run_browser "$fixture/bin/qv-remove-browser" firefox >/dev/null 2>&1
[[ -L $test_home/.config/environment.d/qvos-firefox-wayland.conf &&
  $(<"$external_wayland") == "EXTERNAL_FIREFOX_SETTING=1" ]] ||
  fail "linked native Firefox environment preservation"

"$root/qvcore/browser/check"
printf 'ok - optional browser installs and removals are exact and non-destructive\n'
