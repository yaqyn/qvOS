#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
installed="$test_root/localsend"
log="$test_root/actions.log"
thunar_config="$test_root/home/.config/Thunar/uca.xml"
firewall_profile="$test_root/firewall/qvos-qvcore-share"
firewall_rules_v4="$test_root/firewall/user.rules"
firewall_rules_v6="$test_root/firewall/user6.rules"
firewall_defaults="$test_root/firewall/ufw"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$(dirname -- "$thunar_config")" "$(dirname -- "$firewall_defaults")"
install -m 0600 /dev/stdin "$thunar_config" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<actions>
  <action>
    <icon>test</icon>
    <name>User Action</name>
    <unique-id>user-action</unique-id>
    <command>keep</command>
    <description>Keep me.</description>
    <patterns>*</patterns>
    <directories/>
  </action>
</actions>
XML
printf 'IPV6=yes\n' >"$firewall_defaults"

for name in omarchy-pkg-present omarchy-pkg-missing omarchy-pkg-add \
  omarchy-pkg-drop omarchy-cmd-present sudo ufw pacman gum; do
  install -m 0755 /dev/stdin "$test_bin/$name" <<'SCRIPT'
#!/bin/bash
case ${0##*/} in
omarchy-pkg-present) [[ -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-pkg-missing) [[ ! -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-pkg-add) install -m 0644 /dev/null "$QVOS_TEST_INSTALLED"; echo add >>"$QVOS_TEST_LOG" ;;
omarchy-pkg-drop) rm -f "$QVOS_TEST_INSTALLED"; echo drop >>"$QVOS_TEST_LOG" ;;
omarchy-cmd-present)
  case $1 in
  localsend) [[ -f $QVOS_TEST_INSTALLED ]] ;;
  *) exit 0 ;;
  esac
  ;;
sudo) exec "$@" ;;
ufw)
  printf 'ufw\t%s\n' "$*" >>"$QVOS_TEST_LOG"
  case $* in
  "allow qvCORE Share")
    printf '%s\n' \
      '-A ufw-user-input -p tcp --dport 53317 -j ACCEPT' \
      '-A ufw-user-input -p udp --dport 53317 -j ACCEPT' \
      >"$QVOS_SHARE_UFW_RULES_V4"
    cp "$QVOS_SHARE_UFW_RULES_V4" "$QVOS_SHARE_UFW_RULES_V6"
    ;;
  "delete allow qvCORE Share" | "delete allow 53317/tcp" | "delete allow 53317/udp")
    rm -f "$QVOS_SHARE_UFW_RULES_V4" "$QVOS_SHARE_UFW_RULES_V6"
    ;;
  esac
  ;;
pacman | gum) exit 0 ;;
esac
SCRIPT
done

run_share() {
  HOME="$test_root/home" \
    PATH="$test_bin:/usr/bin" \
    QVOS_THUNAR_CONFIG="$thunar_config" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_LOG="$log" \
    QVOS_SHARE_UFW_DEFAULTS="$firewall_defaults" \
    QVOS_SHARE_UFW_PROFILE_TARGET="$firewall_profile" \
    QVOS_SHARE_UFW_RULES_V4="$firewall_rules_v4" \
    QVOS_SHARE_UFW_RULES_V6="$firewall_rules_v6" \
    "$root/qv/core/share.sh" "$@"
}

install -m 0644 /dev/null "$installed"
run_share install >/dev/null
[[ ! -s $log || $(grep -c '^add$' "$log" || true) == "0" ]] ||
  fail "Share reinstalls compatible LocalSend"
[[ -f $test_root/home/.local/state/qvos/qvcore/share ]] ||
  fail "Share enrollment"
[[ -x $test_root/home/.local/share/qvos/thunar/share ]] ||
  fail "Share helper installation"
[[ -f $firewall_profile ]] || fail "Share firewall profile"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-localsend-share'])" "$thunar_config") == "1" ]] ||
  fail "Share Thunar action"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='user-action'])" "$thunar_config") == "1" ]] ||
  fail "Share preserves unrelated Thunar action"

run_share remove --yes >/dev/null
[[ ! -f $installed ]] || fail "Share package removal"
[[ ! -e $test_root/home/.local/state/qvos/qvcore/share ]] ||
  fail "Share enrollment removal"
[[ ! -e $test_root/home/.local/share/qvos/thunar/share ]] ||
  fail "Share helper removal"
[[ ! -e $firewall_profile ]] || fail "Share firewall removal"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-localsend-share'])" "$thunar_config") == "0" ]] ||
  fail "Share Thunar action removal"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='user-action'])" "$thunar_config") == "1" ]] ||
  fail "Share removal preserves user action"

printf 'ok - Share reuses LocalSend and owns its complete integration lifecycle\n'
