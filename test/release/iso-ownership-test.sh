#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail
export LC_ALL=C

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="$root/release/iso"
release_contract="$release_root/AGENTS.md"
release_gate="$release_root/README.md"
build="$release_root/build"
builder="$release_root/builder/build-iso.sh"
cache_recovery="$release_root/builder/cache-recovery"
space_check="$release_root/space-check"
profile="$release_root/profile"
installer="$profile/airootfs/root/.automated_script.sh"
post_install_verifier="$root/qvcore/install/post-install/verify"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

[[ ! -e $root/qvcore/iso ]] || fail "ISO implementation remains in qvCORE"
[[ -x $build && -x $builder && -x $space_check && -f $cache_recovery &&
  ! -L $cache_recovery && -f $profile/profiledef.sh ]] ||
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
grep -Fq 'verify every virtual optical drive is empty' "$root/AGENTS.md" ||
  fail "root release lifecycle permits attached installation media"
grep -Fq 'verify every emulated optical drive reports no inserted medium' \
  "$release_contract" ||
  fail "ISO owner permits attached installation media during reboot proof"
grep -Fq 'every emulated optical drive is empty' "$release_gate" ||
  fail "release gate permits attached installation media during installed boot"
grep -Fq 'A hard reset can recover a disposable VM but is never reboot' \
  "$release_contract" ||
  fail "ISO owner accepts a hard reset as reboot proof"
grep -Fq 'a hypervisor reset does not satisfy this gate' "$release_gate" ||
  fail "release gate accepts a reset as installed-boot evidence"

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
if grep -Fq '"$HOME/.local/share/omarchy"' "$build"; then
  fail "native ISO builder infers product context from the compatibility path"
fi
grep -Fq 'git -C "$source_checkout" rev-parse --show-toplevel' "$build" ||
  fail "native ISO builder context does not derive from its owning checkout"
grep -Fq '/usr/share/archiso/configs/releng/' "$builder" ||
  fail "native ISO does not use the signed Archiso releng profile"
grep -Fq -- '--noconfirm -Syu --needed archiso git sudo base-devel jq grub go' \
  "$builder" ||
  fail "native ISO permits a partial build-container upgrade"
grep -Fq -- '--pull=always' "$build" ||
  fail "native ISO reuses a stale mutable build container"
grep -Fq 'stage_root=$(mktemp -d "$release_dir/.qvos-stage.XXXXXX")' \
  "$build" || fail "native ISO stage bypasses its release filesystem"
space_line=$(grep -Fn '"$space_check" "$release_dir" "$minimum_free_gib"' "$build" | cut -d: -f1)
stage_line=$(grep -Fn 'stage_root=$(mktemp -d "$release_dir/.qvos-stage.XXXXXX")' "$build" | cut -d: -f1)
if [[ -z $space_line || -z $stage_line ]] || (( space_line >= stage_line )); then
  fail "native ISO creates scratch before checking release-disk space"
fi
mirror_line=$(grep -Fn 'if [[ $arch_mirror != https://* ]]' "$build" | cut -d: -f1)
if [[ -z $mirror_line ]] || (( mirror_line >= stage_line )); then
  fail "native ISO creates scratch before validating its mirror input"
fi
grep -Fq 'qvOS ISO failed scratch will be removed; reusable download caches are preserved.' \
  "$build" || fail "native ISO retains ordinary failed build scratch"
grep -Fq 'retain_failed_stage=true' "$build" ||
  fail "native ISO lacks an explicit failed-stage debugging mode"
grep -Fq '(( status != 0 )) && [[ $retain_failed_stage == "true" ]]' "$build" ||
  fail "native ISO debugging mode does not retain every failed stage"
grep -Fq -- '-v "$cache_root:/var/cache"' "$build" ||
  fail "native ISO Archiso workspace bypasses its private stage"
grep -Fq 'using an empty one-shot build cache' "$build" ||
  fail "native ISO no-cache mode is not explicit"
grep -Fq -- '-v qvos-iso-pacman-cache:/var/cache/pacman/pkg' "$build" ||
  fail "native ISO does not preserve its reusable package cache"
grep -Fq -- '-v qvos-iso-tool-cache:/var/cache/qvos' "$build" ||
  fail "native ISO does not preserve its reusable tool cache"
grep -Fq -- '--pull=never' "$build" ||
  fail "native ISO stage ownership cleanup can pull mutable code"
grep -Fq 'chown -R "$1:$2" /cache && chmod -R u+rwX /cache' "$build" ||
  fail "native ISO leaves staged build data owned by Docker"
grep -Fq 'stage_cache_needs_release=true' "$build" ||
  fail "native ISO does not track interrupted Docker ownership"
grep -Fq '! release_staged_cache "$stage_cache"' "$build" ||
  fail "native ISO cannot release an interrupted build stage"
grep -Fq 'install -d -m 0755 "$stage_cache"' "$build" ||
  fail "native ISO blocks Pacman's sandboxed download user from its stage"
if rg -n 'DisableSandbox|DownloadUser[[:space:]]*=[[:space:]]*root' "$build" "$builder"; then
  fail "native ISO weakens Pacman's download sandbox for its stage cache"
fi

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
grep -Fq '! -f $cache_recovery || -L $cache_recovery' "$build" ||
  fail "release ISO does not validate its cache recovery owner"
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
grep -Fq 'source /builder/cache-recovery' "$builder" ||
  fail "release ISO bypasses its cache recovery owner"
grep -Fq 'quarantine_corrupt_cache_entries()' "$cache_recovery" ||
  fail "release ISO lacks exact corrupted-cache recovery"
grep -Fq 'Refusing unsafe Pacman cache recovery target:' "$cache_recovery" ||
  fail "release ISO accepts unsafe cache recovery targets"
grep -Fq 'Retrying Pacman with fresh signed package data' "$cache_recovery" ||
  fail "release ISO does not retry a verified stale cache entry"
if grep -Eq 'pacman[[:space:]].*-Scc|rm -rf.*pacman/pkg' \
  "$builder" "$cache_recovery"; then
  fail "release ISO clears the reusable package cache broadly"
fi
grep -Fq '[[ -d $tool_mirror_root && ! -L $tool_mirror_root ]]' "$builder" ||
  fail "release ISO follows an unsafe reusable tool-cache mirror root"
grep -Fq '$(readlink -- "$tool_mirror_link") == "$offline_mirror_dir"' \
  "$builder" || fail "release ISO accepts a foreign cached offline mirror"
grep -Fq 'unsafe qvOS tool-cache offline mirror entry' "$builder" ||
  fail "release ISO does not reject tool-cache drift"

cache_test_root=$(mktemp -d)
trap 'rm -rf -- "$cache_test_root"' EXIT
"$space_check" "$cache_test_root" 1 >/dev/null 2>&1 ||
  fail "native ISO free-space owner rejects adequate storage"
set +e
space_output=$("$space_check" "$cache_test_root" 1048576 2>&1)
space_status=$?
set -e
(( space_status == 1 )) || fail "native ISO free-space owner accepts inadequate storage"
grep -Fq 'qvos-build needs at least' <<<"$space_output" ||
  fail "native ISO free-space owner lacks an actionable failure"
ln -s "$cache_test_root" "$cache_test_root-linked"
if "$space_check" "$cache_test_root-linked" 1 >/dev/null 2>&1; then
  fail "native ISO free-space owner accepts a linked release directory"
fi
unlink -- "$cache_test_root-linked"
test_bin="$cache_test_root/bin"
package_cache_dir="$cache_test_root/cache"
cache_quarantine_dir="$cache_test_root/quarantine"
test_package="$package_cache_dir/qvos-test-1-1-any.pkg.tar.zst"
test_state="$cache_test_root/pacman-attempt"
mkdir -p "$test_bin" "$package_cache_dir" "$cache_quarantine_dir"
install -m 0644 /dev/null "$test_package"
install -m 0644 /dev/null "$test_package.sig"
install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

attempt=0
[[ ! -f $QVOS_TEST_STATE ]] || attempt=$(<"$QVOS_TEST_STATE")
((attempt += 1))
printf '%s\n' "$attempt" >"$QVOS_TEST_STATE"
if ((attempt == 1)); then
  printf ':: File %s is corrupted (invalid or corrupted package (checksum)).\n' \
    "$QVOS_TEST_PACKAGE"
  exit 1
fi
SCRIPT
export QVOS_TEST_PACKAGE="$test_package"
export QVOS_TEST_STATE="$test_state"
# shellcheck source=release/iso/builder/cache-recovery
# shellcheck disable=SC1091
source "$cache_recovery"
PATH="$test_bin:$PATH" pacman_with_cache_recovery --noconfirm -Sy qvos-test \
  >/dev/null 2>&1 || fail "release ISO cache recovery retry"
[[ $(<"$test_state") == "2" && ! -e $test_package &&
  ! -e $test_package.sig ]] || fail "release ISO exact stale-cache quarantine"
(( $(find "$cache_quarantine_dir" -maxdepth 1 -type f | wc -l) == 2 )) ||
  fail "release ISO stale-cache quarantine inventory"

removed_package="$package_cache_dir/qvos-removed-1-1-any.pkg.tar.zst"
removed_log="$cache_test_root/removed.log"
install -m 0644 /dev/null "$removed_package.sig"
printf ':: File %s is corrupted (invalid or corrupted package (checksum)).\n' \
  "$removed_package" >"$removed_log"
quarantine_corrupt_cache_entries "$removed_log" >/dev/null 2>&1 ||
  fail "release ISO rejects an exact cache entry Pacman already removed"
[[ ! -e $removed_package.sig &&
  -f $cache_quarantine_dir/${removed_package##*/}.sig ]] ||
  fail "release ISO leaves the removed cache entry signature behind"

unsafe_package="$cache_test_root/outside.pkg.tar.zst"
unsafe_log="$cache_test_root/unsafe.log"
install -m 0644 /dev/null "$unsafe_package"
printf ':: File %s is corrupted (invalid or corrupted package (checksum)).\n' \
  "$unsafe_package" >"$unsafe_log"
set +e
quarantine_corrupt_cache_entries "$unsafe_log" >/dev/null 2>&1
unsafe_status=$?
set -e
((unsafe_status == 2)) || fail "release ISO unsafe cache target status"
[[ -f $unsafe_package ]] || fail "release ISO moved an unsafe cache target"

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
grep -Fqx 'repository_databases=(core extra multilib omarchy)' "$builder" ||
  fail "release ISO does not retain the resolved repository databases"
grep -Fq 'install -m 0644 -- "$database" "$repository_sync_dir/$repository.db"' \
  "$builder" || fail "release ISO does not stage repository database seeds"
grep -Fq 'resolved repository database inventory is unexpected' "$builder" ||
  fail "release ISO does not verify its repository database seed inventory"
grep -Fq '["/var/cache/qvos/mirror/sync"]="0:0:755"' \
  "$profile/profiledef.sh" || fail "release ISO repository database permissions"
grep -Fq 'multi-user.target.wants/sshd.service' "$builder" ||
  fail "release ISO does not disable automatic remote administration"
grep -Fq 'multi-user.target.wants/choose-mirror.service' "$builder" ||
  fail "release ISO does not disable inherited mirror discovery"
grep -Fq 'airootfs/etc/systemd/system/choose-mirror.service' "$builder" ||
  fail "release ISO retains the inherited mirror-discovery unit"
grep -Fq 'airootfs/usr/local/bin/choose-mirror' "$builder" ||
  fail "release ISO retains the inherited mirror-discovery executable"
if grep -Fq '["/usr/local/bin/choose-mirror"]=' "$profile/profiledef.sh"; then
  fail "release ISO retains inherited mirror-discovery permissions"
fi
grep -Fq 'cloud-init.target.wants' "$builder" ||
  fail "release ISO does not disable inherited cloud bootstrap"
grep -Fqx 'unused_live_packages=(cloud-init dhcpcd reflector)' "$builder" ||
  fail "release ISO retains unsupported releng packages"
grep -Fq 'sed -i "/^${package}$/d" "$build_cache_dir/packages.x86_64"' \
  "$builder" || fail "release ISO does not prune unsupported releng packages"
grep -Fq 'Unsupported live-image package remains:' "$builder" ||
  fail "release ISO does not verify unsupported package removal"
grep -Fq 'qvcore/install/system/printing-resolver.conf' "$builder" ||
  fail "release ISO duplicates or omits the native resolver policy"
grep -Fq 'zz-qvos-live.conf' "$builder" ||
  fail "release ISO does not stage its resolver privacy boundary"
grep -Fq 'resolver_upstream_target="$resolver_policy_dir/archiso.conf"' \
  "$builder" || fail "release ISO retains Archiso resolver discovery"
grep -Fq 'rm -f -- "$resolver_upstream_target"' "$builder" ||
  fail "release ISO does not retire Archiso resolver discovery"
grep -Fq 'cmp -s -- "$resolver_policy_source" "$native_policy"' \
  "$builder" ||
  fail "release ISO does not verify its staged resolver policy"
grep -Fq \
  'The staged live resolver configuration re-enables local discovery.' \
  "$builder" || fail "release ISO does not reject resolver policy conflicts"
grep -Fq \
  'validate_live_resolver_policy "$build_cache_dir/airootfs"' \
  "$builder" || fail "release ISO does not inspect its staged resolver policy"
grep -Fq \
  'validate_live_resolver_policy "$build_cache_dir/work/x86_64/airootfs"' \
  "$builder" || fail "release ISO does not inspect its assembled resolver policy"
grep -Fq '["/etc/systemd/resolved.conf.d/zz-qvos-live.conf"]="0:0:644"' \
  "$profile/profiledef.sh" ||
  fail "release ISO resolver policy permissions"
grep -Fq 'identity_source="$qvos_source/qvcore/branding/os-release"' "$builder" ||
  fail "release ISO duplicates or omits the native qvOS system identity"
grep -Fq '["/etc/os-release"]="0:0:644"' "$profile/profiledef.sh" ||
  fail "release ISO system identity permissions"
grep -Fq 'https://nodejs.org/dist/index.json' "$builder" ||
  fail "release ISO does not resolve Node.js from official release metadata"
grep -Fq 'select(.lts != false and ((.files // []) | index("linux-x64")))' "$builder" ||
  fail "release ISO does not select a Linux Node.js LTS release"
grep -Fq 'node_filename="node-$node_version-linux-x64.tar.gz"' "$builder" ||
  fail "release ISO does not derive the exact official Node.js archive name"
grep -Fq 'qvOS ISO progress: selected Node.js LTS %s (%s)' "$builder" ||
  fail "release ISO does not record the selected Node.js LTS digest"
if rg -n 'nodejs\.org/dist/latest([/"[:space:]]|$)' "$builder"; then
  fail "release ISO caches the moving Node.js Current release"
fi
if rg -n 'SigLevel[[:space:]]*=[[:space:]]*Never|TrustAll|arch-mact2|linux-(ptl|t2)' \
  "$builder" "$profile"; then
  fail "release ISO activates weak package trust or an unsupported kernel stack"
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
grep -Fq "env -i \\" "$installer" ||
  fail "release ISO does not sanitize the target installer environment"
for target_environment in \
  'HOME="/home/$QVOS_USER"' \
  'XDG_CONFIG_HOME="/home/$QVOS_USER/.config"' \
  'XDG_DATA_HOME="/home/$QVOS_USER/.local/share"' \
  'XDG_CACHE_HOME="/home/$QVOS_USER/.cache"' \
  'XDG_STATE_HOME="/home/$QVOS_USER/.local/state"'; do
  grep -Fq "$target_environment" "$installer" ||
    fail "release ISO target environment: $target_environment"
done
target_environment_log="$cache_test_root/target-environment.log"
target_installer="$cache_test_root/target-installer"
install -m 0755 /dev/stdin "$test_bin/arch-chroot" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

[[ $1 == "-u" && $3 == "/mnt/" ]] || exit 64
shift 3
exec "$@"
SCRIPT
install -m 0644 /dev/stdin "$target_installer" <<'SCRIPT'
[[ $HOME == "/home/tester" && $USER == "tester" && $LOGNAME == "tester" ]]
[[ $XDG_CONFIG_HOME == "/home/tester/.config" ]]
[[ $XDG_DATA_HOME == "/home/tester/.local/share" ]]
[[ $XDG_CACHE_HOME == "/home/tester/.cache" ]]
[[ $XDG_STATE_HOME == "/home/tester/.local/state" ]]
[[ $QVOS_PROVIDER_CHANNEL == "stable" ]]
[[ $QVOS_USER_NAME == "Test User" && $QVOS_USER_EMAIL == "test@example.invalid" ]]
for absent in LIVE_MEDIA_ONLY MISE_DATA_DIR XDG_RUNTIME_DIR; do
  [[ ! -v $absent ]]
done
printf 'isolated\n' >"$1"
SCRIPT
printf '%s\n' 'Test User' >"$cache_test_root/user_full_name.txt"
printf '%s\n' 'test@example.invalid' >"$cache_test_root/user_email_address.txt"
(
  cd "$cache_test_root"
  export LIVE_MEDIA_ONLY=leak
  export MISE_DATA_DIR=/live-media/mise
  export QVOS_PROVIDER_CHANNEL=stable
  export QVOS_USER=tester
  export XDG_RUNTIME_DIR=/run/live-media
  PATH="$test_bin:/usr/bin"
  # shellcheck disable=SC1090
  source "$installer"
  chroot_bash "$target_installer" "$target_environment_log"
)
grep -Fqx 'isolated' "$target_environment_log" ||
  fail "release ISO target environment runtime isolation"

database_test_root="$cache_test_root/database-seed"
database_source="$database_test_root/source"
database_target="$database_test_root/target"
mkdir -p "$database_source" "$database_target"
for repository in core extra multilib omarchy; do
  printf '%s database\n' "$repository" >"$database_source/$repository.db"
done
printf 'stale offline database\n' >"$database_target/offline.db"
(
  # shellcheck disable=SC1090
  source "$installer"
  seed_qvos_target_databases "$database_source" "$database_target"
)
for repository in core extra multilib omarchy; do
  cmp -s \
    "$database_source/$repository.db" \
    "$database_target/$repository.db" ||
    fail "release ISO target database seed: $repository"
  [[ $(stat -c '%a' "$database_target/$repository.db") == "644" ]] ||
    fail "release ISO target database permissions: $repository"
done
[[ -f $database_target/offline.db && ! -L $database_target/offline.db ]] ||
  fail "release ISO removes the offline database before native packaging"
(
  # shellcheck disable=SC1090
  source "$installer"
  retire_qvos_target_offline_database "$database_target"
)
for stale_database in offline.db offline.db.sig; do
  [[ ! -e $database_target/$stale_database &&
    ! -L $database_target/$stale_database ]] ||
    fail "release ISO retains temporary offline target metadata after handoff"
done
set +e
(
  # shellcheck disable=SC1090
  source "$installer"
  seed_qvos_target_databases "$database_source" "$database_target"
) >/dev/null 2>&1
missing_offline_status=$?
set -e
((missing_offline_status != 0)) ||
  fail "release ISO accepts a target without its native offline database"

outside_offline="$database_test_root/outside-offline.db"
printf 'outside offline\n' >"$outside_offline"
ln -s "$outside_offline" "$database_target/offline.db"
set +e
(
  # shellcheck disable=SC1090
  source "$installer"
  retire_qvos_target_offline_database "$database_target"
) >/dev/null 2>&1
unsafe_offline_status=$?
set -e
((unsafe_offline_status != 0)) ||
  fail "release ISO retires symbolic-link offline metadata"
[[ -L $database_target/offline.db &&
  $(<"$outside_offline") == "outside offline" ]] ||
  fail "release ISO modified unsafe offline metadata"
unlink "$database_target/offline.db"

outside_database="$database_test_root/outside.db"
printf 'outside\n' >"$outside_database"
rm -f -- "$database_target/core.db"
ln -s "$outside_database" "$database_target/core.db"
set +e
(
  # shellcheck disable=SC1090
  source "$installer"
  seed_qvos_target_databases "$database_source" "$database_target"
) >/dev/null 2>&1
unsafe_database_status=$?
set -e
((unsafe_database_status != 0)) ||
  fail "release ISO accepts a symbolic-link target database"
[[ $(<"$outside_database") == "outside" ]] ||
  fail "release ISO wrote through a target database link"

handoff_root="$cache_test_root/handoff-target"
handoff_source="$handoff_root/home/tester/.local/share/qvos/qvcore/install/post-install/completion-marker"
handoff_marker="$handoff_root/var/tmp/qvos-install-completed"
handoff_log="$handoff_root/var/log/qvos-install.log"
mkdir -p \
  "${handoff_source%/*}" \
  "${handoff_marker%/*}" \
  "${handoff_log%/*}" \
  "$handoff_root/etc/sudoers.d" \
  "$handoff_root/var/lib/pacman"
install -m 0644 \
  "$root/qvcore/install/post-install/completion-marker" \
  "$handoff_source"
install -m 0600 "$handoff_source" "$handoff_marker"
printf 'complete qvOS install log\n' >"$handoff_log"
chmod 0640 "$handoff_log"
validate_handoff_fixture() {
  QVOS_USER=tester bash -Eeuo pipefail -c '
    source "$1"
    validate_qvos_target_handoff_files "$2" "$3" "$4"
  ' _ "$installer" "$handoff_root" "$(id -u)" "$(id -g)"
}

validate_handoff_fixture ||
  fail "release ISO rejects a complete target handoff"

: >"$handoff_log"
if validate_handoff_fixture >/dev/null 2>&1; then
  fail "release ISO accepts an empty persisted install log"
fi
printf 'complete qvOS install log\n' >"$handoff_log"
chmod 0640 "$handoff_log"

printf 'temporary authorization\n' \
  >"$handoff_root/etc/sudoers.d/99-qvos-installer"
if validate_handoff_fixture >/dev/null 2>&1; then
  fail "release ISO accepts retained installer authorization"
fi
rm -- "$handoff_root/etc/sudoers.d/99-qvos-installer"

: >"$handoff_marker"
if validate_handoff_fixture >/dev/null 2>&1; then
  fail "release ISO accepts a truncated completion marker"
fi
install -m 0600 "$handoff_source" "$handoff_marker"

grep -Fq 'qvos_target_mounts+=("$target")' "$installer" ||
  fail "release ISO does not record target bind mounts immediately"
grep -Fq 'cleanup_qvos_target_mounts' "$installer" ||
  fail "release ISO does not unwind target bind mounts"
grep -Fq 'qvOS installation returned without a completion marker.' "$installer" ||
  fail "release ISO accepts a partial qvOS finalizer"
grep -Fq 'chroot_bash "$target_installer"' "$installer" ||
  fail "release ISO does not execute the native installer directly"
grep -Fq 'CURRENT_SCRIPT=$target_installer' "$installer" ||
  fail "release ISO does not identify native handoff failures"
if rg -n 'chroot_bash -lc|pacman .*gum' "$installer"; then
  fail "release ISO retains a hidden package or login-shell handoff"
fi
grep -Fq 'arch-chroot /mnt mount /boot' "$installer" ||
  fail "release ISO does not remount the target ESP for native finalization"
grep -Fq 'seed_qvos_target_databases' "$installer" ||
  fail "release ISO leaves a fresh target without repository databases"
grep -Fq 'validate_qvos_target_databases' "$installer" ||
  fail "release ISO accepts unreadable target repository databases"
grep -Fq 'finalize_qvos_target' "$installer" ||
  fail "release ISO bypasses its durable target handoff"
grep -Fq '/usr/bin/sync -f /mnt' "$installer" ||
  fail "release ISO reboots without synchronizing the installed root"
grep -Fq 'qvcore/install/post-install/verify' "$installer" ||
  fail "release ISO bypasses the native installed-state verifier"
grep -Fq 'QVOS_INSTALL_VERIFY_TARGET=1' "$installer" ||
  fail "release ISO does not verify the synchronized target as root"
grep -Fq 'pacman_args+=(--sysroot "$system_root")' \
  "$post_install_verifier" ||
  fail "release ISO target verification still reads the live Pacman policy"
grep -Fq '[[ $path == $system_root/* ]]' "$post_install_verifier" ||
  fail "release ISO target verification accepts paths outside its mount"
grep -Fq 'path=${path#"$system_root"}' "$post_install_verifier" ||
  fail "release ISO target verification double-prefixes package paths"
grep -Fq 'mounted-target verifier without an isolated Pacman path boundary' \
  "$build" ||
  fail "release build does not reject a host-configured target verifier"
finalizer=$(sed -n '/^finalize_qvos_target() {$/,/^}$/p' "$installer")
grep -Fq 'QVOS_CHROOT_INSTALL=1' <<<"$finalizer" ||
  fail "release ISO final verifier cannot resolve its reviewed provider channel"
if grep -Fq 'chroot_bash "$target_verifier"' "$installer"; then
  fail "release ISO executes a user-owned target verifier as root"
fi
grep -Fqx '  retire_qvos_target_offline_database' "$installer" ||
  fail "release ISO retains its temporary database after provider handoff"
if grep -Fq 'arch-chroot /mnt pacman -Sy --noconfirm' "$installer"; then
  fail "release ISO retains a partial target repository synchronization"
fi
grep -Fq 'boot_fstype == "vfat"' "$installer" ||
  fail "release ISO does not validate the remounted target ESP"
if rg -n 'fmask=0022|dmask=0022|chmod .*[/]boot' "$installer"; then
  fail "release ISO weakens the target ESP for unprivileged finalization"
fi
cleanup_line=$(grep -Fn '  cleanup_qvos_target_mounts' "$installer" | tail -n 1 | cut -d: -f1)
finalize_line=$(grep -Fn '  finalize_qvos_target' "$installer" | tail -n 1 | cut -d: -f1)
reboot_line=$(grep -Fn '  reboot' "$installer" | tail -n 1 | cut -d: -f1)
if [[ -z $cleanup_line || -z $finalize_line || -z $reboot_line ]] ||
  (( cleanup_line >= finalize_line || finalize_line >= reboot_line )); then
  fail "release ISO target finalization order"
fi
[[ ! -e $profile/airootfs/root/configurator ]] ||
  fail "release ISO ships a duplicate installer"
grep -Fq 'unexpected source digest' "$builder" ||
  fail "release ISO does not verify the built TUI"
grep -Fq '"$qvos_tui_source/build"' "$builder" ||
  fail "release ISO bypasses the shared TUI build owner"
grep -Fq -- '-buildvcs=false' "$root/qvcore/tui/build" ||
  fail "release ISO TUI build includes ambient VCS state"
grep -Fq 'release/iso/source-permissions' "$builder" ||
  fail "release ISO bypasses tracked executable modes"
grep -Fq 'will not overwrite an existing release artifact' "$build" ||
  fail "release ISO can overwrite an existing artifact"
grep -Fq 'if ! ln -- "$partial_iso" "$target_iso"; then' "$build" ||
  fail "release ISO publication is not atomic and no-clobbering"
if rg -n 'source .*\|\| bash|python3\.[0-9]+/site-packages|OMARCHY_[A-Z_]+=' \
  "$installer" "$builder"; then
  fail "release ISO retains a fragile installer fallback or inherited identity"
fi
[[ $(
  rg -o 'QVOS_CHROOT_INSTALL' "$installer" "$builder" | sed 's/.*://' | sort -u
) == "QVOS_CHROOT_INSTALL" ]] ||
  fail "release ISO lacks its native target-chroot signal"

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

expected=$'AGENTS.md\nLICENSE.omarchy-iso\nREADME.md\nUPSTREAM.md\nbuild\nsource-permissions\nspace-check\nsyslinux-splash.png'
actual=$(find "$release_root" -maxdepth 1 -type f -printf '%f\n' | sort)
[[ $actual == "$expected" ]] || fail "release/iso source inventory"

printf 'ok - qvOS owns one native Archiso builder and one thin TUI adapter\n'
