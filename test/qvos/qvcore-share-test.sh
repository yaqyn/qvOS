#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
share_script="$root/qv/core/share.sh"
firewall_reconciler="$root/qv/core/share/reconcile-inherited-firewall"
share_command="$root/qv/share/share"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
installed_dir="$test_root/installed"
action_log="$test_root/actions"
systemd_log="$test_root/systemd"
thunar_config="$test_root/.config/Thunar/uca.xml"
thunar_share_runtime="$test_root/.local/share/qvos/thunar/share"
thunar_share_command="/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/share\" \"\$@\"' qvos-thunar %F"
state_file="$test_root/.local/state/qvos/qvcore/share"
hook_target="$test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore-share"
firewall_profile="$test_root/firewall/qvos-qvcore-share"
firewall_rules_v4="$test_root/firewall/user.rules"
firewall_rules_v6="$test_root/firewall/user6.rules"
firewall_defaults="$test_root/firewall/ufw"

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
  rm -f \
    "$state_file" \
    "$hook_target" \
    "$firewall_profile" \
    "$firewall_rules_v4" \
    "$firewall_rules_v6"
  install -D -m 0644 /dev/stdin "$firewall_defaults" <<'DEFAULTS'
IPV6=yes
DEFAULTS
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
omarchy-qvos-share | ufw | xmlstarlet)
  exit 0
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/ufw" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

printf 'ufw\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
case $* in
"app update qvCORE Share")
  ;;
"allow qvCORE Share")
  install -d "$(dirname -- "$QVOS_SHARE_UFW_RULES_V4")"
  printf '%s\n' \
    '-A ufw-user-input -p tcp --dport 53317 -j ACCEPT' \
    '-A ufw-user-input -p udp --dport 53317 -j ACCEPT' \
    >"$QVOS_SHARE_UFW_RULES_V4"
  cp "$QVOS_SHARE_UFW_RULES_V4" "$QVOS_SHARE_UFW_RULES_V6"
  ;;
"delete allow qvCORE Share" | \
"delete allow 53317/tcp" | \
"delete allow 53317/udp")
  rm -f "$QVOS_SHARE_UFW_RULES_V4" "$QVOS_SHARE_UFW_RULES_V6"
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

install -m 0755 /dev/stdin "$test_bin/localsend" <<'SCRIPT'
#!/bin/bash
printf 'localsend\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-qvos-share" <<'SCRIPT'
#!/bin/bash
printf 'share\n' >"$QVOS_TEST_ACTION_LOG"
printf '%s\n' "$@" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

run_share() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_INSTALLED_DIR="$installed_dir" \
    QVOS_TEST_PACKAGE_NO_REGISTER="${QVOS_TEST_PACKAGE_NO_REGISTER:-}" \
    QVOS_SHARE_UFW_DEFAULTS="$firewall_defaults" \
    QVOS_SHARE_UFW_PROFILE_TARGET="$firewall_profile" \
    QVOS_SHARE_UFW_RULES_V4="$firewall_rules_v4" \
    QVOS_SHARE_UFW_RULES_V6="$firewall_rules_v6" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$share_script" "$@"
}

run_share_command() {
  QVOS_TEST_ACTION_LOG="$action_log" \
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
install -D -m 0644 /dev/null "$hook_target"
install_output=$(run_share)
grep -Fqx $'package\tlocalsend' "$action_log" ||
  fail "missing LocalSend package install"
[[ -f $installed_dir/localsend ]] || fail "LocalSend package registration"
cmp -s "$root/qv/thunar/share" "$thunar_share_runtime" ||
  fail "Thunar Share helper installation"
assert_thunar_integration
(( $(find "$(dirname -- "$thunar_config")" -maxdepth 1 -type f -name 'uca.xml.bak.*' | wc -l) == 1 )) ||
  fail "Thunar actions backup"
cmp -s "$root/qv/core/share/ufw.profile" "$firewall_profile" ||
  fail "qvCORE Share firewall profile installation"
[[ ! -e $hook_target ]] ||
  fail "legacy qvCORE Share post-update hook cleanup"
[[ -f $state_file ]] || fail "qvCORE Share enabled state"
grep -Fq 'qvCORE Share inventory: 0/5 ready' <<<"$install_output" ||
  fail "initial Share inventory"
grep -Fq 'qvCORE Share inventory: 5/5 ready' <<<"$install_output" ||
  fail "final Share inventory"
grep -Fq 'qvCORE Share is ready: 5/5.' <<<"$install_output" ||
  fail "Share ready summary"
pass "Share installs LocalSend and all owned integration surfaces"

: >"$action_log"
ready_checksum=$(sha256sum "$thunar_config")
ready_output=$(run_share --repair)
if grep -Eq $'^(package|sudo|ufw)\t' "$action_log"; then
  fail "ready Share repair changes packages or firewall"
fi
[[ $(sha256sum "$thunar_config") == "$ready_checksum" ]] ||
  fail "ready Share rerun rewrites Thunar actions"
(( $(find "$(dirname -- "$thunar_config")" -maxdepth 1 -type f -name 'uca.xml.bak.*' | wc -l) == 1 )) ||
  fail "ready Share rerun creates a backup"
grep -Fq 'qvCORE Share inventory: 5/5 ready' <<<"$ready_output" ||
  fail "ready Share inventory"
pass "Share repair keeps an already-ready integration unchanged"

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
helper_repair_output=$(run_share --repair)
if grep -Eq $'^(package|sudo|ufw)\t' "$action_log"; then
  fail "helper repair changes packages or firewall"
fi
cmp -s "$root/qv/thunar/share" "$thunar_share_runtime" ||
  fail "stale Thunar Share helper repair"
grep -Fq 'qvCORE Share inventory: 4/5 ready' <<<"$helper_repair_output" ||
  fail "stale helper Share inventory"
pass "Share repairs only its stale Thunar helper"

xmlstarlet ed -L \
  -u "/actions/action[unique-id='qvos-localsend-share']/command" \
  -v "broken-command" \
  "$thunar_config"
: >"$action_log"
repair_output=$(run_share --repair)
if grep -Eq $'^(package|sudo|ufw)\t' "$action_log"; then
  fail "integration repair changes packages or firewall"
fi
assert_thunar_integration
grep -Fq 'qvCORE Share inventory: 4/5 ready' <<<"$repair_output" ||
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
grep -Fqx $'package\tlocalsend' "$action_log" ||
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
if grep -Fq $'package\t' "$action_log"; then
  fail "invalid Thunar actions XML changes packages"
fi
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
adopt_output=$(run_share --adopt)
grep -Fq 'qvCORE Share is ready: 5/5.' <<<"$adopt_output" ||
  fail "Share adopt result"
if grep -Fq $'package\t' "$action_log"; then
  fail "Share adoption installs a package"
fi
pass "Share adopts an existing LocalSend install without reinstalling it"

: >"$action_log"
disable_output=$(run_share --disable)
[[ ! -e $thunar_share_runtime ]] || fail "Share disable helper removal"
[[ ! -e $state_file && ! -e $hook_target ]] ||
  fail "Share disable maintenance removal"
[[ ! -e $firewall_profile ]] || fail "Share disable firewall profile removal"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-localsend-share'])" "$thunar_config") == "0" ]] ||
  fail "Share disable action removal"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='user-action'])" "$thunar_config") == "1" ]] ||
  fail "Share disable user action preservation"
[[ -f $installed_dir/localsend ]] || fail "Share disable package preservation"
grep -Fq 'LocalSend and personal data were not changed.' <<<"$disable_output" ||
  fail "Share disable boundary"
pass "Share disables only its owned integration and preserves LocalSend"

reset_test_state
install -m 0644 /dev/null "$installed_dir/localsend"
run_share_command file "$file_one" "$file_two"
expected_systemd_args=$'--user\n--quiet\n--collect\nlocalsend\n--headless\nsend\n'
expected_systemd_args+="$file_one"$'\n'"$file_two"
[[ $(<"$systemd_log") == "$expected_systemd_args" ]] ||
  fail "LocalSend multi-selection argument preservation"
pass "Thunar multi-selection paths remain separate through the Share command"

safe_clipboard_temp=$(mktemp "$test_root/qvos-share-clipboard.XXXXXX.txt")
chmod 0600 "$safe_clipboard_temp"
printf 'private clipboard text\n' >"$safe_clipboard_temp"
: >"$action_log"
run_share_command --send-clipboard-temp "$safe_clipboard_temp"
[[ ! -e $safe_clipboard_temp ]] ||
  fail "clipboard temporary file cleanup"
grep -Fqx $'localsend\t--headless send '"$safe_clipboard_temp" "$action_log" ||
  fail "clipboard temporary file send"

unsafe_clipboard_temp="$test_root/unowned-name.txt"
install -m 0600 /dev/null "$unsafe_clipboard_temp"
if run_share_command --send-clipboard-temp "$unsafe_clipboard_temp" \
  >/dev/null 2>&1; then
  fail "unsafe clipboard temporary path succeeds"
fi
[[ -f $unsafe_clipboard_temp ]] ||
  fail "unsafe clipboard path was removed"
pass "clipboard sharing cleans only its private verified temporary file"

: >"$systemd_log"
set +e
invalid_mode_output=$(run_share_command unknown 2>&1)
invalid_mode_status=$?
set -e
((invalid_mode_status != 0)) || fail "unknown Share mode succeeds"
[[ ! -s $systemd_log ]] || fail "unknown Share mode launches LocalSend"
grep -Fq 'Usage: omarchy-qvos-share [clipboard|file|folder]' \
  <<<"$invalid_mode_output" ||
  fail "unknown Share mode usage"
pass "Share rejects unknown modes before launching LocalSend"

[[ -x $share_script ]] || fail "qvCORE Share component is not executable"
[[ -x $firewall_reconciler ]] ||
  fail "qvCORE Share inherited-firewall reconciler is not executable"
grep -Fqx '# localsend' "$root/qv/install/packaging/base.packages" ||
  fail "LocalSend is not disabled in the base package manifest"
grep -Fq 'omarchy-qvos-block-upstream-maintenance' \
  "$root/bin/omarchy-remove-preinstalls" ||
  fail "upstream preinstall cleanup is not guarded on qvOS"
grep -Eq 'ufw allow 53317/(udp|tcp)' "$root/install/first-run/firewall.sh" ||
  fail "inherited Omarchy firewall policy was rewritten"
grep -Fqx "\"\$OMARCHY_PATH/qv/core/share/reconcile-inherited-firewall\"" \
  "$root/qv/install/first-run/apply" ||
  fail "qvOS first-run does not reconcile inherited LocalSend ports"

rm -f "$test_root/.local/state/qvos/qvcore/share"
printf '%s\n' \
  '-A ufw-user-input -p tcp --dport 53317 -j ACCEPT' \
  '-A ufw-user-input -p udp --dport 53317 -j ACCEPT' \
  >"$firewall_rules_v4"
cp "$firewall_rules_v4" "$firewall_rules_v6"
: >"$action_log"
QVOS_TEST_ACTION_LOG="$action_log" \
  QVOS_SHARE_UFW_RULES_V4="$firewall_rules_v4" \
  QVOS_SHARE_UFW_RULES_V6="$firewall_rules_v6" \
  HOME="$test_root" \
  PATH="$test_bin:/usr/bin" \
  "$firewall_reconciler"
[[ ! -e $firewall_rules_v4 && ! -e $firewall_rules_v6 ]] ||
  fail "disabled Share leaves inherited LocalSend ports open"
grep -Fqx $'ufw\tdelete allow 53317/tcp' "$action_log" ||
  fail "inherited LocalSend TCP rule cleanup"
grep -Fqx $'ufw\tdelete allow 53317/udp' "$action_log" ||
  fail "inherited LocalSend UDP rule cleanup"

grep -Fqx 'ports=53317/tcp|53317/udp' "$root/qv/core/share/ufw.profile" ||
  fail "Share-owned UFW application profile"
if grep -Eq '(localsend[[:space:]]+--(help|version)|uwsm-app|systemctl.*localsend)' \
  "$share_script"; then
  fail "Share launches LocalSend during installation verification"
fi
if grep -Fq 'Nautilus integration' "$share_script"; then
  fail "Share still treats Nautilus as the qvOS integration"
fi
pass "Share stays optional, on demand, Thunar-owned, and firewall-scoped"
