#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
command_path="$root/qv/network/setup-dns"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
action_log="$test_root/actions"

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

install -d "$test_bin"

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
[[ $1 == "warp-cli" && ${QVOS_TEST_WARP_MISSING:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-aur-add" <<'SCRIPT'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
[[ $1 == "is-active" && ${QVOS_TEST_WARP_ACTIVE:-0} == "1" ]]
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

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ $1 == "tee" ]]; then
  while IFS= read -r line; do
    printf 'dns-config\t%s\n' "$line" >>"$QVOS_TEST_ACTION_LOG"
  done
fi
SCRIPT

run_setup() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_GUM_CHOICE="${QVOS_TEST_GUM_CHOICE:-WARP}" \
    QVOS_TEST_GUM_CONFIRM="${QVOS_TEST_GUM_CONFIRM:-1}" \
    QVOS_TEST_WARP_ACTIVE="${QVOS_TEST_WARP_ACTIVE:-0}" \
    QVOS_TEST_WARP_MISSING="${QVOS_TEST_WARP_MISSING:-0}" \
    QVOS_TEST_WARP_REGISTERED="${QVOS_TEST_WARP_REGISTERED:-0}" \
    PATH="$test_bin:/usr/bin" \
    "$command_path" "$@"
}

: >"$action_log"
QVOS_TEST_WARP_MISSING=1 run_setup WARP >/dev/null
grep -Fqx $'package\tcloudflare-warp-nox-bin' "$action_log" || fail "missing WARP package install"
grep -Fqx $'gum\tconfirm Accept Cloudflare WARP terms and register this device?' "$action_log" || fail "first WARP terms confirmation"
grep -Fqx $'warp-cli\t--accept-tos registration new' "$action_log" || fail "first WARP registration"
grep -Fqx $'warp-cli\tmode warp' "$action_log" || fail "full WARP mode"
grep -Fqx $'dns-config\tFallbackDNS=' "$action_log" || fail "WARP resets DNS to DHCP"
grep -Fqx $'warp-cli\tconnect' "$action_log" || fail "WARP connection"
dhcp_line="$(grep -nFx $'dns-config\tFallbackDNS=' "$action_log" | cut -d: -f1)"
connect_line="$(grep -nFx $'warp-cli\tconnect' "$action_log" | cut -d: -f1)"
((dhcp_line < connect_line)) || fail "WARP connects before the DHCP reset"
if grep -Fq $'warp-cli\tdisconnect' "$action_log"; then
  fail "WARP activation disconnects itself"
fi
pass "WARP installs, registers, resets DNS, and connects"

: >"$action_log"
warp_output="$(QVOS_TEST_WARP_REGISTERED=1 run_setup)"
grep -Fqx $'gum\tchoose --height 7 --header Select WARP or DNS provider WARP Cloudflare Quad9 None Custom' "$action_log" || fail "WARP selector option"
if grep -Fq $'package\t' "$action_log" || grep -Fq $'registration new' "$action_log"; then
  fail "configured WARP is reinstalled or reregistered"
fi
[[ $warp_output != *"registration-secret-must-not-escape"* ]] || fail "WARP registration secret output"
grep -Fqx $'warp-cli\tconnect' "$action_log" || fail "registered WARP reconnect"
pass "existing WARP registration is reused without exposing credentials"

: >"$action_log"
if QVOS_TEST_GUM_CONFIRM=0 run_setup WARP >/dev/null 2>&1; then
  fail "declined WARP terms succeed"
fi
grep -Fqx $'sudo\tsystemctl disable --now warp-svc.service' "$action_log" || fail "declined WARP cleanup"
if grep -Fq $'registration new' "$action_log" || grep -Fq $'warp-cli\tconnect' "$action_log"; then
  fail "declined WARP terms register or connect"
fi
pass "declined WARP terms leave the service disabled"

: >"$action_log"
QVOS_TEST_WARP_ACTIVE=1 QVOS_TEST_WARP_REGISTERED=1 run_setup Quad9 >/dev/null
grep -Fqx $'warp-cli\tdisconnect' "$action_log" || fail "DNS selection disconnects WARP"
grep -Fqx $'sudo\tsystemctl disable --now warp-svc.service' "$action_log" || fail "DNS selection disables WARP"
grep -Fqx $'dns-config\tDNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net' "$action_log" || fail "Quad9 configuration"
disconnect_line="$(grep -nFx $'warp-cli\tdisconnect' "$action_log" | cut -d: -f1)"
dns_line="$(grep -nF $'dns-config\tDNS=9.9.9.9' "$action_log" | cut -d: -f1)"
((disconnect_line < dns_line)) || fail "DNS is applied before WARP disconnects"
pass "DNS selection deactivates WARP before applying DNS"

: >"$action_log"
QVOS_TEST_WARP_MISSING=1 run_setup DHCP >/dev/null
if grep -Fq $'warp-cli\t' "$action_log" || grep -Fq 'warp-svc.service' "$action_log"; then
  fail "DHCP touches missing WARP"
fi
grep -Fqx $'dns-config\tFallbackDNS=' "$action_log" || fail "DHCP configuration"
pass "DHCP remains independent when WARP is absent"

: >"$action_log"
if printf '\n' | QVOS_TEST_WARP_ACTIVE=1 run_setup Custom >/dev/null 2>&1; then
  fail "empty custom DNS succeeds"
fi
[[ ! -s $action_log ]] || fail "cancelled custom DNS changes network state"
pass "invalid custom DNS leaves the current network untouched"

: >"$action_log"
if run_setup Unknown >/dev/null 2>&1; then
  fail "unknown provider succeeds"
fi
[[ ! -s $action_log ]] || fail "unknown provider changes network state"
pass "unknown providers fail without side effects"
