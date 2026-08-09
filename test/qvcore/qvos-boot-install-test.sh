#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
system_root="$test_root/system"
action_log="$test_root/actions.log"
swap_failure_marker="$test_root/swap-failed"
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
  exit 0
fi
if [[ ${QVOS_TEST_FAIL_THEME_SWAP:-} == "1" && $1 == "mv" &&
  ${3:-} == */.qvos-plymouth.* && ${3:-} != *-backup.* &&
  ${4:-} == */usr/share/plymouth/themes/omarchy &&
  ! -e $QVOS_TEST_SWAP_FAILURE_MARKER ]]; then
  : >"$QVOS_TEST_SWAP_FAILURE_MARKER"
  exit 1
fi
exec "$@"
SCRIPT

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
  (( $# > 0 )) || printf 'legacy\n'
  ;;
pacman)
  if [[ ${QVOS_TEST_PACMAN_ENTRIES:-} == "1" ]]; then
    printf '/+qvOS\n' >>"$QVOS_BOOT_TEST_ROOT/boot/limine.conf"
  fi
  ;;
snapper)
  if [[ ${1:-} == "list-configs" ]]; then
    printf 'Config | Subvolume\n-------+----------\n'
  fi
  ;;
limine-update)
  printf '/+qvOS\n' >>"$QVOS_BOOT_TEST_ROOT/boot/limine.conf"
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

install -d "$system_root/usr/share/plymouth/themes/omarchy"
printf 'stale\n' >"$system_root/usr/share/plymouth/themes/omarchy/stale"
run_boot "$root/qvcore/boot/install-plymouth"
[[ ! -e $system_root/usr/share/plymouth/themes/omarchy/stale ]] ||
  fail "Plymouth stale payload cleanup"
for source_file in "$root/qvcore/boot/plymouth/"*; do
  cmp -s \
    "$source_file" \
    "$system_root/usr/share/plymouth/themes/omarchy/${source_file##*/}" ||
    fail "Plymouth payload sync: ${source_file##*/}"
done
if grep -Eq '^(limine-mkinitcpio|mkinitcpio)' "$action_log"; then
  fail "fresh Plymouth install rebuilt boot images early"
fi

: >"$action_log"
run_boot "$root/qvcore/boot/refresh-plymouth"
[[ $(grep -c '^limine-mkinitcpio$' "$action_log") == "1" ]] ||
  fail "Plymouth refresh image rebuild"

printf 'stale\n' >"$system_root/usr/share/plymouth/themes/omarchy/stale"
install -d "$system_root/usr/share/sddm/themes/omarchy"
printf 'stale\n' >"$system_root/usr/share/sddm/themes/omarchy/stale"
: >"$action_log"
run_boot "$root/qvcore/boot/plymouth-reset"
[[ ! -e $system_root/usr/share/plymouth/themes/omarchy/stale ]] ||
  fail "Plymouth reset bypassed the shared refresh owner"
[[ ! -e $system_root/usr/share/sddm/themes/omarchy/stale ]] ||
  fail "Plymouth reset bypassed the shared SDDM owner"
[[ $(grep -c '^limine-mkinitcpio$' "$action_log") == "1" ]] ||
  fail "Plymouth reset duplicated the image rebuild"

printf 'prior\n' >"$system_root/usr/share/plymouth/themes/omarchy/prior"
export QVOS_TEST_FAIL_THEME_SWAP=1
if run_boot "$root/qvcore/boot/sync-theme" plymouth >/dev/null 2>&1; then
  fail "failed Plymouth swap reported success"
fi
unset QVOS_TEST_FAIL_THEME_SWAP
[[ $(<"$system_root/usr/share/plymouth/themes/omarchy/prior") == "prior" ]] ||
  fail "failed Plymouth swap did not restore the prior theme"

install -d "$system_root/etc/pam.d"
printf '%s\n' \
  'auth optional pam_unix.so' \
  '-auth optional pam_gnome_keyring.so' \
  '-password optional pam_gnome_keyring.so' \
  >"$system_root/etc/pam.d/sddm"
: >"$action_log"
run_boot "$root/qvcore/boot/install-sddm"
cmp -s \
  "$root/qvcore/boot/wayland-sessions/omarchy.desktop" \
  "$system_root/usr/local/share/wayland-sessions/omarchy.desktop" ||
  fail "SDDM qvOS session install"
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
grep -Fqx 'Session=omarchy' \
  "$system_root/etc/sddm.conf.d/autologin.conf" ||
  fail "SDDM compatibility session"
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
grep -Fqx 'Session=omarchy' \
  "$system_root/etc/sddm.conf.d/autologin.conf" ||
  fail "SDDM legacy session migration"

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
: >"$action_log"
export QVOS_TEST_PACMAN_ENTRIES=1
OMARCHY_CHROOT_INSTALL=1 run_boot "$root/qvcore/boot/install-limine-snapper"
unset QVOS_TEST_PACMAN_ENTRIES
grep -Fqx 'KERNEL_CMDLINE[default]+="root=UUID=test foo=a&b pipe=one|two slash=\value"' \
  "$system_root/etc/default/limine" ||
  fail "Limine literal kernel command line rendering"
grep -Fqx 'KERNEL_CMDLINE[default]+=" extra=1"' \
  "$system_root/etc/default/limine" ||
  fail "Limine drop-in merge"
grep -Fqx 'ENABLE_UKI=yes' "$system_root/etc/default/limine" ||
  fail "Limine EFI UKI preservation"
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
grep -Fqx $'pacman\t-S\t--noconfirm\t--needed\tlimine-snapper-sync\tlimine-mkinitcpio-hook' \
  "$action_log" || fail "Limine package transaction"
grep -Fqx $'btrfs\tquota\tdisable\t/' "$action_log" ||
  fail "Snapper quota performance policy"
grep -Fqx $'systemctl\tenable\tlimine-snapper-sync.service' "$action_log" ||
  fail "Limine snapshot service enable"
grep -Fqx $'efibootmgr\t-b\t0007\t-B' "$action_log" ||
  fail "legacy EFI entry cleanup"

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

chmod 0770 "$system_root"
if run_boot "$root/qvcore/boot/sync-theme" plymouth >/dev/null 2>&1; then
  fail "group-writable boot fixture root accepted"
fi

printf 'ok - qvOS boot installation is atomic, private-boot safe, and rebuild efficient\n'
