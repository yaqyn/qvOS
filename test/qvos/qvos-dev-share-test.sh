#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
dev_share="$root/qv/security/dev-share"
firewall_helper="$root/qv/security/dev-share-firewall"
adapter="$root/bin/omarchy-qvos-dev-share"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
fixture="$test_root/fixture"
project="$test_root/project"
net_root="$test_root/sys/class/net"
action_log="$test_root/actions.log"
test_token=aaaaaaaaaaaaaaaa

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$fixture" \
  "$project/supabase" \
  "$net_root/enp8s0"
install -m 0755 /dev/null "$fixture/root-helper"
install -m 0644 /dev/stdin "$project/supabase/config.toml" <<'CONFIG'
project_id = "test"

[api]
enabled = true
port = 54321

[db]
port = 54322

[studio]
port = 54323

[inbucket]
port = 54324

[analytics]
port = 54327
CONFIG

install -m 0755 /dev/stdin "$test_bin/ip" <<'SCRIPT'
#!/bin/bash
if [[ ${QVOS_TEST_PUBLIC_IP:-0} == "1" ]]; then
  address=203.0.113.10
else
  address=192.168.100.164
fi
case $* in
"-4 route show table main default")
  printf 'default via 192.168.100.1 dev enp8s0 proto dhcp src %s metric 100\n' "$address"
  ;;
"-o -4 address show dev enp8s0 scope global")
  printf '2: enp8s0 inet %s/24 brd 192.168.100.255 scope global enp8s0\n' "$address"
  ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/ss" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
[[ $* =~ sport[[:space:]]=[[:space:]]:([0-9]+) ]]
port=${BASH_REMATCH[1]}
if [[ -e $QVOS_TEST_FIXTURE/missing-$port ]]; then
  exit 0
fi
if [[ -e $QVOS_TEST_FIXTURE/wildcard-$port ]]; then
  printf 'LISTEN 0 4096 0.0.0.0:%s 0.0.0.0:*\n' "$port"
  exit 0
fi
printf 'LISTEN 0 4096 127.0.0.1:%s 0.0.0.0:*\n' "$port"
if [[ -e $QVOS_TEST_FIXTURE/other-interface-$port ]]; then
  printf 'LISTEN 0 4096 192.168.50.10:%s 0.0.0.0:*\n' "$port"
fi
if [[ -e $QVOS_TEST_FIXTURE/proxy-$port ]]; then
  printf 'LISTEN 0 4096 192.168.100.164:%s 0.0.0.0:*\n' "$port"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemd-run" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
printf 'systemd-run\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
for argument in "$@"; do
  if [[ $argument == TCP4-LISTEN:* ]]; then
    port=${argument#TCP4-LISTEN:}
    port=${port%%,*}
    touch "$QVOS_TEST_FIXTURE/proxy-$port"
  fi
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
case $* in
*" show "*)
  unit=${!#}
  port=${unit%.service}
  port=${port##*-}
  printf '%s\n' "$port"
  ;;
*" is-active "*) exit 1 ;;
*" stop "*)
  unit=${!#}
  port=${unit%.service}
  port=${port##*-}
  rm -f "$QVOS_TEST_FIXTURE/proxy-$port"
  printf 'systemctl-stop\t%s\n' "$unit" >>"$QVOS_TEST_ACTION_LOG"
  ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "-n" && ${2:-} == "true" ]] && exit 1
exit 99
SCRIPT

install -m 0755 /dev/stdin "$test_bin/pkexec" <<'SCRIPT'
#!/bin/bash
printf 'pkexec\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

run_share() {
  (
    cd "$project"
    DISPLAY=:1 \
      QVOS_DEV_SHARE_TESTING=1 \
      QVOS_DEV_SHARE_ROOT_HELPER="$fixture/root-helper" \
      QVOS_DEV_SHARE_IP="$test_bin/ip" \
      QVOS_DEV_SHARE_SS="$test_bin/ss" \
      QVOS_DEV_SHARE_SYSTEMD_RUN="$test_bin/systemd-run" \
      QVOS_DEV_SHARE_SYSTEMCTL="$test_bin/systemctl" \
      QVOS_DEV_SHARE_SUDO="$test_bin/sudo" \
      QVOS_DEV_SHARE_PKEXEC="$test_bin/pkexec" \
      QVOS_DEV_SHARE_NET_ROOT="$net_root" \
      QVOS_DEV_SHARE_TOKEN="$test_token" \
      QVOS_TEST_ACTION_LOG="$action_log" \
      QVOS_TEST_FIXTURE="$fixture" \
      "$dev_share" "$@"
  )
}

share_output=$(run_share 3000 --supabase --duration 1m)
grep -Fq 'LAN preview: http://192.168.100.164:3000' <<<"$share_output" ||
  fail "frontend LAN preview address"
grep -Fq 'Supabase API: http://192.168.100.164:54321' <<<"$share_output" ||
  fail "Supabase API LAN preview address"
grep -Fq 'Only enp8s0 clients from 192.168.100.164/24 can connect.' \
  <<<"$share_output" ||
  fail "LAN preview interface and subnet"
grep -Fq 'TCP4-LISTEN:3000,bind=192.168.100.164,reuseaddr,fork' \
  "$action_log" ||
  fail "frontend localhost proxy"
grep -Fq 'TCP4-LISTEN:54321,bind=192.168.100.164,reuseaddr,fork' \
  "$action_log" ||
  fail "Supabase API localhost proxy"
if grep -Eq '54322|54323|54324|54327' "$action_log"; then
  fail "Supabase database or administration port exposed"
fi
grep -Eq \
  $'^pkexec\t.* open aaaaaaaaaaaaaaaa [0-9]+ enp8s0 192\\.168\\.100\\.164/24 192\\.168\\.100\\.164 1m 3000:3000 54321:54321$' \
  "$action_log" ||
  fail "subnet-scoped firewall authorization"
grep -Fq $'systemctl-stop\tqvos-dev-share-aaaaaaaaaaaaaaaa-3000.service' \
  "$action_log" ||
  fail "frontend proxy cleanup"
grep -Fq $'systemctl-stop\tqvos-dev-share-aaaaaaaaaaaaaaaa-54321.service' \
  "$action_log" ||
  fail "Supabase proxy cleanup"

touch "$fixture/wildcard-3000"
if run_share 3000 >/dev/null 2>&1; then
  fail "already-exposed frontend accepted"
fi
rm -f "$fixture/wildcard-3000"

touch "$fixture/other-interface-3000"
if run_share 3000 >/dev/null 2>&1; then
  fail "frontend exposed on another interface accepted"
fi
rm -f "$fixture/other-interface-3000"

touch "$fixture/missing-3000"
if run_share 3000 >/dev/null 2>&1; then
  fail "missing frontend listener accepted"
fi
rm -f "$fixture/missing-3000"

if run_share 3000 --duration 9h >/dev/null 2>&1; then
  fail "unbounded LAN preview duration accepted"
fi
if QVOS_TEST_PUBLIC_IP=1 run_share 3000 >/dev/null 2>&1; then
  fail "public interface accepted as LAN preview"
fi

install -m 0755 /dev/stdin "$test_bin/ufw" <<'SCRIPT'
#!/bin/bash
printf 'Status: active\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/iptables" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
printf 'iptables\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
port=
previous=
for argument in "$@"; do
  if [[ $previous == "--dport" ]]; then
    port=$argument
    break
  fi
  previous=$argument
done
case " $* " in
*" -n -L ufw-user-input "*) exit 0 ;;
*" -C ufw-user-input "*)
  [[ -n $port && -e $QVOS_TEST_FIXTURE/rule-$port ]]
  ;;
*" -I ufw-user-input "*)
  touch "$QVOS_TEST_FIXTURE/rule-$port"
  ;;
*" -D ufw-user-input "*)
  rm -f "$QVOS_TEST_FIXTURE/rule-$port"
  ;;
*) exit 1 ;;
esac
SCRIPT

proxy_pid=13000
proxy_proc="$fixture/proc/$proxy_pid"
install -d "$proxy_proc"
install -m 0644 /dev/stdin "$proxy_proc/status" <<EOF
Name:	socat
Uid:	$(id -u)	$(id -u)	$(id -u)	$(id -u)
EOF
ln -s /usr/bin/socat1 "$proxy_proc/exe"
printf '/usr/bin/socat\0TCP4-LISTEN:3000,bind=192.168.100.164,reuseaddr,fork\0TCP4:127.0.0.1:3000\0' \
  >"$proxy_proc/cmdline"
touch "$fixture/proxy-3000"

api_proxy_pid=54321
api_proxy_proc="$fixture/proc/$api_proxy_pid"
install -d "$api_proxy_proc"
install -m 0644 /dev/stdin "$api_proxy_proc/status" <<EOF
Name:	socat
Uid:	$(id -u)	$(id -u)	$(id -u)	$(id -u)
EOF
ln -s /usr/bin/socat1 "$api_proxy_proc/exe"
printf '/usr/bin/socat\0TCP4-LISTEN:54321,bind=192.168.100.164,reuseaddr,fork\0TCP4:127.0.0.1:54321\0' \
  >"$api_proxy_proc/cmdline"
touch "$fixture/proxy-54321"

helper_environment=(
  QVOS_DEV_SHARE_TESTING=1
  QVOS_DEV_SHARE_IP="$test_bin/ip"
  QVOS_DEV_SHARE_IPTABLES="$test_bin/iptables"
  QVOS_DEV_SHARE_SS="$test_bin/ss"
  QVOS_DEV_SHARE_SYSTEMD_RUN="$test_bin/systemd-run"
  QVOS_DEV_SHARE_UFW="$test_bin/ufw"
  QVOS_DEV_SHARE_ROOT_HELPER="$firewall_helper"
  QVOS_DEV_SHARE_PROC_ROOT="$fixture/proc"
  QVOS_DEV_SHARE_POLL_SECONDS=0.01
  QVOS_DEV_SHARE_SOCAT_EXECUTABLE=/usr/bin/socat1
  QVOS_TEST_ACTION_LOG="$action_log"
  QVOS_TEST_FIXTURE="$fixture"
)

env "${helper_environment[@]}" \
  "$firewall_helper" open \
  fedcba9876543210 "$(id -u)" enp8s0 \
  192.168.100.164/24 192.168.100.164 1m \
  3000:$proxy_pid 54321:$api_proxy_pid
[[ -e $fixture/rule-3000 && -e $fixture/rule-54321 ]] ||
  fail "runtime LAN preview firewall rules"
grep -Fq -- \
  '--comment qvos-dev-share:'"$(id -u)"':fedcba9876543210 -j ACCEPT' \
  "$action_log" ||
  fail "firewall rule has a unique qvOS owner"
grep -Fq -- \
  '-i enp8s0 -p tcp -s 192.168.100.164/24 -d 192.168.100.164 --dport 3000' \
  "$action_log" ||
  fail "firewall rule is interface and subnet scoped"
grep -Fq \
  'monitor fedcba9876543210 '"$(id -u)"' enp8s0 192.168.100.164/24 192.168.100.164 1m 3000:13000 54321:54321' \
  "$action_log" ||
  fail "process-bound firewall monitor"

env "${helper_environment[@]}" \
  "$firewall_helper" monitor \
  fedcba9876543210 "$(id -u)" enp8s0 \
  192.168.100.164/24 192.168.100.164 1m \
  3000:$proxy_pid 54321:$api_proxy_pid &
monitor_pid=$!
sleep 0.05
rm -rf -- "$proxy_proc"
sleep 0.05
[[ ! -e $fixture/rule-3000 ]] ||
  fail "frontend firewall rule survives its proxy"
[[ -e $fixture/rule-54321 ]] ||
  fail "live API firewall rule removed with the frontend"
rm -rf -- "$api_proxy_proc"
wait "$monitor_pid"
[[ ! -e $fixture/rule-3000 && ! -e $fixture/rule-54321 ]] ||
  fail "firewall rules survive their proxies"

touch "$fixture/rule-3000"
if env "${helper_environment[@]}" \
  "$firewall_helper" monitor \
  fedcba9876543210 "$(id -u)" enp8s0 \
  192.168.100.164/24 192.168.100.164 1m 3000:$proxy_pid \
  >/dev/null 2>&1; then
  fail "firewall monitor accepted a vanished proxy"
fi
[[ ! -e $fixture/rule-3000 ]] ||
  fail "firewall rule survives monitor validation failure"

if env "${helper_environment[@]}" \
  "$firewall_helper" open \
  aaaaaaaaaaaaaaaa "$(id -u)" enp8s0 \
  203.0.113.10/24 203.0.113.10 1m 3000:$proxy_pid \
  >/dev/null 2>&1; then
  fail "firewall helper accepted a public network"
fi

# shellcheck disable=SC2016
grep -Fq 'exec "$OMARCHY_PATH/qv/security/dev-share" "$@"' "$adapter" ||
  fail "public command is a thin security-owner adapter"
grep -Fq '# omarchy:hidden=true' "$adapter" ||
  fail "advanced LAN preview stays out of the default command surface"

printf 'ok - LAN preview is explicit, subnet-scoped, process-bound, and self-cleaning\n'
