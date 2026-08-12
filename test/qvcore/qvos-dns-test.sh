#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
setup_dns="$root/qvcore/network/setup-dns"
policy="$root/qvcore/network/dns-policy"
warp_policy="$root/qvcore/network/warp-policy"
installer="$root/qvcore/network/install"
test_root="$(mktemp -d)"
system_root="$test_root/system"
network_root="$system_root/etc/systemd/network"
resolved_root="$system_root/etc/systemd/resolved.conf.d"
test_bin="$test_root/bin"
action_log="$test_root/actions"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_policy() {
  QVOS_NETWORK_TESTING=1 \
    QVOS_NETWORK_SYSTEM_ROOT="$system_root" \
    "$policy" "$@"
}

install -d \
  "$system_root/etc/systemd" \
  "$system_root/run" \
  "$network_root" \
  "$resolved_root"
install -m 0644 /dev/stdin "$network_root/20-ethernet.network" <<'NETWORK'
[Match]
Name=en*

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100
NETWORK
install -m 0644 /dev/stdin "$network_root/20-wlan.network" <<'NETWORK'
[Match]
Name=wl*

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=600
NETWORK
network_snapshot=$(sha256sum "$network_root"/*.network)

run_policy validate Custom 1.1.1.1 2606:4700:4700::1111#cloudflare-dns.com
for invalid in \
  'not-an-address' \
  '1.1.1.1%wlan0' \
  '1.1.1.1#bad_name' \
  $'1.1.1.1\nFallbackDNS=8.8.8.8'; do
  if run_policy validate Custom "$invalid" >/dev/null 2>&1; then
    fail "invalid custom DNS accepted: $invalid"
  fi
done
if run_policy validate Custom >/dev/null 2>&1; then
  fail "empty custom DNS accepted"
fi
if run_policy validate Custom \
  1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 \
  9.9.9.9 149.112.112.112 208.67.222.222 208.67.220.220 \
  192.168.1.1 >/dev/null 2>&1; then
  fail "unbounded custom DNS list accepted"
fi
pass "custom DNS accepts only bounded literal addresses"

run_policy apply Cloudflare
resolved_policy="$resolved_root/80-qvos-dns.conf"
grep -Fqx '# Managed by qvOS DNS. Do not edit.' "$resolved_policy" ||
  fail "managed resolver header"
grep -Fqx \
  'DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com' \
  "$resolved_policy" || fail "Cloudflare resolver policy"
[[ $(find "$network_root" -path '*/80-qvos-dns.conf' -type f | wc -l) == "2" ]] ||
  fail "per-network DHCP DNS policy"
for dropin in "$network_root"/*.network.d/80-qvos-dns.conf; do
  grep -Fqx 'UseDNS=no' "$dropin" || fail "network DNS drop-in contents"
  [[ $(stat -c '%a' "$dropin") == "644" ]] || fail "network DNS drop-in mode"
done
[[ $(sha256sum "$network_root"/*.network) == "$network_snapshot" ]] ||
  fail "base network configuration was edited"
run_policy check Cloudflare
pass "static DNS uses atomic qvOS-owned drop-ins"

run_policy apply Custom 192.168.1.1 2001:4860:4860::8888#dns.google
grep -Fqx 'DNS=192.168.1.1 2001:4860:4860::8888#dns.google' \
  "$resolved_policy" || fail "custom resolver values"
grep -Fqx 'FallbackDNS=' "$resolved_policy" ||
  fail "custom DNS unexpectedly leaks to a fallback provider"
run_policy check Custom 192.168.1.1 2001:4860:4860::8888#dns.google
pass "custom DNS preserves the exact selected resolver set"

cp -a "$resolved_policy" "$test_root/resolved-policy-good"
printf 'modified\n' >>"$resolved_policy"
if run_policy apply Quad9 >/dev/null 2>&1; then
  fail "modified managed resolver policy was overwritten"
fi
grep -Fqx 'modified' "$resolved_policy" ||
  fail "modified managed resolver policy was not preserved"
install -m 0644 "$test_root/resolved-policy-good" "$resolved_policy"
pass "modified managed policy fails closed"

install -m 0644 /dev/stdin "$network_root/20-wlan.network.d/90-foreign.conf" <<'FOREIGN'
[DHCPv4]
UseRoutes=no
FOREIGN
run_policy apply DHCP
[[ ! -e $resolved_policy ]] || fail "DHCP resolver policy removal"
[[ -f $network_root/20-wlan.network.d/90-foreign.conf ]] ||
  fail "foreign network drop-in preservation"
if find "$network_root" -path '*/80-qvos-dns.conf' -print -quit | grep -q .; then
  fail "DHCP left qvOS DNS drop-ins"
fi
run_policy check DHCP
pass "DHCP removes only validated qvOS DNS policy"

foreign_dropin_root="$test_root/foreign-dropin-root"
install -d "$foreign_dropin_root"
ln -s "$foreign_dropin_root" "$network_root/20-ethernet.network.d"
if run_policy apply Cloudflare >/dev/null 2>&1; then
  fail "linked network drop-in directory was accepted"
fi
[[ ! -e $resolved_policy ]] ||
  fail "failed multi-file DNS transaction left resolver policy"
[[ -z $(find "$foreign_dropin_root" -mindepth 1 -print -quit) ]] ||
  fail "failed DNS transaction escaped through a linked directory"
unlink "$network_root/20-ethernet.network.d"
pass "failed multi-file DNS policy rolls back without following links"

install_root="$test_root/install-system"
install -d "$install_root"
QVOS_NETWORK_TESTING=1 QVOS_NETWORK_SYSTEM_ROOT="$install_root" \
  "$installer"
for helper_name in dns-policy warp-policy; do
  installed_helper="$install_root/usr/lib/qvos/network/$helper_name"
  cmp -s "$root/qvcore/network/$helper_name" "$installed_helper" ||
    fail "installed $helper_name helper contents"
  [[ $(stat -c '%a' "$installed_helper") == "755" ]] ||
    fail "installed $helper_name helper mode"
done
install_snapshot=$(
  find "$install_root/usr/lib/qvos/network" -type f \
    -printf '%f:%i:%T@\n' | sort
)
QVOS_NETWORK_TESTING=1 QVOS_NETWORK_SYSTEM_ROOT="$install_root" \
  "$installer"
[[ $(find "$install_root/usr/lib/qvos/network" -type f \
  -printf '%f:%i:%T@\n' | sort) == "$install_snapshot" ]] ||
  fail "current DNS helper was replaced"
pass "root network helper installation converges without churn"

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/qv-cmd-missing" <<'SCRIPT'
#!/bin/bash
[[ $1 == "warp-cli" && ${QVOS_TEST_WARP_MISSING:-0} == "1" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-pkg-aur-add" <<'SCRIPT'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ $1 == "is-active" ]]; then
  [[ ${QVOS_TEST_WARP_ACTIVE:-0} == "1" ]]
else
  exit 0
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/warp-policy" <<'SCRIPT'
#!/bin/bash
printf 'warp-policy\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/warp-cli" <<'SCRIPT'
#!/bin/bash
printf 'warp-cli\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ $* == *"registration show" ]]; then
  printf 'registration-secret-must-not-escape\n'
  [[ ${QVOS_TEST_WARP_REGISTERED:-0} == "1" ]]
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/networkctl" <<'SCRIPT'
#!/bin/bash
printf 'networkctl\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
case $1 in
choose) printf '%s\n' "${QVOS_TEST_GUM_CHOICE:-WARP}" ;;
confirm) [[ ${QVOS_TEST_GUM_CONFIRM:-1} == "1" ]] ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/policy-install" <<'SCRIPT'
#!/bin/bash
printf 'policy-install\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/dns-policy" <<'SCRIPT'
#!/bin/bash
printf 'policy\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ $1 == "validate" ]]; then
  exec "$QVOS_TEST_SOURCE_POLICY" "$@"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exec "$@"
SCRIPT

run_setup() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_SOURCE_POLICY="$policy" \
    QVOS_TEST_GUM_CHOICE="${QVOS_TEST_GUM_CHOICE:-WARP}" \
    QVOS_TEST_GUM_CONFIRM="${QVOS_TEST_GUM_CONFIRM:-1}" \
    QVOS_TEST_WARP_ACTIVE="${QVOS_TEST_WARP_ACTIVE:-0}" \
    QVOS_TEST_WARP_MISSING="${QVOS_TEST_WARP_MISSING:-0}" \
    QVOS_TEST_WARP_REGISTERED="${QVOS_TEST_WARP_REGISTERED:-0}" \
    QVOS_NETWORK_TESTING=1 \
    QVOS_NETWORK_POLICY_HELPER="$test_bin/dns-policy" \
    QVOS_NETWORK_WARP_POLICY_HELPER="$test_bin/warp-policy" \
    QVOS_NETWORK_INSTALL="$test_bin/policy-install" \
    QVOS_NETWORK_NETWORKCTL="$test_bin/networkctl" \
    QVOS_NETWORK_SYSTEMCTL="$test_bin/systemctl" \
    QVOS_NETWORK_SUDO="$test_bin/sudo" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$setup_dns" "$@"
}

: >"$action_log"
QVOS_TEST_WARP_MISSING=1 run_setup WARP >/dev/null
grep -Fqx $'package\tcloudflare-warp-nox-bin' "$action_log" ||
  fail "missing WARP package install"
policy_check_line=$(grep -nFx $'warp-policy\tcheck' "$action_log" | head -n 1 | cut -d: -f1)
enable_line=$(grep -nFx $'systemctl\tenable --now warp-svc.service' "$action_log" | cut -d: -f1)
((policy_check_line < enable_line)) || fail "WARP starts before privacy validation"
grep -Fqx $'gum\tconfirm Accept Cloudflare WARP terms and register this device?' \
  "$action_log" || fail "first WARP terms confirmation"
grep -Fqx $'warp-cli\t--accept-tos registration new' "$action_log" ||
  fail "first WARP registration"
grep -Fqx $'policy\tapply DHCP' "$action_log" || fail "WARP DHCP policy"
policy_line=$(grep -nFx $'policy\tapply DHCP' "$action_log" | cut -d: -f1)
connect_line=$(grep -nFx $'warp-cli\tconnect' "$action_log" | cut -d: -f1)
((policy_line < connect_line)) || fail "WARP connects before DHCP policy"
pass "WARP installs, registers, applies DHCP policy, and connects"

warp_root="$test_root/warp-system"
warp_action_log="$test_root/warp-actions"
install -d \
  "$warp_root/etc/systemd/system" \
  "$warp_root/usr/lib/systemd/system" \
  "$warp_root/var/lib/cloudflare-warp" \
  "$warp_root/var/log/cloudflare-warp"
install -m 0644 /dev/stdin \
  "$warp_root/usr/lib/systemd/system/warp-svc.service" <<'UNIT'
[Service]
ExecStart=/usr/bin/warp-svc
StateDirectory=cloudflare-warp
LogsDirectory=cloudflare-warp
UNIT
install -m 0755 /dev/stdin "$test_bin/warp-systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
case $1 in
is-active) [[ ${QVOS_TEST_WARP_ACTIVE:-0} == "1" ]] ;;
restart)
  if [[ ${QVOS_TEST_WARP_RESTART_FAIL_ONCE:-0} == "1" &&
    ! -e ${QVOS_TEST_WARP_FAILURE_MARKER:-} ]]; then
    : >"$QVOS_TEST_WARP_FAILURE_MARKER"
    exit 1
  fi
  ;;
show)
  printf '%s\n' \
    'StateDirectoryMode=0700' \
    'LogsDirectoryMode=0700' \
    'StandardOutput=null' \
    'StandardError=null'
  ;;
esac
SCRIPT
: >"$warp_action_log"
QVOS_TEST_ACTION_LOG="$warp_action_log" \
  QVOS_TEST_WARP_ACTIVE=1 \
  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$warp_root" \
  QVOS_NETWORK_SYSTEMCTL="$test_bin/warp-systemctl" \
  "$warp_policy" apply
warp_dropin="$warp_root/etc/systemd/system/warp-svc.service.d/80-qvos-privacy.conf"
grep -Fqx 'StateDirectoryMode=0700' "$warp_dropin" ||
  fail "WARP state privacy drop-in"
grep -Fqx 'LogsDirectoryMode=0700' "$warp_dropin" ||
  fail "WARP log privacy drop-in"
grep -Fqx 'StandardOutput=null' "$warp_dropin" ||
  fail "WARP journal output suppression"
grep -Fqx 'StandardError=null' "$warp_dropin" ||
  fail "WARP journal error suppression"
[[ $(stat -c '%a' "$warp_root/var/lib/cloudflare-warp") == "700" &&
  $(stat -c '%a' "$warp_root/var/log/cloudflare-warp") == "700" ]] ||
  fail "existing WARP directories remain exposed"
grep -Fqx $'systemctl\tdaemon-reload' "$warp_action_log" ||
  fail "WARP systemd policy reload"
grep -Fqx $'systemctl\trestart warp-svc.service' "$warp_action_log" ||
  fail "active WARP policy restart"
QVOS_TEST_ACTION_LOG="$warp_action_log" \
  QVOS_TEST_WARP_ACTIVE=1 \
  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$warp_root" \
  QVOS_NETWORK_SYSTEMCTL="$test_bin/warp-systemctl" \
  "$warp_policy" check
: >"$warp_action_log"
QVOS_TEST_ACTION_LOG="$warp_action_log" \
  QVOS_TEST_WARP_ACTIVE=1 \
  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$warp_root" \
  QVOS_NETWORK_SYSTEMCTL="$test_bin/warp-systemctl" \
  "$warp_policy" apply
if grep -Eq $'systemctl\t(daemon-reload|restart)' "$warp_action_log"; then
  fail "current WARP privacy policy restarted the service"
fi
printf 'modified\n' >>"$warp_dropin"
if QVOS_TEST_ACTION_LOG="$warp_action_log" \
  QVOS_TEST_WARP_ACTIVE=1 \
  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$warp_root" \
  QVOS_NETWORK_SYSTEMCTL="$test_bin/warp-systemctl" \
  "$warp_policy" apply >/dev/null 2>&1; then
  fail "modified WARP privacy policy was overwritten"
fi
grep -Fqx 'modified' "$warp_dropin" ||
  fail "modified WARP privacy policy was not preserved"

warp_rollback_root="$test_root/warp-rollback-system"
warp_rollback_log="$test_root/warp-rollback-actions"
warp_failure_marker="$test_root/warp-restart-failed"
install -d \
  "$warp_rollback_root/etc/systemd/system" \
  "$warp_rollback_root/usr/lib/systemd/system" \
  "$warp_rollback_root/var/lib/cloudflare-warp" \
  "$warp_rollback_root/var/log/cloudflare-warp"
install -m 0644 "$warp_root/usr/lib/systemd/system/warp-svc.service" \
  "$warp_rollback_root/usr/lib/systemd/system/warp-svc.service"
: >"$warp_rollback_log"
if QVOS_TEST_ACTION_LOG="$warp_rollback_log" \
  QVOS_TEST_WARP_ACTIVE=1 \
  QVOS_TEST_WARP_RESTART_FAIL_ONCE=1 \
  QVOS_TEST_WARP_FAILURE_MARKER="$warp_failure_marker" \
  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$warp_rollback_root" \
  QVOS_NETWORK_SYSTEMCTL="$test_bin/warp-systemctl" \
  "$warp_policy" apply >/dev/null 2>&1; then
  fail "failed WARP restart retained a successful policy status"
fi
[[ ! -e $warp_rollback_root/etc/systemd/system/warp-svc.service.d/80-qvos-privacy.conf ]] ||
  fail "failed WARP policy retained its new drop-in"
[[ $(stat -c '%a' "$warp_rollback_root/var/lib/cloudflare-warp") == "755" &&
  $(stat -c '%a' "$warp_rollback_root/var/log/cloudflare-warp") == "755" ]] ||
  fail "failed WARP policy retained partial directory modes"
[[ $(grep -Fxc $'systemctl\trestart warp-svc.service' "$warp_rollback_log") == "2" ]] ||
  fail "failed WARP policy did not restore the active service"
pass "WARP privacy policy is private, idempotent, and recoverable"

: >"$action_log"
warp_output=$(QVOS_TEST_WARP_REGISTERED=1 run_setup 2>/dev/null)
grep -Fqx \
  $'gum\tchoose --height 7 --header Select WARP or DNS provider WARP Cloudflare Quad9 DHCP Custom' \
  "$action_log" || fail "DNS selector choices"
[[ $warp_output != *"registration-secret-must-not-escape"* ]] ||
  fail "WARP registration secret output"
if grep -Fq $'package\t' "$action_log" || grep -Fq 'registration new' "$action_log"; then
  fail "configured WARP is reinstalled or reregistered"
fi
pass "existing WARP registration is reused without exposing credentials"

: >"$action_log"
if QVOS_TEST_GUM_CONFIRM=0 run_setup WARP >/dev/null 2>&1; then
  fail "declined WARP terms succeed"
fi
grep -Fqx $'systemctl\tdisable --now warp-svc.service' "$action_log" ||
  fail "declined WARP cleanup"
if grep -Fq $'policy\tapply' "$action_log" || grep -Fq $'warp-cli\tconnect' "$action_log"; then
  fail "declined WARP terms change DNS or connect"
fi
pass "declined WARP terms leave DNS unchanged and the service disabled"

: >"$action_log"
QVOS_TEST_WARP_ACTIVE=1 QVOS_TEST_WARP_REGISTERED=1 \
  run_setup Quad9 >/dev/null
grep -Fqx $'warp-cli\tdisconnect' "$action_log" || fail "static DNS disconnects WARP"
grep -Fqx $'policy\tapply Quad9' "$action_log" || fail "Quad9 policy application"
disconnect_line=$(grep -nFx $'warp-cli\tdisconnect' "$action_log" | cut -d: -f1)
apply_line=$(grep -nFx $'policy\tapply Quad9' "$action_log" | cut -d: -f1)
((disconnect_line < apply_line)) || fail "static DNS applies before WARP disconnect"
pass "static DNS deactivates WARP before applying policy"

: >"$action_log"
if QVOS_TEST_WARP_ACTIVE=1 run_setup Custom \
  $'1.1.1.1\nDNS=8.8.8.8' >/dev/null 2>&1; then
  fail "configuration-injection custom DNS accepted"
fi
if grep -Fq $'warp-cli\tdisconnect' "$action_log" ||
  grep -Fq $'policy\tapply' "$action_log"; then
  fail "invalid custom DNS changed network state"
fi
pass "invalid custom DNS fails before network mutation"

: >"$action_log"
run_setup Custom 192.168.1.1 2606:4700:4700::1111 >/dev/null
grep -Fqx $'policy\tapply Custom 192.168.1.1 2606:4700:4700::1111' \
  "$action_log" || fail "custom DNS argument preservation"
if run_setup Unknown >/dev/null 2>&1; then
  fail "unknown provider succeeds"
fi
pass "custom and unknown provider routing is strict"

# shellcheck disable=SC2016
grep -Fq 'exec "$QVOS_PATH/qvcore/network/setup-dns" "$@"' \
  "$root/bin/qv-setup-dns" || fail "native DNS adapter"
# shellcheck disable=SC2016
grep -Fq 'exec "$QVOS_PATH/qvcore/network/setup-dns" "$@"' \
  "$root/bin/omarchy-setup-dns" || fail "compatibility DNS adapter"
[[ ! -e $root/bin/omarchy-qvos-setup-dns ]] || fail "obsolete DNS adapter"
"$root/qvcore/network/check" >/dev/null
printf 'ok - qvOS DNS policy is validated, isolated, and singularly owned\n'
