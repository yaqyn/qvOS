#!/bin/bash
set -euo pipefail

provider_channel=${QVOS_PROVIDER_CHANNEL:-stable}
case $provider_channel in
stable | edge | rc) ;;
*)
  echo "QVOS_PROVIDER_CHANNEL must be stable, edge, or rc." >&2
  exit 2
  ;;
esac
qvos_source=/qvos

configure_pacman_transport() {
  local config="$1"
  local xfer_command='XferCommand = /usr/bin/curl --http1.1 --fail --location --connect-timeout 20 --speed-limit 1 --speed-time 30 --retry 5 --retry-connrefused --retry-delay 2 --output %o --url %u'

  sed -i '/^XferCommand[[:space:]]*=/d' "$config"
  sed -i "/^\[options\]/a $xfer_command" "$config"
}

# Note that these are packages installed to the Arch container used to build the ISO.
pacman-key --init
if [[ -n ${QVOS_ARCH_MIRROR:-} ]]; then
  if [[ $QVOS_ARCH_MIRROR != https://* ]]; then
    echo "QVOS_ARCH_MIRROR must use HTTPS" >&2
    exit 2
  fi
  # shellcheck disable=SC2016
  printf 'Server = %s/$repo/os/$arch\n' "${QVOS_ARCH_MIRROR%/}" >/etc/pacman.d/mirrorlist
  grep -qxF "DisableDownloadTimeout" /etc/pacman.conf ||
    sed -i '/^\[options\]/a DisableDownloadTimeout' /etc/pacman.conf
fi
configure_pacman_transport /etc/pacman.conf
pacman --noconfirm -Sy archlinux-keyring
# A cached container can predate the repositories it is about to use. Upgrade
# the complete ephemeral build root before installing tools; a partial upgrade
# is unsupported on Arch Linux.
pacman --noconfirm -Syu --needed archiso git sudo base-devel jq grub go

# Pre-import the credited provider key from qvOS's reviewed package boundary so
# Pacman can verify the keyring package without a keyserver lookup.
provider_fingerprint=40DFB630FF42BCFFB047046CF0134EE680CAC571
provider_key_sha256=15d6aac44df688165b2ea35fe0b23af239bbc66a6909c10a5c219e8d94b707de
provider_key="$qvos_source/qvcore/packages/provider/omarchy/signing-key.gpg"
[[ -f $provider_key && ! -L $provider_key ]] || {
  echo "Missing the reviewed Omarchy provider signing key." >&2
  exit 1
}
[[ $(sha256sum "$provider_key" | cut -d ' ' -f 1) == \
  "$provider_key_sha256" ]] || {
  echo "The reviewed Omarchy provider signing key payload has drifted." >&2
  exit 1
}
key_fingerprint=$(gpg --show-keys --with-colons "$provider_key" |
  awk -F: '$1 == "fpr" { print $10; exit }')
[[ $key_fingerprint == "$provider_fingerprint" ]] || {
  echo "The Omarchy provider signing key has an unexpected fingerprint." >&2
  exit 1
}
pacman-key --add "$provider_key"
pacman-key --lsign-key "$provider_fingerprint"

# Resolve the exact signed qvOS provider inputs before the first provider package.
provider_output=$(OMARCHY_CHROOT_INSTALL=1 \
  "$qvos_source/qvcore/packages/provider-files" "$provider_channel")
mapfile -t provider_files <<<"$provider_output"
(( ${#provider_files[@]} == 2 )) || {
  echo "Could not resolve qvOS package-provider files." >&2
  exit 1
}
online_pacman_config=$(mktemp /tmp/pacman-online.XXXXXX)
online_mirrorlist=$(mktemp /tmp/mirrorlist.XXXXXX)
cp "${provider_files[0]}" "$online_pacman_config"
cp "${provider_files[1]}" "$online_mirrorlist"
if [[ -n ${QVOS_ARCH_MIRROR:-} ]]; then
  # shellcheck disable=SC2016
  printf 'Server = %s/$repo/os/$arch\n' "${QVOS_ARCH_MIRROR%/}" >"$online_mirrorlist"
fi
sed -i \
  "s|^Include = /etc/pacman.d/mirrorlist$|Include = $online_mirrorlist|" \
  "$online_pacman_config"
configure_pacman_transport "$online_pacman_config"

# Install omarchy-keyring under the same signed provider policy used below.
pacman --config "$online_pacman_config" --noconfirm -Sy omarchy-keyring
pacman-key --populate omarchy

# Setup build locations
build_cache_dir="/var/cache"
offline_mirror_dir="$build_cache_dir/airootfs/var/cache/qvos/mirror/offline"
mkdir -p "$build_cache_dir" "$offline_mirror_dir"

# Base qvOS directly on the releng profile shipped by the signed Archiso
# package installed above. No second distribution's image builder is involved.
cp -r /usr/share/archiso/configs/releng/* "$build_cache_dir/"
rm "$build_cache_dir/airootfs/etc/motd"

# Remove releng packages whose capability qvOS deliberately does not expose.
# The live image uses the global CDN and systemd-networkd, and it has no cloud
# bootstrap contract. SSH remains installed separately for explicit recovery.
unused_live_packages=(cloud-init dhcpcd reflector)
for package in "${unused_live_packages[@]}"; do
  sed -i "/^${package}$/d" "$build_cache_dir/packages.x86_64"
  if grep -Fqx "$package" "$build_cache_dir/packages.x86_64"; then
    echo "Unsupported live-image package remains: $package" >&2
    exit 1
  fi
done

# Remove the corresponding releng activation and configuration overlays.
rm -rf "$build_cache_dir/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service"
rm -rf "$build_cache_dir/airootfs/etc/systemd/system/reflector.service.d"
rm -rf "$build_cache_dir/airootfs/etc/xdg/reflector"

# Bring in the native qvOS profile.
cp -r /profile/* "$build_cache_dir/"

# The interactive qvOS image has no remote-administration or cloud-bootstrap
# contract. Keep SSH available for explicit recovery, but do not expose it or
# run Archiso mirror/cloud discovery automatically on an untrusted network.
rm -f \
  "$build_cache_dir/airootfs/etc/systemd/system/multi-user.target.wants/choose-mirror.service" \
  "$build_cache_dir/airootfs/etc/systemd/system/multi-user.target.wants/sshd.service"
rm -rf "$build_cache_dir/airootfs/etc/systemd/system/cloud-init.target.wants"

# Persist the validated provider channel for the target installer.
printf '%s\n' "$provider_channel" \
  >"$build_cache_dir/airootfs/root/qvos_provider_channel"

# Stage only the source pinned and mounted by the qvOS release owner.
[[ -d $qvos_source/.git ]] || {
  echo "Missing staged qvOS source." >&2
  exit 1
}
cp -rp "$qvos_source" "$build_cache_dir/airootfs/root/qvos"

# Do not ship transient builder identity in the embedded Git checkout. The
# release owner already sanitizes these files; repeat the cleanup after the
# profile copy so the final image fails toward the same invariant.
git -c safe.directory="$build_cache_dir/airootfs/root/qvos" \
  -C "$build_cache_dir/airootfs/root/qvos" \
  config --local core.logAllRefUpdates false
rm -f -- \
  "$build_cache_dir/airootfs/root/qvos/.git/COMMIT_EDITMSG" \
  "$build_cache_dir/airootfs/root/qvos/.git/FETCH_HEAD" \
  "$build_cache_dir/airootfs/root/qvos/.git/ORIG_HEAD"
rm -rf -- "$build_cache_dir/airootfs/root/qvos/.git/logs"

# Build the singular qvOS boot/install interface. A missing or unbuildable TUI
# invalidates the image; never fall back to a second installer implementation.
echo "qvOS ISO progress: staging qvOS TUI installer"
qvos_tui_source="$build_cache_dir/airootfs/root/qvos/qvcore/tui"
[[ -x $qvos_tui_source/source-hash ]] || {
  echo "Missing the qvOS TUI source-hash owner." >&2
  exit 1
}
qvos_tui_source_hash=$("$qvos_tui_source/source-hash" "$qvos_tui_source")
export GOMODCACHE="${GOMODCACHE:-/var/cache/qvos/go/pkg/mod}"
export GOCACHE="${GOCACHE:-/var/cache/qvos/go/build}"
mkdir -p \
  "$GOMODCACHE" \
  "$GOCACHE" \
  "$build_cache_dir/airootfs/usr/local/bin"
(
  cd "$qvos_tui_source"
  go build \
    -buildvcs=false \
    -trimpath \
    -ldflags="-s -w -X main.buildSourceHash=$qvos_tui_source_hash" \
    -o "$build_cache_dir/airootfs/usr/local/bin/qvos-tui" \
    .
)
[[ $("$build_cache_dir/airootfs/usr/local/bin/qvos-tui" --source-hash) == \
  "$qvos_tui_source_hash" ]] || {
  echo "The staged qvOS TUI has an unexpected source digest." >&2
  exit 1
}

# Copy the native qvOS Plymouth theme to the ISO.
mkdir -p "$build_cache_dir/airootfs/usr/share/plymouth/themes/qvos"
cp -r "$build_cache_dir/airootfs/root/qvos/qvcore/boot/plymouth/"* "$build_cache_dir/airootfs/usr/share/plymouth/themes/qvos/"

# Replace inherited Arch artwork with the qvOS grayscale BIOS boot splash.
cp "$build_cache_dir/airootfs/root/qvos/release/iso/syslinux-splash.png" \
  "$build_cache_dir/syslinux/splash.png"

# Download and verify Node.js binary for offline installation
node_dist_url="https://nodejs.org/dist/latest"
node_cache_dir="/var/cache/qvos/node"
mkdir -p "$node_cache_dir"

# Get checksums and accept exactly one bounded Linux x86_64 archive name.
node_shasums=$(curl --http1.1 --fail --location --retry 5 \
  --retry-all-errors --retry-delay 2 "$node_dist_url/SHASUMS256.txt")
mapfile -t node_checksum_rows < <(
  awk '$2 ~ /^node-v[0-9]+\.[0-9]+\.[0-9]+-linux-x64\.tar\.gz$/ {
    print $1 " " $2
  }' <<<"$node_shasums"
)
(( ${#node_checksum_rows[@]} == 1 )) || {
  echo "ERROR: Node.js checksum inventory is unexpected." >&2
  exit 1
}
read -r node_sha node_filename <<<"${node_checksum_rows[0]}"
[[ $node_sha =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: Node.js checksum is malformed." >&2
  exit 1
}
node_tarball="$node_cache_dir/$node_filename"

if [[ ! -f $node_tarball ]] ||
  ! printf '%s  %s\n' "$node_sha" "$node_tarball" | sha256sum -c -; then
  echo "qvOS ISO progress: caching node runtime"
  curl --http1.1 --fail --location --retry 5 --retry-all-errors \
    --retry-delay 2 "$node_dist_url/$node_filename" -o "$node_tarball.tmp"
  printf '%s  %s\n' "$node_sha" "$node_tarball.tmp" | sha256sum -c - || {
    echo "ERROR: Node.js checksum verification failed!"
    rm -f "$node_tarball.tmp"
    exit 1
  }
  mv -f "$node_tarball.tmp" "$node_tarball"
fi

# Copy to ISO
mkdir -p "$build_cache_dir/airootfs/opt/packages/"
cp "$node_tarball" "$build_cache_dir/airootfs/opt/packages/"

# Add our additional packages to packages.x86_64
arch_packages=(linux git gum jq openssl plymouth tzupdate omarchy-keyring lvm2 cryptsetup parted)
printf '%s\n' "${arch_packages[@]}" >>"$build_cache_dir/packages.x86_64"

# Resolve the native qvOS package manifests.
qvos_package_resolver="$build_cache_dir/airootfs/root/qvos/qvcore/install/packaging/resolve"
[[ -x $qvos_package_resolver ]] || {
  echo "Missing qvOS package resolver: $qvos_package_resolver" >&2
  exit 1
}
qvos_package_list=$("$qvos_package_resolver" all)
mapfile -t qvos_packages <<<"$qvos_package_list"

# Build one deterministic list of all packages needed for the offline mirror.
mapfile -t archinstall_packages < <(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' /builder/archinstall.packages)
mapfile -t all_packages < <(
  {
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$build_cache_dir/packages.x86_64"
    printf '%s\n' "${qvos_packages[@]}" "${archinstall_packages[@]}"
  } | sort -u
)
(( ${#all_packages[@]} > 0 )) || {
  echo "ERROR: resolved qvOS package inventory is empty." >&2
  exit 1
}

# Download packages into the reusable host cache, then copy only this build's
# resolved package files into the offline mirror inside the ISO filesystem.
package_cache_dir="/var/cache/pacman/pkg"
offline_db_dir=$(mktemp -d /tmp/offlinedb.XXXXXX)
rm -rf "$offline_mirror_dir"
mkdir -p "$package_cache_dir" "$offline_mirror_dir" "$offline_db_dir"
# Pacman downloads as its unprivileged DownloadUser. The randomized root holds
# public repository metadata only, so allow traversal while retaining root
# ownership and write control.
chmod 0755 "$offline_db_dir"

echo "qvOS ISO progress: resolving package set"
download_offline_packages() {
  pacman --config "$online_pacman_config" --noconfirm -Syw \
    "${all_packages[@]}" --cachedir "$package_cache_dir/" --dbpath "$offline_db_dir" --needed
}

download_complete=false
for attempt in 1 2 3; do
  if download_offline_packages; then
    download_complete=true
    break
  fi
  if (( attempt < 3 )); then
    echo "Offline package download failed; retrying cached transfer ($attempt/3)..." >&2
  fi
done
if [[ $download_complete != "true" ]]; then
  echo "Offline package download failed after 3 attempts" >&2
  exit 1
fi

mapfile -t offline_package_urls < <(
  pacman --config "$online_pacman_config" --noconfirm -Sp \
    "${all_packages[@]}" --cachedir "$package_cache_dir/" --dbpath "$offline_db_dir"
)
for package_url in "${offline_package_urls[@]}"; do
  package_file="${package_url##*/}"
  [[ $package_file == *.pkg.tar.* ]] || continue
  if [[ ! -f $package_cache_dir/$package_file ]]; then
    echo "ERROR: package $package_file was not downloaded to $package_cache_dir"
    exit 1
  fi
  signature_file="$package_cache_dir/$package_file.sig"
  if [[ ! -f $signature_file ]]; then
    echo "ERROR: package $package_file has no detached signature in $package_cache_dir"
    exit 1
  fi
  install -m 0644 \
    "$package_cache_dir/$package_file" \
    "$signature_file" \
    "$offline_mirror_dir/"
done

mapfile -t offline_packages < <(
  find "$offline_mirror_dir" -maxdepth 1 -type f -name "*.pkg.tar.*" ! -name "*.sig" | sort
)
if (( ${#offline_packages[@]} == 0 )); then
  echo "ERROR: offline package mirror is empty"
  exit 1
fi

echo "qvOS ISO progress: indexing package mirror"
repo-add --new "$offline_mirror_dir/offline.db.tar.gz" "${offline_packages[@]}"
find "$offline_mirror_dir" -maxdepth 1 -type f -exec chmod 0644 {} +

# Create a symlink to the offline mirror instead of duplicating it.
# mkarchiso needs packages at the same path exposed inside the live image.
mkdir -p /var/cache/qvos/mirror
ln -s "$offline_mirror_dir" "/var/cache/qvos/mirror/offline"

# Copy the offline pacman.conf to the ISO's /etc directory so the live environment uses our
# same config when booted.
cp "$build_cache_dir/pacman-offline.conf" \
  "$build_cache_dir/airootfs/etc/pacman.conf"

# Finally, we assemble the entire ISO
echo "qvOS ISO progress: creating ISO image"
"$build_cache_dir/airootfs/root/qvos/release/iso/source-permissions" \
  "$build_cache_dir/airootfs/root/qvos" \
  "/root/qvos" \
  >>"$build_cache_dir/profiledef.sh"
mkarchiso -v -w "$build_cache_dir/work/" -o "/out/" "$build_cache_dir/"

# Fix ownership of output files to match host user
if [[ -n ${HOST_UID:-} && -n ${HOST_GID:-} ]]; then
  chown -R "$HOST_UID:$HOST_GID" /out/
fi
