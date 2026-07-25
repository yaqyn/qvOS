#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
share_script="$root/qv/core/share.sh"
share_command="$root/bin/omarchy-menu-share"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
installed_dir="$test_root/installed"
action_log="$test_root/actions"
systemd_log="$test_root/systemd"
thunar_config="$test_root/.config/Thunar/uca.xml"
thunar_share_runtime="$test_root/.local/share/qvos/thunar/share"
thunar_share_command="/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/share\" \"\$@\"' qvos-thunar %F"

cleanup() {
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

reset_test_state() {
  rm -f "$installed_dir/localsend"
  rm -f "$thunar_share_runtime"
  find "$(dirname -- "$thunar_config")" \
    -maxdepth 1 \
    -type f \
    -name 'uca.xml*' \
    -delete
  install -m 0600 /dev/stdin "$thunar_config" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<actions>
  <action>
    <icon>utilities-terminal</icon>
    <name>Keep This Action</name>
    <unique-id>user-action</unique-id>
    <command>keep-action %f</command>
    <description>Unrelated user action.</description>
    <patterns>*</patterns>
    <directories/>
  </action>
</actions>
XML
  : >"$action_log"
  : >"$systemd_log"
}

assert_thunar_integration() {
  local action="/actions/action[unique-id='qvos-localsend-share']"
  local type

  xmlstarlet val -e "$thunar_config" >/dev/null ||
    fail "valid Thunar actions XML"
  [[ $(xmlstarlet sel -t -v "count($action)" "$thunar_config") == "1" ]] ||
    fail "single LocalSend Thunar action"
  [[ $(xmlstarlet sel -t -v "$action/icon" "$thunar_config") == "localsend" ]] ||
    fail "LocalSend Thunar icon"
  [[ $(xmlstarlet sel -t -v "$action/name" "$thunar_config") == "Send via LocalSend" ]] ||
    fail "LocalSend Thunar label"
  [[ $(xmlstarlet sel -t -v "count($action/submenu)" "$thunar_config") == "0" ]] ||
    fail "LocalSend Thunar top-level placement"
  [[ $(xmlstarlet sel -t -v "$action/command" "$thunar_config") == "$thunar_share_command" ]] ||
    fail "LocalSend Thunar command"
  [[ $(xmlstarlet sel -t -v "$action/patterns" "$thunar_config") == "*" ]] ||
    fail "LocalSend Thunar file pattern"

  for type in \
    directories \
    audio-files \
    image-files \
    other-files \
    text-files \
    video-files; do
    [[ $(xmlstarlet sel -t -v "count($action/$type)" "$thunar_config") == "1" ]] ||
      fail "LocalSend Thunar $type selection"
  done

  [[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='user-action'])" "$thunar_config") == "1" ]] ||
    fail "unrelated Thunar action preservation"
}

install -d "$test_bin" "$installed_dir" "$(dirname -- "$thunar_config")"

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_INSTALLED_DIR/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-missing" <<'SCRIPT'
#!/bin/bash
[[ ! -f $QVOS_TEST_INSTALLED_DIR/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"

if [[ $1 != "${QVOS_TEST_PACKAGE_NO_REGISTER:-}" ]]; then
  install -m 0644 /dev/null "$QVOS_TEST_INSTALLED_DIR/$1"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
case $1 in
localsend)
  [[ -f $QVOS_TEST_INSTALLED_DIR/localsend ]]
  ;;
omarchy-menu-share | xmlstarlet)
  exit 0
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
if omarchy-cmd-present "$1"; then
  exit 1
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemd-run" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_SYSTEMD_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_ACTION_LOG"
SCRIPT

run_share() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_INSTALLED_DIR="$installed_dir" \
    QVOS_TEST_PACKAGE_NO_REGISTER="${QVOS_TEST_PACKAGE_NO_REGISTER:-}" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$share_script"
}

run_share_command() {
  QVOS_TEST_INSTALLED_DIR="$installed_dir" \
    QVOS_TEST_SYSTEMD_LOG="$systemd_log" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    TMPDIR="$test_root" \
    "$share_command" "$@"
}

run_thunar_share() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$thunar_share_runtime" "$@"
}

reset_test_state
install_output=$(run_share)
[[ $(<"$action_log") == $'package\tlocalsend' ]] ||
  fail "missing LocalSend package install"
[[ -f $installed_dir/localsend ]] || fail "LocalSend package registration"
cmp -s "$root/qv/thunar/share" "$thunar_share_runtime" ||
  fail "Thunar Share helper installation"
assert_thunar_integration
(( $(find "$(dirname -- "$thunar_config")" -maxdepth 1 -type f -name 'uca.xml.bak.*' | wc -l) == 1 )) ||
  fail "Thunar actions backup"
grep -Fq 'qvCORE Share inventory: 0/3 ready' <<<"$install_output" ||
  fail "initial Share inventory"
grep -Fq 'qvCORE Share inventory: 3/3 ready' <<<"$install_output" ||
  fail "final Share inventory"
grep -Fq 'qvCORE Share is ready: 3/3.' <<<"$install_output" ||
  fail "Share ready summary"
pass "Share installs LocalSend, its Thunar helper, and its action"

: >"$action_log"
ready_checksum=$(sha256sum "$thunar_config")
ready_output=$(run_share)
[[ ! -s $action_log ]] || fail "ready Share rerun changes packages"
[[ $(sha256sum "$thunar_config") == "$ready_checksum" ]] ||
  fail "ready Share rerun rewrites Thunar actions"
(( $(find "$(dirname -- "$thunar_config")" -maxdepth 1 -type f -name 'uca.xml.bak.*' | wc -l) == 1 )) ||
  fail "ready Share rerun creates a backup"
grep -Fq 'qvCORE Share inventory: 3/3 ready' <<<"$ready_output" ||
  fail "ready Share inventory"
pass "Share reruns keep an already-ready Thunar integration unchanged"

: >"$action_log"
file_one="$test_root/One file.txt"
file_two="$test_root/Folder Two"
run_thunar_share "$file_one" "$file_two"
expected_thunar_args=$'share\nfile\n'
expected_thunar_args+="$file_one"$'\n'"$file_two"
[[ $(<"$action_log") == "$expected_thunar_args" ]] ||
  fail "Thunar Share helper argument preservation"
pass "Thunar Share helper delegates selections to the shared command"

printf 'stale helper\n' >"$thunar_share_runtime"
: >"$action_log"
helper_repair_output=$(run_share)
[[ ! -s $action_log ]] || fail "helper repair changes packages"
cmp -s "$root/qv/thunar/share" "$thunar_share_runtime" ||
  fail "stale Thunar Share helper repair"
grep -Fq 'qvCORE Share inventory: 2/3 ready' <<<"$helper_repair_output" ||
  fail "stale helper Share inventory"
pass "Share repairs only its stale Thunar helper"

xmlstarlet ed -L \
  -u "/actions/action[unique-id='qvos-localsend-share']/command" \
  -v "broken-command" \
  "$thunar_config"
: >"$action_log"
repair_output=$(run_share)
[[ ! -s $action_log ]] || fail "integration repair changes packages"
assert_thunar_integration
grep -Fq 'qvCORE Share inventory: 2/3 ready' <<<"$repair_output" ||
  fail "stale Share inventory"
pass "Share replaces only its stale Thunar action"

reset_test_state
set +e
verification_output=$(
  QVOS_TEST_PACKAGE_NO_REGISTER=localsend \
    run_share 2>&1
)
verification_status=$?
set -e
((verification_status != 0)) || fail "unregistered LocalSend install succeeds"
[[ $(<"$action_log") == $'package\tlocalsend' ]] ||
  fail "failed LocalSend verification action boundary"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-localsend-share'])" "$thunar_config") == "0" ]] ||
  fail "Thunar integration installed after package verification failure"
[[ ! -e $thunar_share_runtime ]] ||
  fail "Thunar helper installed after package verification failure"
grep -Fq 'LocalSend verification failed after installation.' \
  <<<"$verification_output" ||
  fail "LocalSend verification failure"
pass "Share verifies LocalSend before changing Thunar actions"

reset_test_state
install -m 0644 /dev/null "$installed_dir/localsend"
printf 'invalid xml\n' >"$thunar_config"
set +e
invalid_output=$(run_share 2>&1)
invalid_status=$?
set -e
((invalid_status != 0)) || fail "invalid Thunar actions XML succeeds"
[[ $(<"$thunar_config") == "invalid xml" ]] ||
  fail "invalid Thunar actions XML was overwritten"
[[ ! -s $action_log ]] || fail "invalid Thunar actions XML changes packages"
if find "$(dirname -- "$thunar_config")" \
  -maxdepth 1 \
  -type f \
  -name 'uca.xml.bak.*' |
  grep -q .; then
  fail "invalid Thunar actions XML creates a backup"
fi
[[ -n $invalid_output ]] || fail "invalid Thunar actions XML error"
pass "Share preserves malformed Thunar configuration for recovery"

reset_test_state
install -m 0644 /dev/null "$installed_dir/localsend"
run_share_command file "$file_one" "$file_two"
expected_systemd_args=$'--user\n--quiet\n--collect\nlocalsend\n--headless\nsend\n'
expected_systemd_args+="$file_one"$'\n'"$file_two"
[[ $(<"$systemd_log") == "$expected_systemd_args" ]] ||
  fail "LocalSend multi-selection argument preservation"
pass "Thunar multi-selection paths remain separate through the Share command"

: >"$systemd_log"
set +e
invalid_mode_output=$(run_share_command unknown 2>&1)
invalid_mode_status=$?
set -e
((invalid_mode_status != 0)) || fail "unknown Share mode succeeds"
[[ ! -s $systemd_log ]] || fail "unknown Share mode launches LocalSend"
grep -Fq 'Usage: omarchy-menu-share [clipboard|file|folder]' \
  <<<"$invalid_mode_output" ||
  fail "unknown Share mode usage"
pass "Share rejects unknown modes before launching LocalSend"

[[ -x $share_script ]] || fail "qvCORE Share component is not executable"
grep -Fqx '# localsend' "$root/install/omarchy-base.packages" ||
  fail "LocalSend is not disabled in the base package manifest"
if grep -Eq '^[[:space:]]+localsend([[:space:]\\]|$)' \
  "$root/bin/omarchy-remove-preinstalls"; then
  fail "preinstall cleanup removes qvCORE Share"
fi
grep -Fqx 'sudo ufw allow 53317/udp' "$root/install/first-run/firewall.sh" ||
  fail "LocalSend UDP firewall ownership"
grep -Fqx 'sudo ufw allow 53317/tcp' "$root/install/first-run/firewall.sh" ||
  fail "LocalSend TCP firewall ownership"
if grep -Eq '(localsend[[:space:]]+--(help|version)|uwsm-app|systemctl.*localsend)' \
  "$share_script"; then
  fail "Share launches LocalSend during installation verification"
fi
if grep -Fq 'Nautilus integration' "$share_script"; then
  fail "Share still treats Nautilus as the qvOS integration"
fi
pass "Share stays optional, on demand, and Thunar-owned"
