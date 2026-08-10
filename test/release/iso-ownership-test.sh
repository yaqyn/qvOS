#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="$root/release/iso"
build="$release_root/build"
builder="$release_root/builder/build-iso.sh"
profile="$release_root/profile"
installer="$profile/airootfs/root/.automated_script.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

[[ ! -e $root/qvcore/iso ]] || fail "ISO implementation remains in qvCORE"
[[ -x $build && -x $builder && -f $profile/profiledef.sh ]] ||
  fail "release-owned native image builder"
[[ -x $root/qvcore/tui/bin/qvos-build ]] ||
  fail "installed image-build adapter"
(( $(wc -l <"$root/qvcore/tui/bin/qvos-build") <= 15 )) ||
  fail "TUI image-build adapter contains release implementation"
grep -Fq 'release/iso/build' "$root/qvcore/tui/bin/qvos-build" ||
  fail "TUI adapter bypasses the release owner"
grep -Fq 'native qvOS Archiso builder and profile' "$root/qvcore/README.md" ||
  fail "qvCORE architecture does not describe the native ISO owner"
if rg -n 'source-backed Omarchy ISO|stages .*Omarchy ISO' "$root/qvcore/README.md"; then
  fail "qvCORE architecture retains the retired patched ISO model"
fi

for retired in \
  "$release_root/omarchy-iso-qvos-tui.patch" \
  "$release_root/upstream-ref"; do
  [[ ! -e $retired && ! -L $retired ]] ||
    fail "runtime ISO upstream seam remains: ${retired#"$root/"}"
done
if rg -q "QVOS_OMARCHY_ISO|OMARCHY_ISO_REF|patch_omarchy|staged_iso|(^|[[:space:]\"'])/archiso(/|[[:space:]\"']|$)" \
  "$build" "$builder"; then
  fail "native ISO builder still executes an Omarchy ISO source"
fi
grep -Fq '/usr/share/archiso/configs/releng/' "$builder" ||
  fail "native ISO does not use the signed Archiso releng profile"
grep -Fq 'pacman --noconfirm -Syu --needed' "$builder" ||
  fail "native ISO permits a partial build-container upgrade"
grep -Fq -- '--pull=always' "$build" ||
  fail "native ISO reuses a stale mutable build container"

# shellcheck disable=SC2016
grep -Fq 'provider_channel="${QVOS_PROVIDER_CHANNEL:-stable}"' "$build" ||
  fail "release image does not default to Stable"
grep -Fq 'provider_channel=edge' "$build" ||
  fail "release image lacks explicit Edge selection"
grep -Fq 'provider_channel=rc' "$build" ||
  fail "release image lacks explicit RC selection"
set +e
invalid_channel_output=$(
  QVOS_PROVIDER_CHANNEL='../edge' "$build" --prepare-only 2>&1
)
invalid_channel_status=$?
set -e
((invalid_channel_status == 2)) || fail "release image invalid-channel status"
grep -Fq 'QVOS_PROVIDER_CHANNEL must be stable, edge, or rc.' \
  <<<"$invalid_channel_output" || fail "release image accepts an unsafe channel"

# shellcheck disable=SC2016
grep -Fq 'if [[ ! -x $target/release/iso/builder/build-iso.sh ]]; then' \
  "$build" || fail "release ISO native builder validation"
# shellcheck disable=SC2016
grep -Fq 'if [[ ! -f $target/release/iso/profile/profiledef.sh ]]; then' \
  "$build" || fail "release ISO native profile validation"
grep -Fq 'validate_native_iso "$native_iso"' "$build" ||
  fail "release ISO staged trust validation"
grep -Fq -- '-v "$iso_root/builder:/builder:ro"' "$build" ||
  fail "release ISO native builder read-only mount"
grep -Fq -- '-v "$iso_root/profile:/profile:ro"' "$build" ||
  fail "release ISO native profile read-only mount"
grep -Fq -- '-v "$staged_qvos:/qvos:ro"' "$build" ||
  fail "release ISO pinned qvOS source mount"
grep -Fq 'QVOS_UPDATE_REPO must be a public HTTPS Git URL without credentials.' \
  "$build" || fail "release ISO public update-origin validation"
grep -Fq 'remote set-url origin "$qvos_update_repo"' "$build" ||
  fail "release ISO does not sanitize its embedded update origin"
grep -Fq -- '--depth 1 --single-branch --branch OS --no-tags' "$build" ||
  fail "release ISO embeds unnecessary Git history"
grep -Fq 'source retains unrelated history or tags' "$build" ||
  fail "release ISO does not reject historical Git objects"
grep -Fq '"$target/.git/FETCH_HEAD"' "$build" ||
  fail "release ISO retains transient clone provenance"

grep -Fq '/qvcore/packages/provider-files' "$builder" ||
  fail "release ISO bypasses qvOS provider validation"
grep -Fq 'qvcore/packages/provider/omarchy/signing-key.gpg' "$builder" ||
  fail "release ISO bypasses the reviewed provider key"
grep -Fq '40DFB630FF42BCFFB047046CF0134EE680CAC571' "$builder" ||
  fail "release ISO provider fingerprint"
grep -Fq '15d6aac44df688165b2ea35fe0b23af239bbc66a6909c10a5c219e8d94b707de' \
  "$builder" || fail "release ISO provider key payload digest"
grep -Fq 'package_file.sig' "$builder" ||
  fail "release ISO detached package signature retention"
grep -Fq 'Server = file:///var/cache/qvos/mirror/offline/' \
  "$profile/pacman-offline.conf" || fail "release ISO native offline mirror"
grep -Fqx 'SigLevel = Required DatabaseOptional' \
  "$profile/pacman-offline.conf" || fail "release ISO signed offline policy"
grep -Fqx 'LocalFileSigLevel = Required' \
  "$profile/pacman-offline.conf" || fail "release ISO signed local-package policy"
grep -Fq '["/var/cache/qvos/mirror/offline"]="0:0:755"' \
  "$profile/profiledef.sh" || fail "release ISO offline mirror permissions"
if grep -Fq '["/var/cache/qvos/mirror/offline/"]=' "$profile/profiledef.sh"; then
  fail "release ISO recursively overrides offline artifact permissions"
fi
grep -Fq "install -m 0644 \\" "$builder" ||
  fail "release ISO does not normalize offline package permissions"
grep -Fq 'find "$offline_mirror_dir" -maxdepth 1 -type f -exec chmod 0644 {} +' \
  "$builder" || fail "release ISO does not normalize repository metadata permissions"
grep -Fq 'multi-user.target.wants/sshd.service' "$builder" ||
  fail "release ISO does not disable automatic remote administration"
grep -Fq 'multi-user.target.wants/choose-mirror.service' "$builder" ||
  fail "release ISO does not disable inherited mirror discovery"
grep -Fq 'cloud-init.target.wants' "$builder" ||
  fail "release ISO does not disable inherited cloud bootstrap"
grep -Fqx 'unused_live_packages=(cloud-init dhcpcd reflector)' "$builder" ||
  fail "release ISO retains unsupported releng packages"
grep -Fq 'sed -i "/^${package}$/d" "$build_cache_dir/packages.x86_64"' \
  "$builder" || fail "release ISO does not prune unsupported releng packages"
grep -Fq 'Unsupported live-image package remains:' "$builder" ||
  fail "release ISO does not verify unsupported package removal"
if rg -n 'SigLevel[[:space:]]*=[[:space:]]*Never|TrustAll|arch-mact2|linux-t2' \
  "$builder" "$profile"; then
  fail "release ISO activates weak package trust or unsupported T2 packages"
fi

grep -Fq 'qvos-tui --iso-installer' "$installer" ||
  fail "release ISO bypasses the qvOS installer TUI"
grep -Fqx 'qvos' "$profile/airootfs/etc/hostname" ||
  fail "release ISO live hostname"
grep -Fq 'if [[ ! -f $target/qvcore/boot/install || -L $target/qvcore/boot/install ]]; then' "$build" ||
  fail "release ISO does not require the native qvOS boot owner"
if rg -n \
  '/etc/sddm\.conf\.d|/var/lib/sddm/state\.conf|^[[:space:]]*(Current|Session)=qvos(\.desktop)?$' \
  "$installer"; then
  fail "release ISO duplicates the native qvOS SDDM owner"
fi
grep -Fq 'systemctl start pacman-init.service' "$installer" ||
  fail "release ISO bypasses the Archiso keyring owner"
if rg -n 'pacman-key --(init|populate)' "$installer"; then
  fail "release ISO duplicates the Archiso keyring owner"
fi
grep -Fq "    --offline \\" "$installer" ||
  fail "release ISO invokes Archinstall as an online install"
grep -Fq "env --unset=XDG_RUNTIME_DIR \\" "$installer" ||
  fail "release ISO leaks the live session runtime into the target chroot"
grep -Fq 'qvos_target_mounts+=("$target")' "$installer" ||
  fail "release ISO does not record target bind mounts immediately"
grep -Fq 'cleanup_qvos_target_mounts' "$installer" ||
  fail "release ISO does not unwind target bind mounts"
grep -Fq 'qvOS installation returned without a completion marker.' "$installer" ||
  fail "release ISO accepts a partial qvOS finalizer"
grep -Fq 'arch-chroot /mnt mount /boot' "$installer" ||
  fail "release ISO does not remount the target ESP for native finalization"
grep -Fq 'boot_fstype == "vfat"' "$installer" ||
  fail "release ISO does not validate the remounted target ESP"
if rg -n 'fmask=0022|dmask=0022|chmod .*[/]boot' "$installer"; then
  fail "release ISO weakens the target ESP for unprivileged finalization"
fi
[[ ! -e $profile/airootfs/root/configurator ]] ||
  fail "release ISO ships a duplicate installer"
grep -Fq 'unexpected source digest' "$builder" ||
  fail "release ISO does not verify the built TUI"
grep -Fq -- '-buildvcs=false' "$builder" ||
  fail "release ISO TUI build includes ambient VCS state"
grep -Fq 'release/iso/source-permissions' "$builder" ||
  fail "release ISO bypasses tracked executable modes"
grep -Fq 'will not overwrite an existing release artifact' "$build" ||
  fail "release ISO can overwrite an existing artifact"
grep -Fq 'if ! ln -- "$partial_iso" "$target_iso"; then' "$build" ||
  fail "release ISO publication is not atomic and no-clobbering"
if rg -n 'source .*\|\| bash|python3\.[0-9]+/site-packages|OMARCHY_(USER|MIRROR|PATH|INSTALL)=' \
  "$installer" "$builder"; then
  fail "release ISO retains a fragile installer fallback or inherited identity"
fi
[[ $(
  rg -o 'OMARCHY_[A-Z_]+' "$installer" "$builder" | sed 's/.*://' | sort -u
) == "OMARCHY_CHROOT_INSTALL" ]] ||
  fail "release ISO retains an unreviewed inherited environment contract"

grep -Fq 'QVOS_PROVIDER_CHANNEL="$QVOS_PROVIDER_CHANNEL"' "$installer" ||
  fail "release ISO provider-channel boundary translation"
grep -Fq 'QVOS_USER_NAME="$(<user_full_name.txt)"' "$installer" ||
  fail "release ISO native user-name input"
grep -Fq 'QVOS_USER_EMAIL="$(<user_email_address.txt)"' "$installer" ||
  fail "release ISO native user-email input"
grep -Fq 'cp -a -- /root/qvos "/mnt/home/$QVOS_USER/.local/share/qvos"' \
  "$installer" || fail "release ISO canonical source copy"
grep -Fq 'ln -s qvos "/mnt/home/$QVOS_USER/.local/share/omarchy"' \
  "$installer" || fail "release ISO exact source compatibility link"

grep -Fq "'-comp' 'zstd'" "$profile/profiledef.sh" ||
  fail "release ISO live-root compression"
grep -Fq 'uncompressed@subpathname(var/cache/qvos/mirror/offline)' \
  "$profile/profiledef.sh" || fail "release ISO package recompression policy"
grep -Fq 'iso_name="qvos"' "$profile/profiledef.sh" ||
  fail "release ISO artifact identity"
grep -Fq 'iso_publisher="qvOS <https://github.com/Yaqyn-qvOS/qvOS>"' \
  "$profile/profiledef.sh" || fail "release ISO publisher identity"
boot_entry_count=$(rg -n \
  '^[[:space:]]*(options|linux|APPEND)[[:space:]].*archisobasedir=' \
  "$profile/efiboot" "$profile/grub" "$profile/syslinux" | wc -l)
sync_entry_count=$(rg -n \
  '^[[:space:]]*(options|linux|APPEND)[[:space:]].*archisobasedir=.*initramfs_async=0' \
  "$profile/efiboot" "$profile/grub" "$profile/syslinux" | wc -l)
if (( boot_entry_count == 0 || boot_entry_count != sync_entry_count )); then
  fail "release ISO permits asynchronous live initramfs unpacking"
fi

[[ -f $release_root/LICENSE.omarchy-iso ]] ||
  fail "native derivative lacks its upstream license"
grep -Fq '023cd14f2a64bad856e79714f79d8f9f09605727' \
  "$release_root/UPSTREAM.md" || fail "native derivative lacks exact provenance"

expected=$'AGENTS.md\nLICENSE.omarchy-iso\nREADME.md\nUPSTREAM.md\nbuild\nsource-permissions\nsyslinux-splash.png'
actual=$(find "$release_root" -maxdepth 1 -type f -printf '%f\n' | sort)
[[ $actual == "$expected" ]] || fail "release/iso source inventory"

printf 'ok - qvOS owns one native Archiso builder and one thin TUI adapter\n'
