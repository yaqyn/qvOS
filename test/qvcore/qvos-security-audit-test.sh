#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$root/qvcore/security/lynis-audit"
root_helper="$root/qvcore/security/lynis-audit-root"
baseline="$root/qvcore/security/60-qvos-security.conf"
installer="$root/qvcore/security/install"
boot_mount="$root/qvcore/security/boot-mount"
dev_share="$root/qvcore/security/dev-share"
dev_share_helper="$root/qvcore/security/dev-share-firewall"
retire_passwordless="$root/qvcore/security/retire-passwordless-sudo"
auth_owner="$root/qvcore/security/auth"
auth_policy="$root/qvcore/security/auth-policy"
debug_owner="$root/qvcore/security/debug"
debug_adapter="$root/bin/qv-debug"
debug_compatibility="$root/bin/omarchy-debug"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
escalation_log="$test_root/escalation.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

[[ -x $runner && -x $root_helper ]] \
  || fail "security audit runners are executable"
[[ -x $installer && -x $boot_mount && -f $baseline && -x $dev_share && -x $dev_share_helper &&
  -x $retire_passwordless && -x $auth_owner && -x $auth_policy &&
  -x $debug_owner && -x $debug_adapter && -x $debug_compatibility ]] \
  || fail "security baseline installer is available"
if rg -n 'OMARCHY_PATH' "$root/qvcore/security" --glob '!AGENTS.md'; then
  fail "native security owner accepts the compatibility source root"
fi
grep -Fq 'qvcore/security/AGENTS.md' "$root/AGENTS.md" \
  || fail "root security workflow route"
grep -Fq 'The Lynis hardening index is evidence, not a target.' \
  "$root/qvcore/security/AGENTS.md" \
  || fail "balanced hardening score boundary"
grep -Fq 'never authorize automatic hardening' "$root/qvcore/README.md" \
  || fail "security audit architecture boundary"
[[ ! -e $root/bin/omarchy-upload-log ]] ||
  fail "unsupported diagnostic upload command"
if rg -q 'logs\.omarchy\.org|omarchy upload log' \
  "$debug_owner" \
  "$root/qvcore/config/assistant/qvos/SKILL.md" \
  "$root/qvcore/install/helpers/errors" \
  "$root/release/iso/builder" \
  "$root/release/iso/profile"; then
  fail "qvOS diagnostics still export private machine inventory"
fi
if rg -q 'omarchy-upload-log|Upload log for support' \
  "$root/qvcore/install/helpers/errors" \
  "$root/release/iso/builder" \
  "$root/release/iso/profile"; then
  fail "retired diagnostic upload remains in install or ISO lifecycle"
fi
[[ ! -e $root/bin/omarchy-sudo-passwordless ]] ||
  fail "reboot-unsafe passwordless sudo command remains"
[[ ! -e $root/bin/omarchy-sudo-reset ]] ||
  fail "unsafe authentication lockout reset command remains"
if rg -q 'passwordless-sudo|Passwordless Sudo|omarchy-sudo-passwordless' \
  "$root/qvcore/menu/concepts.psv" \
  "$root/qvcore/tui/task/actions.psv" \
  "$root/qvcore/menu/base" \
  "$root/qvcore/menu/routes"; then
  fail "broad passwordless sudo remains user-accessible"
fi
grep -Fqx 'bin/omarchy-sudo-passwordless' \
  "$root/qvcore/security/retired-paths" ||
  fail "passwordless sudo retirement inventory"
grep -Fqx 'bin/omarchy-sudo-reset' \
  "$root/qvcore/security/retired-paths" ||
  fail "authentication lockout reset retirement inventory"

expected_security_native=$'bin/omarchy-debug\nbin/omarchy-remove-security-fido2\nbin/omarchy-remove-security-fingerprint\nbin/omarchy-setup-security-fido2\nbin/omarchy-setup-security-fingerprint'
[[ $(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
  "$root/qvcore/security/native-paths") == "$expected_security_native" ]] ||
  fail "native security path inventory"
declare -A auth_arguments=(
  [remove-security-fido2]='remove fido2'
  [remove-security-fingerprint]='remove fingerprint'
  [setup-security-fido2]='setup fido2'
  [setup-security-fingerprint]='setup fingerprint'
)
for auth_route in "${!auth_arguments[@]}"; do
  native_auth="$root/bin/qv-$auth_route"
  compatibility_auth="$root/bin/omarchy-$auth_route"
  [[ -x $native_auth && -x $compatibility_auth ]] ||
    fail "authentication adapter mode: $auth_route"
  (( $(wc -l <"$native_auth") <= 10 )) ||
    fail "native authentication adapter contains implementation: $auth_route"
  (( $(wc -l <"$compatibility_auth") <= 5 )) ||
    fail "authentication compatibility adapter contains implementation: $auth_route"
  rg -q '^# qv:summary=' "$native_auth" ||
    fail "native authentication metadata: $auth_route"
  ! rg -q '^# (qv|omarchy):' "$compatibility_auth" ||
    fail "authentication compatibility metadata duplication: $auth_route"
  expected_auth_exec="exec \"\$QVOS_PATH/qvcore/security/auth\" ${auth_arguments[$auth_route]} \"\$@\""
  for auth_adapter in "$native_auth" "$compatibility_auth"; do
    grep -Fqx "$expected_auth_exec" "$auth_adapter" ||
      fail "authentication adapter ownership: $auth_route"
  done
done
if rg -n 'omarchy-(setup|remove)-security-(fingerprint|fido2)' \
  "$root/qvcore/menu" "$root/qvcore/tui/task/actions.psv" \
  --glob '!AGENTS.md' --glob '!native-paths'; then
  fail "native qvOS surfaces call authentication compatibility routes"
fi

retire_root="$test_root/retire-root"
retire_sudoers="$retire_root/etc/sudoers.d"
install -d "$retire_sudoers"
legacy_rule="$retire_sudoers/99-omarchy-nopasswd-fixture"
legacy_timezone_rule="$retire_sudoers/omarchy-tzupdate"
printf 'fixture ALL=(ALL) NOPASSWD: ALL\n' >"$legacy_rule"
printf '%s\n' \
  '%wheel ALL=(root) NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl' \
  >"$legacy_timezone_rule"
chmod 0440 "$legacy_rule" "$legacy_timezone_rule"
QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$retire_root" \
  "$retire_passwordless"
[[ ! -e $legacy_rule && ! -L $legacy_rule &&
  ! -e $legacy_timezone_rule && ! -L $legacy_timezone_rule ]] ||
  fail "exact legacy passwordless sudo rule was not retired"

printf 'fixture ALL=(ALL) NOPASSWD: /usr/bin/true\n' >"$legacy_rule"
chmod 0440 "$legacy_rule"
if QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$retire_root" \
  "$retire_passwordless" >/dev/null 2>&1; then
  fail "modified legacy passwordless sudo rule was accepted"
fi
[[ -f $legacy_rule ]] ||
  fail "modified legacy passwordless sudo rule was removed"
rm -f -- "$legacy_rule"

printf 'fixture ALL=(ALL) NOPASSWD: ALL\n' >"$legacy_rule"
printf 'custom timezone privilege\n' >"$legacy_timezone_rule"
chmod 0440 "$legacy_rule" "$legacy_timezone_rule"
if QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$retire_root" \
  "$retire_passwordless" >/dev/null 2>&1; then
  fail "modified legacy timezone rule was accepted"
fi
[[ -f $legacy_rule && -f $legacy_timezone_rule ]] ||
  fail "passwordless retirement mutated before complete preflight"
rm -f -- "$legacy_rule" "$legacy_timezone_rule"

unsafe_sudoers="$test_root/unsafe-sudoers"
mv "$retire_sudoers" "$unsafe_sudoers"
ln -s "$unsafe_sudoers" "$retire_sudoers"
if QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$retire_root" \
  "$retire_passwordless" >/dev/null 2>&1; then
  fail "linked sudoers directory was accepted"
fi
unlink -- "$retire_sudoers"
mv "$unsafe_sudoers" "$retire_sudoers"
(( $(wc -l <"$debug_adapter") <= 12 )) ||
  fail "native debug adapter contains implementation"
(( $(wc -l <"$debug_compatibility") <= 5 )) ||
  fail "debug compatibility adapter contains implementation"
rg -q '^# qv:summary=' "$debug_adapter" ||
  fail "native debug metadata"
! rg -q '^# (qv|omarchy):' "$debug_compatibility" ||
  fail "debug compatibility metadata duplication"
for adapter in "$debug_adapter" "$debug_compatibility"; do
  # shellcheck disable=SC2016
  grep -Fqx 'exec "$QVOS_PATH/qvcore/security/debug" "$@"' "$adapter" ||
    fail "debug adapter delegation"
done
grep -Fq 'mktemp -d' "$debug_owner" ||
  fail "qvOS debug log private temporary storage"
debug_tmp="$test_root/debug-tmp"
debug_save="$test_root/debug-save"
install -d "$debug_tmp" "$debug_save" "$test_bin"
install -m 0755 /dev/stdin "$test_bin/inxi" <<'SCRIPT'
#!/bin/bash
printf 'fixture system\033[31m unsafe-color\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/journalctl" <<'SCRIPT'
#!/bin/bash
printf 'fixture warning\033]8;;https://unsafe.invalid\a linked\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
-Qqen) printf 'official-alpha\n' ;;
-Qqem) printf 'foreign-beta\n' ;;
*) exit 64 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/expac" <<'SCRIPT'
#!/bin/bash
mode=$1
shift 2
for package in "$@"; do
  case $mode in
  -S)
    printf '%s\tcore\n' "$package"
    printf '%s\tomarchy\n' "$package"
    ;;
  -Q)
    case $package in
    official-alpha) printf '%s\t1.0-installed\n' "$package" ;;
    foreign-beta) printf '%s\t2.0-installed\n' "$package" ;;
    *) exit 64 ;;
    esac
    ;;
  *) exit 64 ;;
  esac
done
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
[[ -z ${QVOS_TEST_GUM_STATUS:-} ]] || exit "$QVOS_TEST_GUM_STATUS"
printf '%s\n' "${QVOS_TEST_GUM_ACTION:-View log}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/less" <<'SCRIPT'
#!/bin/bash
cat -- "${@: -1}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
[[ $# == 1 && $1 == "dmesg" ]] || exit 64
printf 'fixture kernel warning\n'
SCRIPT

debug_output=$(
  TMPDIR="$debug_tmp" \
    PATH="$test_bin:/usr/bin" \
    QVOS_PATH="$root" \
    "$debug_adapter" --no-sudo --print
)
grep -Fq 'qvOS Branch:' <<<"$debug_output" ||
  fail "qvOS debug native identity"
grep -Fq 'official-alpha 1.0-installed (core)' <<<"$debug_output" ||
  fail "qvOS debug repository package classification"
grep -Fq 'foreign-beta 2.0-installed (foreign)' <<<"$debug_output" ||
  fail "qvOS debug foreign package classification"
(( $(grep -Fc 'official-alpha ' <<<"$debug_output") == 1 )) ||
  fail "qvOS debug repository priority duplication"
if LC_ALL=C grep -q $'\033\|\a\|\r' <<<"$debug_output"; then
  fail "qvOS debug terminal-control sanitization"
fi
privileged_debug_output=$(
  TMPDIR="$debug_tmp" \
    PATH="$test_bin:/usr/bin" \
    QVOS_PATH="$root" \
    "$debug_adapter" --print
)
grep -Fq 'fixture kernel warning' <<<"$privileged_debug_output" ||
  fail "qvOS debug limits sudo to dmesg collection"
[[ -z $(find "$debug_tmp" -mindepth 1 -maxdepth 1 -print -quit) ]] ||
  fail "qvOS debug private temporary cleanup"

debug_save_output=$(
  cd -- "$debug_save"
  TMPDIR="$debug_tmp" \
    PATH="$test_bin:/usr/bin" \
    QVOS_PATH="$root" \
    QVOS_TEST_GUM_ACTION="Save in current directory" \
    "$debug_adapter" --no-sudo
)
saved_debug=${debug_save_output#Log saved to }
[[ $saved_debug == "$debug_save"/qvos-debug-*.log &&
  -f $saved_debug && ! -L $saved_debug &&
  $(stat -c '%a' "$saved_debug") == "600" ]] ||
  fail "qvOS debug unique private save"
[[ $(find "$debug_save" -maxdepth 1 -type f -name 'qvos-debug-*.log' | wc -l) == "1" ]] ||
  fail "qvOS debug exact save inventory"
[[ -z $(find "$debug_save" -maxdepth 1 -type f -name '.qvos-debug-stage.*' -print -quit) ]] ||
  fail "qvOS debug atomic save staging cleanup"

set +e
TMPDIR="$debug_tmp" \
  PATH="$test_bin:/usr/bin" \
  QVOS_PATH="$root" \
  QVOS_TEST_GUM_STATUS=130 \
  "$debug_adapter" --no-sudo >/dev/null 2>&1
debug_cancel_status=$?
set -e
((debug_cancel_status == 130)) || fail "qvOS debug cancellation status"
[[ -z $(find "$debug_tmp" -mindepth 1 -maxdepth 1 -print -quit) ]] ||
  fail "qvOS debug cancellation cleanup"
grep -Fq '104b2ad73595de52a2f92f0bb17160385bae0579' "$runner" \
  || fail "LinUtil source provenance"

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/lynis" <<'SCRIPT'
#!/bin/bash

exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash

if [[ ${1:-} == "-n" && ${2:-} == "true" ]]; then
  exit 1
fi
exit 99
SCRIPT
install -m 0755 /dev/stdin "$test_bin/pkexec" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"$QVOS_TEST_ESCALATION_LOG"
root_helper=$1
owner_uid=$2
owner_gid=$3
output_dir=$4
audit_log=$5
audit_report=$6

[[ ${root_helper##*/} == "lynis-audit-root" ]]
[[ $owner_uid =~ ^[0-9]+$ && $owner_gid =~ ^[0-9]+$ ]]
[[ $audit_log == "$output_dir/lynis-"*.log ]]
[[ $audit_report == "$output_dir/lynis-report-"*.dat ]]

printf '[ Lynis test output ]\nSuggestions (2)\n'
if [[ ${QVOS_TEST_OMIT_REPORTS:-0} == "1" ]]; then
  exit 0
fi
printf 'mock log\n' >"$audit_log"
printf '%s\n' \
  'lynis_tests_done=242' \
  'hardening_index=68' \
  'suggestion[]=TEST-1|First suggestion|-|-|' \
  'suggestion[]=TEST-2|Second suggestion|-|-|' \
  'exception_event[]=TEST-3:1|Expected fixture exception|' \
  >"$audit_report"
chmod 0600 "$audit_log" "$audit_report"
SCRIPT

audit_output=$(
  HOME="$test_root/home" \
    XDG_STATE_HOME="$test_root/state" \
    DISPLAY=":1" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ESCALATION_LOG="$escalation_log" \
    "$runner"
)

grep -Fq '[ Lynis test output ]' <<<"$audit_output" \
  || fail "full Lynis output is streamed"
grep -Fq \
  'Tests: 242 | Hardening index: 68 | Warnings: 0 | Suggestions: 2 | Exceptions: 1' \
  <<<"$audit_output" \
  || fail "saved report summary"
[[ $(wc -l <"$escalation_log") == "1" ]] \
  || fail "one privileged audit transaction"
grep -Fq 'lynis-audit-root' "$escalation_log" \
  || fail "root helper escalation"

audit_dir="$test_root/state/qvos/security/lynis"
[[ $(stat -c '%a' "$audit_dir") == "700" ]] \
  || fail "private audit directory mode"
mapfile -t saved_reports < <(find "$audit_dir" -maxdepth 1 -type f -printf '%f\n' | sort)
[[ ${#saved_reports[@]} == 2 ]] \
  || fail "audit report pair"
for saved_report in "${saved_reports[@]}"; do
  [[ $(stat -c '%a' "$audit_dir/$saved_report") == "600" ]] \
    || fail "private audit report mode"
done

grep -Fq '/usr/bin/lynis audit system' "$root_helper" \
  || fail "complete native Lynis audit"
grep -Fq '/usr/bin/install -m 0600' "$root_helper" \
  || fail "private report copy"
grep -Fq 'report_mtime < audit_started' "$root_helper" \
  || fail "stale report rejection"
grep -Fq "'%g' \"\$output_dir\"" "$root_helper" \
  || fail "report group ownership validation"
if rg -q '^[[:space:]]*((/usr/bin/)?mv |(sudo )?pacman|omarchy-pkg-(add|remove))' \
  "$runner" "$root_helper"; then
  fail "audit mutates report ownership or packages"
fi

expected_baseline=$'# Protect named pipes and regular files in all world-writable sticky directories.\nfs.protected_fifos = 2\nfs.protected_regular = 2\n\n# Hide kernel pointers from unprivileged users while preserving root debugging.\nkernel.kptr_restrict = 1'
[[ $(<"$baseline") == "$expected_baseline" ]] \
  || fail "balanced sysctl baseline"
if rg -q 'modules_disabled|kernel\\.sysrq|\\.forwarding|usb|firewire|compiler' \
  "$baseline"; then
  fail "security baseline restricts normal desktop capabilities"
fi

first_run_prepare="$root/qvcore/install/first-run/prepare"
first_run_root="$root/qvcore/install/first-run/root"
grep -Fq 'NOPASSWD: /usr/lib/qvos/first-run-root apply' \
  "$first_run_prepare" || fail "exact first-run apply privilege"
grep -Fq 'NOPASSWD: /usr/lib/qvos/first-run-root cleanup' \
  "$first_run_prepare" || fail "exact first-run cleanup privilege"
grep -Fq '/usr/bin/env -i' "$first_run_root" ||
  fail "first-run privileged command environment sanitation"
if rg -q 'NOPASSWD:.*(systemctl|ufw|ufw-docker|gtk-update-icon-cache|/bin/rm)' \
  "$first_run_prepare" "$root/qvcore/install/preflight"; then
  fail "fresh install grants a broad passwordless command"
fi
# shellcheck disable=SC2016
grep -Fqx '  run_fixed_command "$ufw" default deny incoming' \
  "$first_run_root" ||
  fail "first-run firewall remains deny-incoming"
# shellcheck disable=SC2016
grep -Fqx '  run_fixed_command "$ufw" default allow outgoing' \
  "$first_run_root" ||
  fail "first-run firewall remains allow-outgoing"

post_install_all="$root/qvcore/install/post-install/run"
# shellcheck disable=SC2016
pacman_post_line=$(grep -nF 'run_logged "$QVOS_INSTALL/post-install/pacman.sh"' \
  "$post_install_all" | cut -d: -f1)
# shellcheck disable=SC2016
security_post_line=$(grep -nF 'run_logged "$QVOS_PATH/qvcore/security/install"' \
  "$post_install_all" | cut -d: -f1)
# shellcheck disable=SC2016
allow_reboot_line=$(grep -nF 'source "$QVOS_INSTALL/post-install/allow-reboot.sh"' \
  "$post_install_all" | cut -d: -f1)
[[ $pacman_post_line =~ ^[0-9]+$ && $security_post_line =~ ^[0-9]+$ &&
  $allow_reboot_line =~ ^[0-9]+$ ]] ||
  fail "fresh-install security post-install wiring"
((pacman_post_line < security_post_line &&
  security_post_line < allow_reboot_line)) ||
  fail "fresh-install security runs after final Pacman config and before reboot"

offline_system_root="$test_root/offline-security-system"
install -d "$offline_system_root/etc"
install -m 0644 /dev/stdin "$offline_system_root/etc/pacman.conf" <<'PACMAN'
[options]
SigLevel = Required DatabaseOptional

[offline]
SigLevel = Required DatabaseOptional
Server = file:///var/cache/qvos/mirror/offline/
PACMAN
cp "$offline_system_root/etc/pacman.conf" \
  "$test_root/offline-pacman-original.conf"
offline_output=$(
  OMARCHY_CHROOT_INSTALL=1 \
    QVOS_SECURITY_TESTING=1 \
    QVOS_SECURITY_SYSTEM_ROOT="$offline_system_root" \
    QVOS_PATH="$root" \
    "$installer"
)
grep -Fq 'Deferring qvOS security until the final Pacman configuration' \
  <<<"$offline_output" ||
  fail "ISO offline Pacman deferral is explicit"
cmp -s "$test_root/offline-pacman-original.conf" \
  "$offline_system_root/etc/pacman.conf" ||
  fail "ISO offline Pacman configuration changed before post-install"
[[ ! -e $offline_system_root/etc/sysctl.d/60-qvos-security.conf ]] ||
  fail "ISO security installation partially ran before final Pacman config"

if QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$offline_system_root" \
  QVOS_PATH="$root" \
  "$installer" >/dev/null 2>&1; then
  fail "offline Pacman policy accepted outside the ISO chroot"
fi

printf 'Server = file:///tmp/untrusted/\n' \
  >>"$offline_system_root/etc/pacman.conf"
if OMARCHY_CHROOT_INSTALL=1 \
  QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$offline_system_root" \
  QVOS_PATH="$root" \
  "$installer" >/dev/null 2>&1; then
  fail "ambiguous ISO offline mirror accepted"
fi
[[ ! -e $offline_system_root/etc/sysctl.d/60-qvos-security.conf ]] ||
  fail "ambiguous ISO offline mirror causes partial installation"

install -d "$offline_system_root/etc/pam.d" "$offline_system_root/run"
install -m 0644 /dev/stdin "$offline_system_root/etc/pam.d/sudo" <<'PAM'
auth include system-auth
account include system-auth
session include system-auth
PAM
cp "$root/qvcore/packages/provider/omarchy/pacman-rc.conf" \
  "$offline_system_root/etc/pacman.conf"
OMARCHY_CHROOT_INSTALL=1 \
  QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$offline_system_root" \
  QVOS_PATH="$root" \
  "$installer"
[[ $(awk '
  /^\[omarchy\]$/ { in_omarchy = 1; next }
  /^\[/ { in_omarchy = 0 }
  in_omarchy && /^SigLevel/ { print }
' "$offline_system_root/etc/pacman.conf") == \
  "SigLevel = Required DatabaseOptional" ]] ||
  fail "final ISO Omarchy repository policy"
[[ -f $offline_system_root/etc/sysctl.d/60-qvos-security.conf ]] ||
  fail "deferred ISO security baseline installation"

ambiguous_system_root="$test_root/ambiguous-security-system"
install -d "$ambiguous_system_root/etc"
install -m 0644 /dev/stdin "$ambiguous_system_root/etc/pacman.conf" <<'PACMAN'
[omarchy]
SigLevel = Optional TrustAll
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/stable/$arch
PACMAN
if QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$ambiguous_system_root" \
  QVOS_PATH="$root" \
  "$installer" >/dev/null 2>&1; then
  fail "ambiguous Omarchy repository policy accepted"
fi
[[ ! -e $ambiguous_system_root/etc/sysctl.d/60-qvos-security.conf ]] \
  || fail "ambiguous repository policy causes partial installation"

security_system_root="$test_root/security-system"
system_install_tree="$security_system_root/usr/install"
install -d \
  "$security_system_root/etc/docker" \
  "$security_system_root/etc" \
  "$security_system_root/etc/pam.d" \
  "$security_system_root/run" \
  "$system_install_tree/cache/test-package/dist" \
  "$system_install_tree/global/node_modules/test-package" \
  "$security_system_root/usr/local/bin"
install -m 0644 /dev/stdin "$security_system_root/etc/pam.d/sudo" <<'PAM'
auth include system-auth
account include system-auth
session include system-auth
PAM
install -m 0644 /dev/stdin "$security_system_root/etc/pacman.conf" <<'PACMAN'
[core]
SigLevel = Required DatabaseOptional

[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/stable/$arch

[local-test]
SigLevel = Optional TrustAll
PACMAN
install -m 0644 /dev/stdin "$security_system_root/etc/docker/daemon.json" <<'DOCKER'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "dns": ["172.17.0.1"],
  "bip": "172.17.0.1/16"
}
DOCKER
install -m 0644 /dev/stdin "$security_system_root/etc/fstab" <<'FSTAB'
# qvOS test mounts
UUID=TEST-BOOT /boot vfat rw,relatime,fmask=0022,dmask=0022,utf8 0 2
UUID=TEST-ROOT / btrfs rw,relatime 0 0
FSTAB
install -m 0777 /dev/null \
  "$system_install_tree/cache/test-package/dist/program.js"
install -m 0775 /dev/null \
  "$system_install_tree/global/node_modules/test-package/program.js"
install -m 0700 /dev/null \
  "$system_install_tree/global/node_modules/test-package/private.js"
install -m 0777 /dev/null \
  "$security_system_root/usr/local/bin/outside-program"
ln -s \
  "$system_install_tree/cache/test-package/dist/program.js" \
  "$system_install_tree/global/node_modules/test-package/program-link"
security_sudoers="$security_system_root/etc/sudoers.d"
install -d "$security_sudoers"
security_legacy_rule="$security_sudoers/99-omarchy-nopasswd-fixture"
printf 'fixture ALL=(ALL) NOPASSWD: /usr/bin/true\n' >"$security_legacy_rule"
chmod 0440 "$security_legacy_rule"
security_pacman_before=$(sha256sum "$security_system_root/etc/pacman.conf")
if QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$security_system_root" \
  QVOS_PATH="$root" \
  "$installer" >/dev/null 2>&1; then
  fail "security install accepted a modified legacy passwordless rule"
fi
[[ -f $security_legacy_rule ]] ||
  fail "security install removed a modified legacy passwordless rule"
[[ $(sha256sum "$security_system_root/etc/pacman.conf") == \
  "$security_pacman_before" ]] ||
  fail "legacy-rule refusal partially changed package trust policy"
[[ ! -e $security_system_root/etc/sysctl.d/60-qvos-security.conf ]] ||
  fail "legacy-rule refusal partially installed the security baseline"
chmod 0640 "$security_legacy_rule"
printf 'fixture ALL=(ALL) NOPASSWD: ALL\n' >"$security_legacy_rule"
chmod 0440 "$security_legacy_rule"
QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$security_system_root" \
  QVOS_PATH="$root" \
  "$installer"
[[ ! -e $security_legacy_rule && ! -L $security_legacy_rule ]] ||
  fail "security install did not retire the exact legacy passwordless rule"
managed_security_files=(
  "$security_system_root/etc/docker/daemon.json"
  "$security_system_root/etc/fstab"
  "$security_system_root/etc/pacman.conf"
  "$security_system_root/etc/sysctl.d/60-qvos-security.conf"
  "$security_system_root/usr/lib/qvos/dev-share-firewall"
  "$security_system_root/usr/lib/qvos/security/auth-policy"
  "$security_system_root/usr/lib/qvos/retire-passwordless-sudo"
  "$system_install_tree/cache/test-package/dist/program.js"
  "$system_install_tree/global/node_modules/test-package/private.js"
  "$system_install_tree/global/node_modules/test-package/program.js"
)
security_state_before=$(stat -c '%n|%u:%g:%a|%i|%y' "${managed_security_files[@]}")
QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$security_system_root" \
  QVOS_PATH="$root" \
  "$installer"
[[ $(stat -c '%n|%u:%g:%a|%i|%y' "${managed_security_files[@]}") == \
  "$security_state_before" ]] ||
  fail "idempotent security reconciliation rewrote protected state"
installed_baseline="$security_system_root/etc/sysctl.d/60-qvos-security.conf"
cmp -s "$baseline" "$installed_baseline" \
  || fail "security baseline system install"
[[ $(stat -c '%a' "$installed_baseline") == "644" ]] \
  || fail "security baseline mode"
installed_dev_share_helper="$security_system_root/usr/lib/qvos/dev-share-firewall"
cmp -s "$dev_share_helper" "$installed_dev_share_helper" \
  || fail "LAN preview root helper system install"
[[ $(stat -c '%a' "$installed_dev_share_helper") == "755" ]] \
  || fail "LAN preview root helper mode"
installed_retire_passwordless="$security_system_root/usr/lib/qvos/retire-passwordless-sudo"
cmp -s "$retire_passwordless" "$installed_retire_passwordless" \
  || fail "passwordless-sudo retirement helper system install"
[[ $(stat -c '%a' "$installed_retire_passwordless") == "755" ]] \
  || fail "passwordless-sudo retirement helper mode"
installed_auth_policy="$security_system_root/usr/lib/qvos/security/auth-policy"
cmp -s "$root/qvcore/security/auth-policy" "$installed_auth_policy" \
  || fail "authentication policy helper system install"
[[ $(stat -c '%a' "$installed_auth_policy") == "755" ]] \
  || fail "authentication policy helper mode"
[[ $(awk '
  /^\[omarchy\]$/ { in_omarchy = 1; next }
  /^\[/ { in_omarchy = 0 }
  in_omarchy && /^SigLevel/ { print }
' "$security_system_root/etc/pacman.conf") == \
  "SigLevel = Required DatabaseOptional" ]] \
  || fail "Omarchy package signatures are required"
[[ $(awk '
  /^\[local-test\]$/ { in_local_test = 1; next }
  /^\[/ { in_local_test = 0 }
  in_local_test && /^SigLevel/ { print }
' "$security_system_root/etc/pacman.conf") == "SigLevel = Optional TrustAll" ]] \
  || fail "unrelated repository policy stays unchanged"
jq -e '
  .ip == "127.0.0.1" and
  .["default-network-opts"].bridge[
    "com.docker.network.bridge.host_binding_ipv4"
  ] == "127.0.0.1" and
  .["log-driver"] == "json-file" and
  .dns == ["172.17.0.1"] and
  .bip == "172.17.0.1/16"
' "$security_system_root/etc/docker/daemon.json" >/dev/null \
  || fail "Docker defaults to loopback without losing inherited configuration"
[[ $(awk '$2 == "/boot" { print $4 }' "$security_system_root/etc/fstab") == \
  "rw,relatime,utf8,fmask=0077,dmask=0077" ]] ||
  fail "EFI system partition root-only mount policy"
[[ $(awk '$2 == "/" { print $4 }' "$security_system_root/etc/fstab") == \
  "rw,relatime" ]] || fail "non-EFI mount policy preservation"
fstab_checksum=$(sha256sum "$security_system_root/etc/fstab")
QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$security_system_root" \
  "$boot_mount"
[[ $(sha256sum "$security_system_root/etc/fstab") == "$fstab_checksum" ]] ||
  fail "EFI mount policy idempotence"
grep -Fq 'as_root /usr/bin/systemctl daemon-reload' "$boot_mount" ||
  fail "EFI mount units reload after the policy changes"
# shellcheck disable=SC2016
grep -Fq '[[ $generated_options == "$desired_options" ]]' "$boot_mount" ||
  fail "unchanged EFI policy avoids a redundant privileged reload"
grep -Fq '/usr/bin/systemctl show --property=FragmentPath --value boot.mount' \
  "$boot_mount" ||
  fail "EFI generated mount unit path is resolved"
# shellcheck disable=SC2016
grep -Fq '[[ $source_path == "/etc/fstab" ]]' "$boot_mount" ||
  fail "EFI generated mount unit is sourced from fstab"
# shellcheck disable=SC2016
grep -Fq '[[ $generated_options != "$desired_options" ]]' "$boot_mount" ||
  fail "EFI generated mount policy preserves the complete option set"
if rg -q -- '--property=Options' "$boot_mount"; then
  fail "EFI policy validation incorrectly reads the active systemd property"
fi
if rg -q '/usr/bin/(mount|umount)|\bremount\b' "$boot_mount"; then
  fail "EFI permission masks are incorrectly treated as live-mutable"
fi
grep -Fq 'reboot required to activate fmask=0077,dmask=0077' "$boot_mount" ||
  fail "EFI live policy mismatch requires reboot"
# shellcheck disable=SC2016
grep -Fq 'desired_options=$(awk' "$boot_mount" ||
  fail "EFI generated policy uses the validated candidate options"
grep -Fq 'restore_prior_policy' "$boot_mount" ||
  fail "EFI policy reload failure restores the prior fstab"

ambiguous_boot_root="$test_root/ambiguous-boot-system"
install -d "$ambiguous_boot_root/etc"
install -m 0644 /dev/stdin "$ambiguous_boot_root/etc/fstab" <<'FSTAB'
UUID=TEST-BOOT-A /boot vfat defaults 0 2
UUID=TEST-BOOT-B /boot vfat defaults 0 2
FSTAB
cp "$ambiguous_boot_root/etc/fstab" "$test_root/ambiguous-fstab-original"
if QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$ambiguous_boot_root" \
  "$boot_mount" --check >/dev/null 2>&1; then
  fail "ambiguous EFI mount policy accepted"
fi
cmp -s "$test_root/ambiguous-fstab-original" "$ambiguous_boot_root/etc/fstab" ||
  fail "ambiguous EFI mount policy mutation"
[[ $(stat -c '%a' "$system_install_tree/cache/test-package/dist/program.js") == "755" ]] \
  || fail "world-writable system package program mode"
[[ $(stat -c '%a' "$system_install_tree/global/node_modules/test-package/program.js") == "755" ]] \
  || fail "group-writable system package program mode"
[[ $(stat -c '%a' "$system_install_tree/global/node_modules/test-package/private.js") == "700" ]] \
  || fail "owner-only system package program mode"
[[ $(stat -c '%a' "$security_system_root/usr/local/bin/outside-program") == "777" ]] \
  || fail "files outside the system package tree stay unchanged"
[[ -L $system_install_tree/global/node_modules/test-package/program-link ]] \
  || fail "system package symlinks stay unchanged"

resolved_base=$("$root/qvcore/install/packaging/resolve" base)
grep -qx 'arch-audit' <<<"$resolved_base" \
  || fail "Arch vulnerability audit package"

if HOME="$test_root/omitted-home" \
  XDG_STATE_HOME="$test_root/omitted-state" \
  DISPLAY=":1" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_ESCALATION_LOG="$escalation_log" \
  QVOS_TEST_OMIT_REPORTS=1 \
  "$runner" >/dev/null 2>&1; then
  fail "missing privileged reports return success"
fi

missing_bin="$test_root/missing-bin"
install -d "$missing_bin"
for command_name in awk bash chmod date dirname id install stat; do
  command_path="$(command -v "$command_name")"
  ln -s "$command_path" "$missing_bin/$command_name"
done
if HOME="$test_root/missing-home" \
  PATH="$missing_bin" \
  "$runner" >/dev/null 2>&1; then
  fail "missing Lynis accepted"
fi

printf 'ok - Codex gets full Lynis output, private reports, and balanced hardening policy\n'
