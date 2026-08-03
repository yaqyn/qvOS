#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$root/qv/security/lynis-audit"
root_helper="$root/qv/security/lynis-audit-root"
baseline="$root/qv/security/60-qvos-security.conf"
installer="$root/qv/security/install"
boot_mount="$root/qv/security/boot-mount"
dev_share="$root/qv/security/dev-share"
dev_share_helper="$root/qv/security/dev-share-firewall"
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
[[ -x $installer && -x $boot_mount && -f $baseline && -x $dev_share && -x $dev_share_helper ]] \
  || fail "security baseline installer is available"
grep -Fq 'qv/security/AGENTS.md' "$root/AGENTS.md" \
  || fail "root security workflow route"
grep -Fq 'The Lynis hardening index is evidence, not a target.' \
  "$root/qv/security/AGENTS.md" \
  || fail "balanced hardening score boundary"
grep -Fq 'never authorize automatic hardening' "$root/qv/README.md" \
  || fail "security audit architecture boundary"
[[ ! -e $root/bin/omarchy-upload-log ]] ||
  fail "unsupported diagnostic upload command"
if rg -q 'logs\.omarchy\.org|omarchy upload log' \
  "$root/bin/omarchy-debug" \
  "$root/default/omarchy-skill/SKILL.md" \
  "$root/install/helpers/errors.sh" \
  "$root/qv/iso/omarchy-iso-qvos-tui.patch"; then
  fail "qvOS diagnostics still export private machine inventory"
fi
if rg -q 'omarchy-upload-log|Upload log for support' \
  "$root/install/helpers/errors.sh" ||
  sed -n '/^[ +]/p' "$root/qv/iso/omarchy-iso-qvos-tui.patch" |
    rg -q 'omarchy-upload-log|Upload log for support'; then
  fail "retired diagnostic upload remains in install or ISO lifecycle"
fi
grep -Fq 'mktemp -d' "$root/bin/omarchy-debug" ||
  fail "qvOS debug log private temporary storage"
debug_tmp="$test_root/debug-tmp"
install -d "$debug_tmp"
TMPDIR="$debug_tmp" OMARCHY_PATH="$root" \
  "$root/bin/omarchy-debug" --no-sudo --print >/dev/null
[[ -z $(find "$debug_tmp" -mindepth 1 -maxdepth 1 -print -quit) ]] ||
  fail "qvOS debug private temporary cleanup"
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

post_install_all="$root/install/post-install/all.sh"
# shellcheck disable=SC2016
pacman_post_line=$(grep -nF 'run_logged $OMARCHY_INSTALL/post-install/pacman.sh' \
  "$post_install_all" | cut -d: -f1)
# shellcheck disable=SC2016
security_post_line=$(grep -nF 'run_logged "$OMARCHY_PATH/qv/security/install"' \
  "$post_install_all" | cut -d: -f1)
# shellcheck disable=SC2016
allow_reboot_line=$(grep -nF 'source $OMARCHY_INSTALL/post-install/allow-reboot.sh' \
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
SigLevel = Optional TrustAll
Server = file:///var/cache/omarchy/mirror/offline/
PACMAN
cp "$offline_system_root/etc/pacman.conf" \
  "$test_root/offline-pacman-original.conf"
offline_output=$(
  OMARCHY_CHROOT_INSTALL=1 \
    QVOS_SECURITY_TESTING=1 \
    QVOS_SECURITY_SYSTEM_ROOT="$offline_system_root" \
    OMARCHY_PATH="$root" \
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
  OMARCHY_PATH="$root" \
  "$installer" >/dev/null 2>&1; then
  fail "offline Pacman policy accepted outside the ISO chroot"
fi

printf 'Server = file:///tmp/untrusted/\n' \
  >>"$offline_system_root/etc/pacman.conf"
if OMARCHY_CHROOT_INSTALL=1 \
  QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$offline_system_root" \
  OMARCHY_PATH="$root" \
  "$installer" >/dev/null 2>&1; then
  fail "ambiguous ISO offline mirror accepted"
fi
[[ ! -e $offline_system_root/etc/sysctl.d/60-qvos-security.conf ]] ||
  fail "ambiguous ISO offline mirror causes partial installation"

cp "$root/default/pacman/pacman-rc.conf" \
  "$offline_system_root/etc/pacman.conf"
OMARCHY_CHROOT_INSTALL=1 \
  QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$offline_system_root" \
  OMARCHY_PATH="$root" \
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
  OMARCHY_PATH="$root" \
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
  "$system_install_tree/cache/test-package/dist" \
  "$system_install_tree/global/node_modules/test-package" \
  "$security_system_root/usr/local/bin"
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
QVOS_SECURITY_TESTING=1 \
  QVOS_SECURITY_SYSTEM_ROOT="$security_system_root" \
  OMARCHY_PATH="$root" \
  "$installer"
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
reload_line=$(grep -nF \
  'as_root /usr/bin/systemctl daemon-reload || return' \
  "$boot_mount" | cut -d: -f1)
remount_line=$(grep -nF \
  'as_root /usr/bin/mount -o remount /boot' \
  "$boot_mount" | cut -d: -f1)
[[ $reload_line =~ ^[0-9]+$ && $remount_line =~ ^[0-9]+$ ]] ||
  fail "EFI remount reload lifecycle"
((reload_line < remount_line)) ||
  fail "EFI mount units reload before remount"
grep -Fq 'reload_and_remount_boot || remount_status=$?' "$boot_mount" ||
  fail "EFI mount apply uses the reload lifecycle"
grep -Fq 'reload_and_remount_boot || true' "$boot_mount" ||
  fail "EFI mount rollback uses the reload lifecycle"

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

resolved_base=$("$root/qv/install/packaging/resolve" base)
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
