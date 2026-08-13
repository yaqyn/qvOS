#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
owner="$root/qvcore/install/printing-policy"
source_policy="$root/qvcore/install/system/printing-resolver.conf"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
state_root="$test_root/state"
action_log="$test_root/actions.log"
declare -a units=(
  cups.service
  cups.socket
  cups.path
  cups-browsed.service
  avahi-daemon.service
  avahi-daemon.socket
  systemd-resolved.service
)

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$state_root/enabled" "$state_root/active"
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

state=${QVOS_PRINTING_TEST_STATE:?}
log=${QVOS_PRINTING_TEST_LOG:?}
action=$1
shift
printf '%s|%s\n' "$action" "$*" >>"$log"
case $action in
is-enabled)
  cat "$state/enabled/$1"
  ;;
is-active)
  [[ ${1:-} == "--quiet" ]] && shift
  [[ $(<"$state/active/$1") == "active" ]]
  ;;
enable | disable | start | stop | restart)
  for unit in "$@"; do
    [[ ${QVOS_PRINTING_TEST_FAIL:-} != "$action:$unit" ]] || exit 1
  done
  case $action in
  enable | disable)
    value=disabled
    [[ $action == "enable" ]] && value=enabled
    for unit in "$@"; do printf '%s\n' "$value" >"$state/enabled/$unit"; done
    ;;
  start | stop)
    value=inactive
    [[ $action == "start" ]] && value=active
    for unit in "$@"; do printf '%s\n' "$value" >"$state/active/$unit"; done
    ;;
  restart)
    for unit in "$@"; do printf 'active\n' >"$state/active/$unit"; done
    ;;
  esac
  ;;
*) exit 64 ;;
esac
SCRIPT

new_fixture() {
  local name=$1
  local fixture="$test_root/$name"
  local unit

  install -d "$fixture/usr/lib/systemd/system"
  for unit in "${units[@]}"; do
    install -m 0644 /dev/null "$fixture/usr/lib/systemd/system/$unit"
  done
  printf '%s\n' "$fixture"
}

reset_state() {
  local enabled=${1:-enabled}
  local active=${2:-active}
  local unit

  for unit in "${units[@]}"; do
    printf '%s\n' "$enabled" >"$state_root/enabled/$unit"
    printf '%s\n' "$active" >"$state_root/active/$unit"
  done
  : >"$action_log"
}

run_owner() {
  local fixture=$1
  shift

  QVOS_PATH="$root" \
  QVOS_PRINTING_TESTING=1 \
  QVOS_PRINTING_SYSTEM_ROOT="$fixture" \
  QVOS_PRINTING_SYSTEMCTL="$test_bin/systemctl" \
  QVOS_PRINTING_TEST_STATE="$state_root" \
  QVOS_PRINTING_TEST_LOG="$action_log" \
    "$owner" "$@"
}

fixture=$(new_fixture success)
reset_state
run_owner "$fixture"
policy="$fixture/etc/systemd/resolved.conf.d/50-qvos-local-discovery.conf"
cmp -s "$source_policy" "$policy" || fail "native resolver policy"
[[ $(stat -c '%a' -- "$policy") == "644" ]] || fail "resolver policy mode"
for unit in cups.service cups-browsed.service avahi-daemon.service avahi-daemon.socket; do
  [[ $(<"$state_root/enabled/$unit") == "disabled" ]] ||
    fail "disabled printing unit: $unit"
done
for unit in cups.socket cups.path; do
  [[ $(<"$state_root/enabled/$unit") == "enabled" &&
    $(<"$state_root/active/$unit") == "active" ]] ||
    fail "on-demand CUPS unit: $unit"
done
for unit in cups-browsed.service avahi-daemon.service avahi-daemon.socket; do
  [[ $(<"$state_root/active/$unit") == "inactive" ]] ||
    fail "stopped discovery unit: $unit"
done
policy_state=$(stat -c '%a|%i|%y' "$policy")
: >"$action_log"
run_owner "$fixture"
[[ $(stat -c '%a|%i|%y' "$policy") == "$policy_state" ]] ||
  fail "idempotent resolver policy"
if rg -q '^(enable|disable|start|stop|restart)\|' "$action_log"; then
  fail "idempotent printing policy mutated system state"
fi

rollback_fixture=$(new_fixture rollback)
reset_state
enabled_before=$(sha256sum "$state_root/enabled/"*)
active_before=$(sha256sum "$state_root/active/"*)
if QVOS_PRINTING_TEST_FAIL='enable:cups.socket' run_owner "$rollback_fixture" \
  >/dev/null 2>&1; then
  fail "failed CUPS activation reported success"
fi
[[ $(sha256sum "$state_root/enabled/"*) == "$enabled_before" &&
  $(sha256sum "$state_root/active/"*) == "$active_before" &&
  ! -e $rollback_fixture/etc/systemd/resolved.conf.d/50-qvos-local-discovery.conf ]] ||
  fail "printing policy rollback"

modified_fixture=$(new_fixture modified)
reset_state disabled inactive
install -D -m 0644 /dev/stdin \
  "$modified_fixture/etc/systemd/resolved.conf.d/50-qvos-local-discovery.conf" <<'CONF'
[Resolve]
MulticastDNS=yes
LLMNR=yes
CONF
modified_before=$(sha256sum \
  "$modified_fixture/etc/systemd/resolved.conf.d/50-qvos-local-discovery.conf")
if run_owner "$modified_fixture" >/dev/null 2>&1; then
  fail "modified qvOS resolver policy accepted"
fi
[[ $(sha256sum \
  "$modified_fixture/etc/systemd/resolved.conf.d/50-qvos-local-discovery.conf") == \
  "$modified_before" ]] || fail "modified resolver policy preservation"

chroot_fixture=$(new_fixture chroot)
reset_state disabled inactive
QVOS_CHROOT_INSTALL=1 run_owner "$chroot_fixture"
cmp -s "$source_policy" \
  "$chroot_fixture/etc/systemd/resolved.conf.d/50-qvos-local-discovery.conf" ||
  fail "target-chroot resolver policy"
for unit in "${units[@]}"; do
  [[ $(<"$state_root/active/$unit") == "inactive" ]] ||
    fail "target chroot changed build-host unit state: $unit"
done
if rg -q '^(is-active|start|stop|restart)\|' "$action_log"; then
  fail "target chroot queried or changed live service activity"
fi

# shellcheck disable=SC2016
scoped_enabled_query='query_systemctl is-enabled'
# shellcheck disable=SC2016
scoped_active_query='query_systemctl is-active --quiet'
# shellcheck disable=SC2016
chroot_unit_inventory='[[ -n $system_root || ${QVOS_CHROOT_INSTALL:-} == "1" ]]'
grep -Fq "$scoped_enabled_query" "$owner" ||
  fail "scope-aware system unit enablement query"
grep -Fq "$scoped_active_query" "$owner" ||
  fail "scope-aware system unit activity query"
grep -Fq "$chroot_unit_inventory" "$owner" ||
  fail "target-chroot unit inventory avoids the unavailable system manager"
grep -Fq '/usr/bin/sudo -v || fail "root authorization was not granted"' "$owner" ||
  fail "visible live authorization"
grep -Fq '/usr/bin/sudo -n /usr/bin/true ||' "$owner" ||
  fail "noninteractive target authorization"
current_line=$(grep -nF 'policy_is_current && exit 0' "$owner" | cut -d: -f1)
authorize_line=$(grep -nFx 'authorize_root' "$owner" | cut -d: -f1)
# shellcheck disable=SC2016
disable_line=$(grep -nF 'as_root "$systemctl_command" disable' "$owner" |
  awk -F: 'NR == 1 { print $1; exit }')
[[ -n $current_line && -n $authorize_line && -n $disable_line ]] ||
  fail "printing authorization order inventory"
(( current_line < authorize_line && authorize_line < disable_line )) ||
  fail "printing policy prompts only before required mutations"

printf 'ok - qvOS printing is on demand without unsolicited network discovery\n'
