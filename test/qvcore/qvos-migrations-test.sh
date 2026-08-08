#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$root/qvcore/migrations/run"
creator="$root/qvcore/migrations/add"
test_root="$(mktemp -d)"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

make_home() {
  local home=$1

  install -d -m 0700 "$home" "$home/run"
}

source_root="$test_root/source"
home="$test_root/home"
log="$test_root/migrations.log"
install -d "$source_root/qvcore/migrations" "$source_root/qvcore/install"
make_home "$home"
install -d "$home/.local/state/omarchy/migrations/skipped"
for legacy_marker in \
  "$home/.local/state/omarchy/migrations/100.sh" \
  "$home/.local/state/omarchy/migrations/099.sh" \
  "$home/.local/state/omarchy/migrations/097_historical_name.sh" \
  "$home/.local/state/omarchy/migrations/skipped/098.sh"; do
  install -m 0644 /dev/null "$legacy_marker"
done
install -m 0644 /dev/stdin "$source_root/qvcore/migrations/100.sh" <<'SCRIPT'
printf '100\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
install -m 0644 /dev/stdin "$source_root/qvcore/migrations/101.sh" <<'SCRIPT'
printf '101\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
chmod 0644 "$source_root/qvcore/migrations"/*.sh

HOME="$home" \
  XDG_RUNTIME_DIR="$home/run" \
  QVOS_PATH="$source_root" \
  QVOS_TEST_MIGRATION_LOG="$log" \
  "$runner" >/dev/null
[[ $(<"$log") == "101" ]] ||
  fail "exact applied legacy marker was not adopted"
state_root="$home/.local/state/qvos/migrations"
for marker in 100.sh 101.sh; do
  [[ -f $state_root/$marker && ! -s $state_root/$marker ]] ||
    fail "native migration marker missing: $marker"
  [[ $(stat -c '%a' "$state_root/$marker") == "600" ]] ||
    fail "native migration marker is not private: $marker"
done
[[ $(stat -c '%a' "$state_root") == "700" ]] ||
  fail "native migration state is not private"
[[ ! -e $home/.local/state/omarchy/migrations ]] ||
  fail "validated historical migration markers remain"
snapshot=$(find "$home/.local/state/qvos" -printf '%P|%m|%i|%T@\n' | sort)
HOME="$home" \
  XDG_RUNTIME_DIR="$home/run" \
  QVOS_PATH="$source_root" \
  QVOS_TEST_MIGRATION_LOG="$log" \
  "$runner" >/dev/null
[[ $(<"$log") == "101" ]] || fail "current migration reran"
[[ $(find "$home/.local/state/qvos" -printf '%P|%m|%i|%T@\n' | sort) == "$snapshot" ]] ||
  fail "current migration reconciliation changed state"
printf 'ok - native migration markers adopt exact state and converge privately\n'

retired_windows_migration="$root/qvcore/migrations/1785774136.sh"
retired_windows_home="$test_root/retired-windows-home"
retired_windows_runtime="$retired_windows_home/.local/lib/qvos/windows"
install -d "$(dirname -- "$retired_windows_runtime")"
cp -a "$root/qvcore/windows" "$retired_windows_runtime"
HOME="$retired_windows_home" bash "$retired_windows_migration" >/dev/null
[[ ! -e $retired_windows_runtime ]] ||
  fail "exact retired Windows runtime was preserved"

modified_windows_home="$test_root/modified-windows-home"
modified_windows_runtime="$modified_windows_home/.local/lib/qvos/windows"
install -d "$(dirname -- "$modified_windows_runtime")"
cp -a "$root/qvcore/windows" "$modified_windows_runtime"
printf '\nuser modification\n' >>"$modified_windows_runtime/command"
migration_warning=$(
  HOME="$modified_windows_home" bash "$retired_windows_migration" 2>&1 >/dev/null
)
[[ -d $modified_windows_runtime ]] ||
  fail "modified retired Windows runtime was removed"
grep -Fq 'Preserving modified or unsafe retired Windows runtime:' \
  <<<"$migration_warning" ||
  fail "modified retired Windows runtime warning"
printf 'ok - obsolete runtime cleanup removes only exact generated artifacts\n'

controls_migration="$root/qvcore/migrations/1785776096.sh"
controls_home="$test_root/controls-home"
controls_rule_root="$test_root/controls-rules"
controls_rule="$controls_rule_root/99-power-profile.rules"
controls_system_root="$test_root/controls-system"
controls_log="$test_root/controls-systemctl.log"
controls_bin="$test_root/controls-bin"
legacy_command="${root%/*}/omarchy/bin/omarchy-powerprofiles-set"
install -d "$controls_home/.config/hypr" "$controls_rule_root" "$controls_bin"
install -m 0755 /dev/stdin "$controls_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
SCRIPT
install -m 0644 /dev/stdin "$controls_home/.config/hypr/bindings.conf" <<'CONFIG'
bindeld = , XF86AudioMicMute, Mute microphone, exec, omarchy-audio-input-mute
CONFIG
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service %s"\n' \
  "$legacy_command" >"$controls_rule"
printf 'SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service %s"\n' \
  "$legacy_command" >>"$controls_rule"
HOME="$controls_home" \
PATH="$controls_bin:/usr/bin" \
QVOS_PATH="$root" \
QVOS_POWER_TESTING=1 \
QVOS_POWER_SYSTEM_ROOT="$controls_system_root" \
QVOS_POWER_PROFILE_RULE="$controls_rule" \
QVOS_TEST_SYSTEMCTL_LOG="$controls_log" \
  bash "$controls_migration" >/dev/null
grep -Fq 'qv-audio-input-mute' "$controls_home/.config/hypr/bindings.conf" ||
  fail "desktop-control migration integration"
grep -Fq "$controls_system_root/usr/lib/qvos/power/profiles-set autodetect" \
  "$controls_rule" ||
  fail "power-profile rule migration integration"
if rg -q 'omarchy|--unit=' "$controls_rule"; then
  fail "legacy power-profile rule survived integrated migration"
fi
controls_snapshot=$(find "$controls_home" "$controls_rule_root" \
  "$controls_system_root" -type f -printf '%p|%m|%i|%T@\n' | sort)
HOME="$controls_home" \
PATH="$controls_bin:/usr/bin" \
QVOS_PATH="$root" \
QVOS_POWER_TESTING=1 \
QVOS_POWER_SYSTEM_ROOT="$controls_system_root" \
QVOS_POWER_PROFILE_RULE="$controls_rule" \
QVOS_TEST_SYSTEMCTL_LOG="$controls_log" \
  bash "$controls_migration" >/dev/null
[[ $(find "$controls_home" "$controls_rule_root" "$controls_system_root" \
  -type f -printf '%p|%m|%i|%T@\n' | sort) == \
  "$controls_snapshot" ]] || fail "desktop-control migration integration idempotence"
printf 'ok - promoted control config and root policy migrate together idempotently\n'

browser_migration="$root/qvcore/migrations/1785779159.sh"
browser_home="$test_root/browser-home"
browser_environment="$browser_home/.config/environment.d"
install -d "$browser_environment"
printf '%s\n' 'MOZ_ENABLE_WAYLAND=1' \
  >"$browser_environment/omarchy-firefox-wayland.conf"
HOME="$browser_home" QVOS_PATH="$root" bash "$browser_migration" >/dev/null
grep -Fqx 'MOZ_ENABLE_WAYLAND=1' \
  "$browser_environment/qvos-firefox-wayland.conf" ||
  fail "Firefox Wayland environment migration"
[[ ! -e $browser_environment/omarchy-firefox-wayland.conf ]] ||
  fail "retired Firefox Wayland environment remains"
browser_snapshot=$(find "$browser_environment" -type f -printf '%p|%m|%i|%T@\n' | sort)
HOME="$browser_home" QVOS_PATH="$root" bash "$browser_migration" >/dev/null
[[ $(find "$browser_environment" -type f -printf '%p|%m|%i|%T@\n' | sort) == \
  "$browser_snapshot" ]] || fail "Firefox Wayland migration idempotence"

modified_browser_home="$test_root/modified-browser-home"
modified_browser_environment="$modified_browser_home/.config/environment.d"
install -d "$modified_browser_environment"
printf '%s\n' 'CUSTOM_FIREFOX_SETTING=1' \
  >"$modified_browser_environment/omarchy-firefox-wayland.conf"
browser_warning=$(
  HOME="$modified_browser_home" QVOS_PATH="$root" \
    bash "$browser_migration" 2>&1 >/dev/null
)
grep -Fqx 'CUSTOM_FIREFOX_SETTING=1' \
  "$modified_browser_environment/omarchy-firefox-wayland.conf" ||
  fail "modified Firefox Wayland environment preservation"
grep -Fq 'Preserving modified Firefox Wayland environment:' \
  <<<"$browser_warning" || fail "modified Firefox Wayland migration warning"
printf 'ok - browser runtime naming migrates exactly and preserves modifications\n'

oauth_migration="$root/qvcore/migrations/1786214549.sh"
oauth_home="$test_root/oauth-home"
oauth_flags="$oauth_home/.config/chromium-flags.conf"
install -d "${oauth_flags%/*}"
if git -C "$root" show-ref --verify --quiet refs/remotes/upstream/master; then
  oauth_upstream_ref=upstream/master
else
  oauth_upstream_ref=origin/master
fi
mapfile -t inherited_oauth_flags < <(
  git -C "$root" show \
    "$oauth_upstream_ref:bin/omarchy-install-chromium-google-account" |
    sed -n '/^[[:space:]]*echo "--oauth2-client-/{s/^[[:space:]]*echo "//;s/" >>.*$//;p}'
)
((${#inherited_oauth_flags[@]} == 2)) ||
  fail "reviewed Chromium OAuth migration fixture"
printf '%s\n' "${inherited_oauth_flags[@]}" '--unrelated-flag' >"$oauth_flags"
HOME="$oauth_home" \
  XDG_CONFIG_HOME="$oauth_home/.config" \
  QVOS_PATH="$root" \
  bash "$oauth_migration" >/dev/null
grep -Fqx -- '--unrelated-flag' "$oauth_flags" ||
  fail "Chromium OAuth migration unrelated flag preservation"
if grep -qE '^--oauth2-client-(id|secret)=' "$oauth_flags"; then
  fail "Chromium OAuth migration retained inherited credentials"
fi
oauth_snapshot=$(sha256sum "$oauth_flags")
HOME="$oauth_home" \
  XDG_CONFIG_HOME="$oauth_home/.config" \
  QVOS_PATH="$root" \
  bash "$oauth_migration" >/dev/null
[[ $(sha256sum "$oauth_flags") == "$oauth_snapshot" ]] ||
  fail "Chromium OAuth migration idempotence"
printf 'ok - inherited Chromium OAuth credentials retire exactly and atomically\n'

walker_migration="$root/qvcore/migrations/1786215563.sh"
walker_system="$test_root/walker-system"
walker_hook="$walker_system/etc/pacman.d/hooks/walker-restart.hook"
install -d "${walker_hook%/*}"
install -m 0644 /dev/stdin "$walker_hook" <<'HOOK'
[Trigger]
Type = Package
Operation = Upgrade
Target = walker
Target = walker-debug
Target = elephant*

[Action]
Description = Restarting Walker services after system update
When = PostTransaction
Exec = /home/qv/.local/share/omarchy/bin/omarchy-restart-walker
HOOK
QVOS_PATH="$root" \
  QVOS_MENU_TESTING=1 \
  QVOS_MENU_SYSTEM_ROOT="$walker_system" \
  bash "$walker_migration" >/dev/null
[[ ! -e $walker_hook && ! -L $walker_hook ]] ||
  fail "exact retired Walker Pacman hook remains"
QVOS_PATH="$root" \
  QVOS_MENU_TESTING=1 \
  QVOS_MENU_SYSTEM_ROOT="$walker_system" \
  bash "$walker_migration" >/dev/null

install -m 0644 /dev/stdin "$walker_hook" <<'HOOK'
[Trigger]
Type = Package
Operation = Upgrade
Target = custom-walker

[Action]
Description = Custom administrator hook
When = PostTransaction
Exec = /usr/local/bin/custom-walker-restart
HOOK
walker_warning=$(
  QVOS_PATH="$root" \
    QVOS_MENU_TESTING=1 \
    QVOS_MENU_SYSTEM_ROOT="$walker_system" \
    bash "$walker_migration" 2>&1 >/dev/null
)
[[ -f $walker_hook ]] || fail "modified Walker Pacman hook was removed"
grep -Fq 'Preserving modified or unsafe retired Walker Pacman hook:' \
  <<<"$walker_warning" || fail "modified Walker Pacman hook warning"
printf 'ok - retired Walker root hook cleanup is exact and preservation-safe\n'

dns_migration="$root/qvcore/migrations/1786210567.sh"
dns_system_root="$test_root/dns-system"
dns_network_root="$dns_system_root/etc/systemd/network"
install -d \
  "$dns_system_root/etc/systemd" \
  "$dns_system_root/run" \
  "$dns_network_root"
install -m 0644 /dev/stdin "$dns_system_root/etc/systemd/resolved.conf" <<'RESOLVED'
[Resolve]
FallbackDNS=
RESOLVED
install -m 0644 /dev/stdin "$dns_network_root/20-test.network" <<'NETWORK'
[Match]
Name=en*

[Network]
DHCP=yes

[DHCPv4]
UseDNS=no
RouteMetric=100

[IPv6AcceptRA]
UseDNS=no
RouteMetric=100
NETWORK
QVOS_PATH="$root" \
  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$dns_system_root" \
  bash "$dns_migration" >/dev/null
cmp -s \
  "$root/qvcore/network/dns-policy" \
  "$dns_system_root/usr/lib/qvos/network/dns-policy" ||
  fail "DNS migration root-helper installation"
! grep -Fqx 'FallbackDNS=' "$dns_system_root/etc/systemd/resolved.conf" ||
  fail "DNS migration legacy resolver policy"
! grep -Fqx 'UseDNS=no' "$dns_network_root/20-test.network" ||
  fail "DNS migration inline network policy"
dns_snapshot=$(find "$dns_system_root" -type f -printf '%p|%m|%i|%T@\n' | sort)
QVOS_PATH="$root" \
  QVOS_NETWORK_TESTING=1 \
  QVOS_NETWORK_SYSTEM_ROOT="$dns_system_root" \
  bash "$dns_migration" >/dev/null
[[ $(find "$dns_system_root" -type f -printf '%p|%m|%i|%T@\n' | sort) == \
  "$dns_snapshot" ]] || fail "DNS migration idempotence"
printf 'ok - DNS policy migrates once to a root-owned native helper\n'

seed_home="$test_root/seed-home"
seed_log="$test_root/seed.log"
make_home "$seed_home"
HOME="$seed_home" \
  XDG_RUNTIME_DIR="$seed_home/run" \
  QVOS_PATH="$source_root" \
  QVOS_INSTALL="$source_root/qvcore/install" \
  QVOS_TEST_MIGRATION_LOG="$seed_log" \
  "$runner" --mark-current >/dev/null
[[ ! -e $seed_log ]] || fail "fresh-install seeding executed a migration"
for marker in 100.sh 101.sh; do
  [[ -f $seed_home/.local/state/qvos/migrations/$marker ]] ||
    fail "fresh-install marker missing: $marker"
done
if HOME="$seed_home" XDG_RUNTIME_DIR="$seed_home/run" \
  QVOS_PATH="$source_root" "$runner" --mark-current >/dev/null 2>&1; then
  fail "migration seeding accepted a non-installer caller"
fi
printf 'ok - fresh installation marks native migrations without executing them\n'

failure_root="$test_root/failure-source"
failure_home="$test_root/failure-home"
failure_log="$test_root/failure.log"
install -d "$failure_root/qvcore/migrations"
make_home "$failure_home"
cat >"$failure_root/qvcore/migrations/200.sh" <<'SCRIPT'
if [[ ${QVOS_TEST_MIGRATION_FAIL:-0} == "1" ]]; then
  exit 7
fi
printf '200\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
install -m 0644 /dev/stdin "$failure_root/qvcore/migrations/201.sh" <<'SCRIPT'
printf '201\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
chmod 0644 "$failure_root/qvcore/migrations"/*.sh
set +e
failure_output=$(HOME="$failure_home" \
  XDG_RUNTIME_DIR="$failure_home/run" \
  QVOS_PATH="$failure_root" \
  QVOS_TEST_MIGRATION_FAIL=1 \
  QVOS_TEST_MIGRATION_LOG="$failure_log" \
  "$runner" 2>&1)
failure_status=$?
set -e
((failure_status == 7)) || fail "failed migration status was not preserved"
grep -Fq 'migration 200 failed; correct the error and retry' <<<"$failure_output" ||
  fail "failed migration did not explain recovery"
[[ ! -e $failure_home/.local/state/qvos/migrations/200.sh ]] ||
  fail "failed migration was marked current"
[[ ! -e $failure_log ]] || fail "later migration ran after failure"
HOME="$failure_home" \
  XDG_RUNTIME_DIR="$failure_home/run" \
  QVOS_PATH="$failure_root" \
  QVOS_TEST_MIGRATION_LOG="$failure_log" \
  "$runner" >/dev/null
[[ $(<"$failure_log") == $'200\n201' ]] ||
  fail "failed migration did not retry in order"
printf 'ok - failures stop without skip state and retry in order\n'

unsafe_home="$test_root/unsafe-home"
outside="$test_root/outside"
make_home "$unsafe_home"
install -d "$unsafe_home/.local/state/qvos" "$outside"
printf 'preserve\n' >"$outside/marker"
ln -s "$outside" "$unsafe_home/.local/state/qvos/migrations"
if HOME="$unsafe_home" XDG_RUNTIME_DIR="$unsafe_home/run" \
  QVOS_PATH="$source_root" "$runner" >/dev/null 2>&1; then
  fail "migration runner accepted symbolic-link state"
fi
[[ $(<"$outside/marker") == "preserve" ]] ||
  fail "unsafe migration state changed external data"
printf 'ok - unsafe state is rejected before migration mutation\n'

lock_root="$test_root/lock-source"
lock_home="$test_root/lock-home"
lock_log="$test_root/lock.log"
lock_started="$test_root/lock-started"
install -d "$lock_root/qvcore/migrations"
make_home "$lock_home"
cat >"$lock_root/qvcore/migrations/300.sh" <<'SCRIPT'
printf 'started\n' >"$QVOS_TEST_MIGRATION_STARTED"
sleep 1
printf '300\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
chmod 0644 "$lock_root/qvcore/migrations/300.sh"
HOME="$lock_home" \
  XDG_RUNTIME_DIR="$lock_home/run" \
  QVOS_PATH="$lock_root" \
  QVOS_TEST_MIGRATION_LOG="$lock_log" \
  QVOS_TEST_MIGRATION_STARTED="$lock_started" \
  "$runner" >/dev/null &
first_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -e $lock_started ]] && break
  sleep 0.01
done
[[ -e $lock_started ]] || fail "concurrency fixture did not start"
set +e
lock_output=$(HOME="$lock_home" \
  XDG_RUNTIME_DIR="$lock_home/run" \
  QVOS_PATH="$lock_root" \
  QVOS_TEST_MIGRATION_LOG="$lock_log" \
  QVOS_TEST_MIGRATION_STARTED="$lock_started" \
  "$runner" 2>&1)
lock_status=$?
set -e
((lock_status != 0)) || fail "concurrent migration run was accepted"
grep -Fq 'another migration run is active' <<<"$lock_output" ||
  fail "concurrent migration failure was unclear"
wait "$first_pid"
[[ $(<"$lock_log") == "300" ]] || fail "serialized migration result"
printf 'ok - concurrent migration execution is serialized\n'

creator_root="$test_root/creator"
install -d "$creator_root/qvcore/migrations"
git -C "$creator_root" init -q
created=$(QVOS_PATH="$creator_root" "$creator" --no-edit)
[[ $created =~ /qvcore/migrations/[0-9]+\.sh$ && -f $created ]] ||
  fail "migration creator path"
[[ $(stat -c '%a' "$created") == "644" ]] ||
  fail "migration creator mode"
[[ $(<"$created") == '# shellcheck shell=bash' ]] ||
  fail "migration creator safe template"
printf 'ok - migration creation targets only the native owner directory\n'
