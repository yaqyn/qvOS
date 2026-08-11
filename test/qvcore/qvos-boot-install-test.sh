#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
system_root="$test_root/system"
action_log="$test_root/actions.log"
sudo_auth_log="$test_root/sudo-auth.log"
swap_failure_marker="$test_root/swap-failed"
package_installed_marker="$test_root/packages-installed"
test_user=$(id -un)

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_boot() {
  QVOS_BOOT_TESTING=1 \
    QVOS_BOOT_TEST_ROOT="$system_root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_SUDO_AUTH_LOG="$sudo_auth_log" \
    QVOS_TEST_PACKAGES_INSTALLED_MARKER="$package_installed_marker" \
    QVOS_TEST_SWAP_FAILURE_MARKER="$swap_failure_marker" \
    QVOS_PATH="$root" \
    OMARCHY_PATH="$test_root/stale-source" \
    USER="$test_user" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

install -d -m 0700 "$test_bin" "$system_root"
: >"$action_log"

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} == "-v" ]]; then
  printf '%s\n' '-v' >>"$QVOS_TEST_SUDO_AUTH_LOG"
  exit 0
fi
if [[ ${1:-} == "-n" && ${2:-} == "/usr/bin/true" && $# == 2 ]]; then
  printf '%s\n' '-n /usr/bin/true' >>"$QVOS_TEST_SUDO_AUTH_LOG"
  exit 0
fi
if [[ ${QVOS_TEST_FAIL_THEME_SWAP:-} == "1" && $1 == "mv" &&
  ${3:-} == */.qvos-plymouth.* && ${3:-} != *-backup.* &&
  ${4:-} == */usr/share/plymouth/themes/qvos &&
  ! -e $QVOS_TEST_SWAP_FAILURE_MARKER ]]; then
  : >"$QVOS_TEST_SWAP_FAILURE_MARKER"
  exit 1
fi
exec "$@"
SCRIPT

: >"$sudo_auth_log"
run_init() {
  QVOS_BOOT_TESTING=1 \
    QVOS_BOOT_TEST_ROOT="$system_root" \
    QVOS_TEST_SUDO_AUTH_LOG="$sudo_auth_log" \
    PATH="$test_bin:/usr/bin" \
    bash -c 'source "$1"; qvos_boot_init' _ \
    "$root/qvcore/boot/install-lib"
}
run_init
[[ $(<"$sudo_auth_log") == "-v" ]] ||
  fail "interactive boot authorization"
: >"$sudo_auth_log"
OMARCHY_CHROOT_INSTALL=1 run_init
[[ $(<"$sudo_auth_log") == "-n /usr/bin/true" ]] ||
  fail "noninteractive ISO boot authorization"

install -m 0755 /dev/stdin "$test_bin/qvos-test-boot-command" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

command_name=${0##*/}
{
  printf '%s' "$command_name"
  for argument in "$@"; do
    printf '\t%s' "$argument"
  done
  printf '\n'
} >>"$QVOS_TEST_ACTION_LOG"

case $command_name in
plymouth-set-default-theme)
  if [[ ${QVOS_TEST_FAIL_PLYMOUTH_SELECT:-} == "1" ]]; then
    exit 9
  fi
  (( $# > 0 )) || printf 'legacy\n'
  ;;
pacman)
  if [[ ${1:-} == "-Q" ]]; then
    [[ ${QVOS_TEST_PACKAGES_MISSING:-0} != "1" ||
      -e $QVOS_TEST_PACKAGES_INSTALLED_MARKER ]]
    exit
  fi
  if [[ ${1:-} == "-S" ]]; then
    : >"$QVOS_TEST_PACKAGES_INSTALLED_MARKER"
  fi
  if [[ ${QVOS_TEST_PACMAN_ENTRIES:-} == "1" ]]; then
    cmdline=$(
      sed -nE 's/^KERNEL_CMDLINE\[default\]\+="(.*)"$/\1/p' \
        "$QVOS_BOOT_TEST_ROOT/etc/default/limine" | head -n 1
    )
    printf '/+qvOS\ncmdline: %s\n' "$cmdline" \
      >>"$QVOS_BOOT_TEST_ROOT/boot/limine.conf"
    install -D -m 0644 /dev/stdin \
      "$QVOS_BOOT_TEST_ROOT/boot/EFI/Linux/qvos_linux.efi" <<<"qvOS UKI"
  fi
  ;;
snapper)
  if [[ ${1:-} == "--no-dbus" ]]; then
    shift
  fi
  if [[ ${1:-} == "list-configs" ]]; then
    printf 'Config | Subvolume\n-------+----------\n'
    if [[ -f $QVOS_BOOT_TEST_ROOT/etc/snapper/configs/root ]]; then
      printf 'root | /\n'
    fi
    [[ ${QVOS_TEST_SNAPPER_EMPTY_STATUS:-0} != "1" ]] || exit 1
  elif [[ ${1:-} == "-c" && ${2:-} == "root" &&
    ${3:-} == "create-config" && ${4:-} == "/" ]]; then
    [[ ${QVOS_TEST_SNAPPER_CREATE_FAIL:-0} != "1" ]] || exit 9
  fi
  ;;
limine-update)
  cmdline=$(
    sed -nE 's/^KERNEL_CMDLINE\[default\]\+="(.*)"$/\1/p' \
      "$QVOS_BOOT_TEST_ROOT/etc/default/limine" | head -n 1
  )
  printf '/+qvOS\ncmdline: %s\n' "$cmdline" \
    >>"$QVOS_BOOT_TEST_ROOT/boot/limine.conf"
  install -D -m 0644 /dev/stdin \
    "$QVOS_BOOT_TEST_ROOT/boot/EFI/Linux/qvos_linux.efi" <<<"qvOS UKI"
  ;;
efibootmgr)
  if (( $# == 0 )); then
    printf 'Boot0007* Arch Linux Limine\nBoot0008* qvOS\n'
  fi
  ;;
esac
SCRIPT

for command_name in \
  btrfs \
  efibootmgr \
  limine \
  limine-mkinitcpio \
  limine-update \
  mkinitcpio \
  pacman \
  plymouth-set-default-theme \
  snapper \
  systemctl; do
  ln -s qvos-test-boot-command "$test_bin/$command_name"
done

seed_legacy_plymouth_theme() {
  local target=$1
  local source_file
  local source_name
  local target_name

  install -d "$target"
  for source_file in "$root/qvcore/boot/plymouth/"*; do
    source_name=${source_file##*/}
    case $source_name in
    qvos.plymouth)
      target_name=omarchy.plymouth
      sed \
        -e 's#/themes/qvos#/themes/omarchy#g' \
        -e 's/qvos\.script/omarchy.script/g' \
        "$source_file" >"$target/$target_name"
      ;;
    qvos.script)
      target_name=omarchy.script
      sed '1s/.*/# Omarchy Plymouth Theme Script/' \
        "$source_file" >"$target/$target_name"
      ;;
    *)
      install -m 0644 "$source_file" "$target/$source_name"
      ;;
    esac
  done
}

install -d "$system_root/usr/share/plymouth/themes/qvos"
printf 'stale\n' >"$system_root/usr/share/plymouth/themes/qvos/stale"
install -d "$system_root/usr/share/plymouth/themes/omarchy"
seed_legacy_plymouth_theme "$system_root/usr/share/plymouth/themes/omarchy"
run_boot "$root/qvcore/boot/install-plymouth"
[[ ! -e $system_root/usr/share/plymouth/themes/qvos/stale ]] ||
  fail "Plymouth stale native payload cleanup"
[[ ! -e $system_root/usr/share/plymouth/themes/omarchy ]] ||
  fail "exact legacy Plymouth theme cleanup"
for source_file in "$root/qvcore/boot/plymouth/"*; do
  cmp -s \
    "$source_file" \
    "$system_root/usr/share/plymouth/themes/qvos/${source_file##*/}" ||
    fail "Plymouth payload sync: ${source_file##*/}"
done
if grep -Eq '^(limine-mkinitcpio|mkinitcpio)' "$action_log"; then
  fail "fresh Plymouth install rebuilt boot images early"
fi

seed_legacy_plymouth_theme "$system_root/usr/share/plymouth/themes/omarchy"
export QVOS_TEST_FAIL_PLYMOUTH_SELECT=1
if run_boot "$root/qvcore/boot/install-plymouth" >/dev/null 2>&1; then
  fail "failed Plymouth selection reported success"
fi
unset QVOS_TEST_FAIL_PLYMOUTH_SELECT
[[ -d $system_root/usr/share/plymouth/themes/omarchy ]] ||
  fail "legacy Plymouth theme retired before native selection"
run_boot "$root/qvcore/boot/install-plymouth"
[[ ! -e $system_root/usr/share/plymouth/themes/omarchy ]] ||
  fail "legacy Plymouth theme remained after native selection"

: >"$action_log"
run_boot "$root/qvcore/boot/refresh-plymouth"
[[ $(grep -c '^limine-mkinitcpio$' "$action_log") == "1" ]] ||
  fail "Plymouth refresh image rebuild"

install -d "$system_root/usr/share/plymouth/themes/omarchy"
printf 'modified\n' >"$system_root/usr/share/plymouth/themes/omarchy/custom"
printf 'stale\n' >"$system_root/usr/share/plymouth/themes/qvos/stale"
install -d "$system_root/usr/share/sddm/themes/qvos"
printf 'stale\n' >"$system_root/usr/share/sddm/themes/qvos/stale"
install -d "$system_root/usr/share/sddm/themes/omarchy"
printf 'modified\n' >"$system_root/usr/share/sddm/themes/omarchy/custom"
: >"$action_log"
run_boot "$root/qvcore/boot/plymouth-reset"
[[ ! -e $system_root/usr/share/plymouth/themes/qvos/stale ]] ||
  fail "Plymouth reset bypassed the shared refresh owner"
[[ ! -e $system_root/usr/share/sddm/themes/qvos/stale ]] ||
  fail "Plymouth reset bypassed the shared SDDM owner"
[[ $(<"$system_root/usr/share/plymouth/themes/omarchy/custom") == "modified" ]] ||
  fail "modified legacy Plymouth theme was removed"
[[ $(<"$system_root/usr/share/sddm/themes/omarchy/custom") == "modified" ]] ||
  fail "modified legacy SDDM theme was removed"
[[ $(grep -c '^limine-mkinitcpio$' "$action_log") == "1" ]] ||
  fail "Plymouth reset duplicated the image rebuild"

printf 'prior\n' >"$system_root/usr/share/plymouth/themes/qvos/prior"
export QVOS_TEST_FAIL_THEME_SWAP=1
if run_boot "$root/qvcore/boot/sync-theme" plymouth >/dev/null 2>&1; then
  fail "failed Plymouth swap reported success"
fi
unset QVOS_TEST_FAIL_THEME_SWAP
[[ $(<"$system_root/usr/share/plymouth/themes/qvos/prior") == "prior" ]] ||
  fail "failed Plymouth swap did not restore the prior theme"

install -d "$system_root/etc/pam.d"
printf '%s\n' \
  'auth optional pam_unix.so' \
  '-auth optional pam_gnome_keyring.so' \
  '-password optional pam_gnome_keyring.so' \
  >"$system_root/etc/pam.d/sddm"
install -d "$system_root/usr/local/share/wayland-sessions" \
  "$system_root/etc/sddm.conf.d" \
  "$system_root/var/lib/sddm"
sed 's/qvOS/Omarchy/g; s/UWSM/uwsm/g' \
  "$root/qvcore/boot/wayland-sessions/qvos.desktop" \
  >"$system_root/usr/local/share/wayland-sessions/omarchy.desktop"
printf '%s\n' \
  '[Theme]' \
  'Current=omarchy' \
  '' \
  '[Users]' \
  'RememberLastUser=true' \
  'RememberLastSession=true' \
  >"$system_root/etc/sddm.conf.d/99-omarchy-login.conf"
printf '[Theme]\nCurrent=omarchy\n' \
  >"$system_root/etc/sddm.conf.d/zz-omarchy.conf"
printf '[Theme]\nCurrent=qvos\n' \
  >"$system_root/etc/sddm.conf.d/zz-qvos-sddm.conf"
printf '[Last]\nSession=omarchy.desktop\n' \
  >"$system_root/var/lib/sddm/state.conf"
: >"$action_log"
run_boot "$root/qvcore/boot/install-sddm"
cmp -s \
  "$root/qvcore/boot/wayland-sessions/qvos.desktop" \
  "$system_root/usr/local/share/wayland-sessions/qvos.desktop" ||
  fail "SDDM qvOS session install"
[[ ! -e $system_root/usr/local/share/wayland-sessions/omarchy.desktop ]] ||
  fail "exact legacy SDDM session cleanup"
cmp -s \
  "$root/qvcore/boot/sddm-hyprland.conf" \
  "$system_root/usr/share/sddm/hyprland.conf" ||
  fail "SDDM compositor config install"
grep -Fqx 'DisplayServer=wayland' \
  "$system_root/etc/sddm.conf.d/10-wayland.conf" ||
  fail "SDDM Wayland configuration"
grep -Fqx "User=$test_user" \
  "$system_root/etc/sddm.conf.d/autologin.conf" ||
  fail "SDDM autologin user"
grep -Fqx 'Session=qvos' \
  "$system_root/etc/sddm.conf.d/autologin.conf" ||
  fail "SDDM native session"
grep -Fqx 'Current=qvos' "$system_root/etc/sddm.conf.d/qvos.conf" ||
  fail "SDDM native theme selection"
[[ ! -e $system_root/etc/sddm.conf.d/zz-omarchy.conf &&
  ! -e $system_root/etc/sddm.conf.d/zz-qvos-sddm.conf ]] ||
  fail "duplicate SDDM theme configuration cleanup"
[[ -f $system_root/etc/sddm.conf.d/99-qvos-login.conf &&
  ! -e $system_root/etc/sddm.conf.d/99-omarchy-login.conf ]] ||
  fail "legacy SDDM login configuration migration"
if rg -q '^Current=' "$system_root/etc/sddm.conf.d/99-qvos-login.conf"; then
  fail "SDDM login state duplicates native theme ownership"
fi
grep -Fqx 'Session=qvos.desktop' "$system_root/var/lib/sddm/state.conf" ||
  fail "SDDM state identity migration"
[[ $(<"$system_root/etc/pam.d/sddm") == 'auth optional pam_unix.so' ]] ||
  fail "SDDM keyring PAM cleanup"
grep -Fqx $'systemctl\tenable\tsddm.service' "$action_log" ||
  fail "SDDM service enable"

printf '%s\n' \
  '[Autologin]' \
  "User=$test_user" \
  'Session=custom-session' \
  '' \
  '[Theme]' \
  'Current=custom-theme' \
  >"$system_root/etc/sddm.conf.d/autologin.conf"
run_boot "$root/qvcore/boot/install-sddm"
grep -Fqx 'Session=custom-session' \
  "$system_root/etc/sddm.conf.d/autologin.conf" ||
  fail "SDDM custom session preservation"
grep -Fqx 'Current=custom-theme' \
  "$system_root/etc/sddm.conf.d/autologin.conf" ||
  fail "SDDM custom theme preservation"

sed -i 's/^Session=custom-session$/Session=hyprland-uwsm/' \
  "$system_root/etc/sddm.conf.d/autologin.conf"
run_boot "$root/qvcore/boot/install-sddm-session"
grep -Fqx 'Session=qvos' \
  "$system_root/etc/sddm.conf.d/autologin.conf" ||
  fail "SDDM legacy session migration"

external_login="$test_root/external-login"
printf 'foreign\n' >"$external_login"
rm -f -- "$system_root/etc/sddm.conf.d/99-qvos-login.conf"
ln -s "$external_login" "$system_root/etc/sddm.conf.d/99-qvos-login.conf"
printf '%s\n' \
  '[Theme]' \
  'Current=omarchy' \
  '' \
  '[Users]' \
  'RememberLastUser=true' \
  'RememberLastSession=true' \
  >"$system_root/etc/sddm.conf.d/99-omarchy-login.conf"
run_boot "$root/qvcore/boot/install-sddm-session" >/dev/null 2>&1
[[ -f $system_root/etc/sddm.conf.d/99-omarchy-login.conf &&
  $(<"$external_login") == "foreign" ]] ||
  fail "unsafe native SDDM login target did not preserve legacy state"

external_pam="$test_root/external-pam"
printf 'foreign\n' >"$external_pam"
rm -f -- "$system_root/etc/pam.d/sddm"
ln -s "$external_pam" "$system_root/etc/pam.d/sddm"
if run_boot "$root/qvcore/boot/install-sddm" >/dev/null 2>&1; then
  fail "SDDM followed a symbolic-link PAM target"
fi
[[ $(<"$external_pam") == "foreign" ]] ||
  fail "SDDM changed a symbolic-link PAM target"
rm -f -- "$system_root/etc/pam.d/sddm"

prepare_limine_root() {
  local fixture_root=$1
  local cmdline=$2

  install -d -m 0700 \
    "$fixture_root" \
    "$fixture_root/boot/EFI/BOOT" \
    "$fixture_root/etc/limine-entry-tool.d" \
    "$fixture_root/etc/mkinitcpio.conf.d" \
    "$fixture_root/sys/firmware/efi" \
    "$fixture_root/usr/share/libalpm/hooks"
  printf 'cmdline: %s\n' "$cmdline" \
    >"$fixture_root/boot/EFI/BOOT/limine.conf"
  printf 'KERNEL_CMDLINE[default]+=" extra=1"\n' \
    >"$fixture_root/etc/limine-entry-tool.d/10-extra.conf"
  printf 'disabled install hook\n' \
    >"$fixture_root/usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled"
  printf 'disabled remove hook\n' \
    >"$fixture_root/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled"
}

system_root="$test_root/limine-hook"
prepare_limine_root \
  "$system_root" \
  'root=UUID=test foo=a&b pipe=one|two slash=\value'
printf '%s' \
  $'HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)\nFILES+=(/etc/vconsole.conf)\n' \
  >"$system_root/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
install -D -m 0644 /dev/null \
  "$system_root/boot/EFI/Linux/omarchy_linux.efi"
: >"$action_log"
export QVOS_TEST_PACMAN_ENTRIES=1
export QVOS_TEST_PACKAGES_MISSING=1
export QVOS_TEST_SNAPPER_EMPTY_STATUS=1
OMARCHY_CHROOT_INSTALL=1 run_boot "$root/qvcore/boot/install-limine-snapper"
unset QVOS_TEST_PACKAGES_MISSING QVOS_TEST_PACMAN_ENTRIES \
  QVOS_TEST_SNAPPER_EMPTY_STATUS
grep -Fqx 'KERNEL_CMDLINE[default]+="root=UUID=test foo=a&b pipe=one|two slash=\value"' \
  "$system_root/etc/default/limine" ||
  fail "Limine literal kernel command line rendering"
grep -Fqx 'KERNEL_CMDLINE[default]+=" extra=1"' \
  "$system_root/etc/default/limine" ||
  fail "Limine drop-in merge"
grep -Fqx 'ENABLE_UKI=yes' "$system_root/etc/default/limine" ||
  fail "Limine EFI UKI preservation"
grep -Fqx 'CUSTOM_UKI_NAME="qvos"' "$system_root/etc/default/limine" ||
  fail "Limine native UKI identity"
[[ -f $system_root/etc/mkinitcpio.conf.d/qvos_hooks.conf &&
  ! -e $system_root/etc/mkinitcpio.conf.d/omarchy_hooks.conf ]] ||
  fail "mkinitcpio hook identity migration"

[[ -f $system_root/boot/EFI/Linux/qvos_linux.efi &&
  ! -e $system_root/boot/EFI/Linux/omarchy_linux.efi ]] ||
  fail "verified UKI identity migration"
[[ ! -e $system_root/boot/EFI/BOOT/limine.conf ]] ||
  fail "Limine conflicting config cleanup"
grep -q '^/+' "$system_root/boot/limine.conf" ||
  fail "Limine generated entry preservation"
if grep -q '^limine-update' "$action_log"; then
  fail "Limine rebuilt images after package hooks produced entries"
fi
cmp -s \
  "$root/qvcore/boot/snapper-root.conf" \
  "$system_root/etc/snapper/configs/root" ||
  fail "Snapper root-only policy install"
for hook in 90-mkinitcpio-install.hook 60-mkinitcpio-remove.hook; do
  [[ -f $system_root/usr/share/libalpm/hooks/$hook ]] ||
    fail "mkinitcpio hook restoration: $hook"
  [[ ! -e $system_root/usr/share/libalpm/hooks/$hook.disabled ]] ||
    fail "disabled mkinitcpio hook residue: $hook"
done
grep -Fqx $'pacman\t-S\t--noconfirm\t--needed\t--\tinotify-tools\tlimine-mkinitcpio-hook\tlimine-snapper-sync' \
  "$action_log" || fail "Limine package transaction"
grep -Fqx $'snapper\t--no-dbus\t-c\troot\tcreate-config\t/' "$action_log" ||
  fail "empty Snapper inventory root creation"
grep -Fqx $'btrfs\tquota\tdisable\t/' "$action_log" ||
  fail "Snapper quota performance policy"
grep -Fqx $'systemctl\tenable\tlimine-snapper-sync.service' "$action_log" ||
  fail "Limine snapshot service enable"
grep -Fqx $'efibootmgr\t-b\t0007\t-B' "$action_log" ||
  fail "legacy EFI entry cleanup"
: >"$action_log"
OMARCHY_CHROOT_INSTALL=1 run_boot "$root/qvcore/boot/install-limine-snapper"
if grep -q '^limine-update' "$action_log"; then
  fail "unchanged Limine header forced a second UKI rebuild"
fi
if grep -q $'^pacman\t-S\t' "$action_log"; then
  fail "unchanged Limine retry required a synchronization database"
fi
grep -q '^/+qvOS' "$system_root/boot/limine.conf" ||
  fail "unchanged Limine reconciliation lost generated entries"

printf 'KERNEL_CMDLINE[default]+=" extra=2"\n' \
  >"$system_root/etc/limine-entry-tool.d/10-extra.conf"
: >"$action_log"
OMARCHY_CHROOT_INSTALL=1 run_boot "$root/qvcore/boot/install-limine-snapper"
[[ $(grep -c '^limine-update$' "$action_log") == "1" ]] ||
  fail "changed Limine inputs did not rebuild exactly once"
grep -Fqx 'KERNEL_CMDLINE[default]+=" extra=2"' \
  "$system_root/etc/default/limine" ||
  fail "changed Limine drop-in did not reach native defaults"

system_root="$test_root/limine-interrupted"
prepare_limine_root "$system_root" 'root=UUID=interrupted quiet'
: >"$action_log"
export QVOS_TEST_SNAPPER_EMPTY_STATUS=1
export QVOS_TEST_SNAPPER_CREATE_FAIL=1
if OMARCHY_CHROOT_INSTALL=1 \
  run_boot "$root/qvcore/boot/install-limine-snapper" >/dev/null 2>&1; then
  fail "failed Snapper creation reported boot success"
fi
unset QVOS_TEST_SNAPPER_CREATE_FAIL
if grep -q '^[[:space:]]*cmdline:' "$system_root/boot/limine.conf"; then
  fail "interrupted boot fixture retained its original command-line source"
fi
install -D -m 0644 /dev/stdin \
  "$system_root/boot/EFI/Linux/qvos_linux.efi" <<<"existing qvOS UKI"
OMARCHY_CHROOT_INSTALL=1 run_boot "$root/qvcore/boot/install-limine-snapper"
unset QVOS_TEST_SNAPPER_EMPTY_STATUS
grep -Fqx \
  'KERNEL_CMDLINE[default]+="root=UUID=interrupted quiet"' \
  "$system_root/etc/default/limine" ||
  fail "interrupted Limine command-line recovery"
grep -q '^/+qvOS' "$system_root/boot/limine.conf" ||
  fail "interrupted Limine generated-entry recovery"

system_root="$test_root/limine-legacy-hooks"
prepare_limine_root "$system_root" 'root=UUID=legacy-hooks quiet'
printf '%s\n' \
  'HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)' \
  >"$system_root/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
: >"$action_log"
OMARCHY_CHROOT_INSTALL=1 run_boot "$root/qvcore/boot/install-limine-snapper"
[[ ! -e $system_root/etc/mkinitcpio.conf.d/omarchy_hooks.conf ]] ||
  fail "historical mkinitcpio hook identity remains"

system_root="$test_root/limine-modified-hooks"
prepare_limine_root "$system_root" 'root=UUID=modified-hooks quiet'
printf '%s\n' 'HOOKS=(base custom filesystems)' \
  >"$system_root/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
legacy_hook_warning=$(
  OMARCHY_CHROOT_INSTALL=1 \
    run_boot "$root/qvcore/boot/install-limine-snapper" 2>&1 >/dev/null
)
[[ -f $system_root/etc/mkinitcpio.conf.d/omarchy_hooks.conf ]] ||
  fail "modified legacy mkinitcpio hook was removed"
grep -Fq 'Preserving modified or unsafe legacy boot artifact:' \
  <<<"$legacy_hook_warning" ||
  fail "modified legacy mkinitcpio hook warning"

system_root="$test_root/limine-fallback"
prepare_limine_root "$system_root" 'root=UUID=fallback quiet'
: >"$action_log"
OMARCHY_CHROOT_INSTALL=1 run_boot "$root/qvcore/boot/install-limine-snapper"
[[ $(grep -c '^limine-update$' "$action_log") == "1" ]] ||
  fail "Limine missing-entry fallback rebuild"

system_root="$test_root/limine-invalid"
prepare_limine_root "$system_root" ''
: >"$action_log"
if OMARCHY_CHROOT_INSTALL=1 \
  run_boot "$root/qvcore/boot/install-limine-snapper" >/dev/null 2>&1; then
  fail "Limine accepted an empty kernel command line"
fi
if grep -q '^pacman' "$action_log"; then
  fail "invalid Limine input reached package mutation"
fi
for hook in 90-mkinitcpio-install.hook 60-mkinitcpio-remove.hook; do
  [[ -f $system_root/usr/share/libalpm/hooks/$hook ]] ||
    fail "failure-path mkinitcpio hook restoration: $hook"
done

system_root="$test_root/no-limine"
install -d -m 0700 "$system_root/usr/share/libalpm/hooks"
printf 'disabled\n' \
  >"$system_root/usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled"
: >"$action_log"
export QVOS_BOOT_TEST_NO_LIMINE=1
run_boot "$root/qvcore/boot/install-limine-snapper"
unset QVOS_BOOT_TEST_NO_LIMINE
[[ -f $system_root/usr/share/libalpm/hooks/90-mkinitcpio-install.hook ]] ||
  fail "non-Limine hook restoration"
if grep -Eq '^(pacman|limine-update)' "$action_log"; then
  fail "non-Limine host reached Limine mutation"
fi

system_root="$test_root/identity-migration"
install -d -m 0700 "$system_root/etc/pam.d"
printf 'auth optional pam_unix.so\n' >"$system_root/etc/pam.d/sddm"
: >"$action_log"
export QVOS_BOOT_TEST_NO_LIMINE=1
run_boot "$root/qvcore/boot/migrate-identity"
unset QVOS_BOOT_TEST_NO_LIMINE
[[ -f $system_root/usr/share/plymouth/themes/qvos/qvos.plymouth &&
  -f $system_root/usr/share/sddm/themes/qvos/Main.qml &&
  -f $system_root/usr/local/share/wayland-sessions/qvos.desktop ]] ||
  fail "existing-system boot identity migration"

chmod 0770 "$system_root"
if run_boot "$root/qvcore/boot/sync-theme" plymouth >/dev/null 2>&1; then
  fail "group-writable boot fixture root accepted"
fi

printf 'ok - qvOS boot installation is atomic, private-boot safe, and rebuild efficient\n'
