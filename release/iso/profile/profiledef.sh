#!/bin/bash
# shellcheck disable=SC2034

iso_name="qvos"
iso_label="QVOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="qvOS <https://github.com/Yaqyn-qvOS/qvOS>"
iso_application="qvOS Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.grub')
arch="x86_64"
pacman_conf="pacman-offline.conf"
airootfs_image_type="squashfs"
# Package archives are already zstd-compressed. Keep the offline mirror outside
# the outer compression stream and use fast zstd decompression for the live
# root; this improves boot and install throughput with negligible image growth.
airootfs_image_tool_options=(
  '-comp' 'zstd'
  '-Xcompression-level' '19'
  '-b' '1M'
  '-action' 'uncompressed@subpathname(var/cache/qvos/mirror/offline)'
)
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/var/cache/qvos/mirror/offline"]="0:0:755"
  ["/usr/local/bin/qvos-tui"]="0:0:755"
)
