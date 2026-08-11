#!/bin/bash
set -euo pipefail

qvos_target_mounts=()
qvos_governor_paths=()
qvos_governor_values=()
qvos_prefetch_pid=""

use_qvos_helpers() {
  export QVOS_PATH="/root/qvos"
  export QVOS_INSTALL="$QVOS_PATH/qvcore/install"
  export QVOS_INSTALL_LOG_FILE="/var/log/qvos-install.log"
  QVOS_PROVIDER_CHANNEL=$(</root/qvos_provider_channel)
  case $QVOS_PROVIDER_CHANNEL in
  stable | edge | rc) ;;
  *)
    echo "The qvOS image contains an invalid package-provider channel." >&2
    return 1
    ;;
  esac
  export QVOS_PROVIDER_CHANNEL
  # shellcheck disable=SC1091
  source "$QVOS_INSTALL/helpers/run"
}

run_configurator() {
  set_qvos_console_colors
  command -v qvos-tui >/dev/null 2>&1 || {
    echo "The qvOS installer is unavailable. Use this live shell for recovery; do not continue with a partial installer." >&2
    return 1
  }

  start_qvos_package_prefetch
  set +e
  QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-installer
  local configurator_status=$?
  set -e
  stop_qvos_package_prefetch
  ((configurator_status == 0)) || return "$configurator_status"

  QVOS_USER=$(jq -er '.users[0].username' user_credentials.json)
  export QVOS_USER
}

start_qvos_package_prefetch() {
  local mirror=/var/cache/qvos/mirror/offline
  local budget_kb

  qvos_prefetch_pid=""
  [[ -d $mirror ]] || return 0
  budget_kb=$(awk '/^MemAvailable:/ { print int($2 / 2); exit }' /proc/meminfo)
  [[ $budget_kb =~ ^[0-9]+$ ]] || return 0
  ((budget_kb > 262144)) || return 0

  (
    local spent_kb=0
    local size_kb
    local path

    while read -r size_kb path; do
      [[ $size_kb =~ ^[0-9]+$ && -f $path ]] || continue
      ((spent_kb + size_kb <= budget_kb)) || continue
      cat -- "$path" >/dev/null 2>&1 || true
      ((spent_kb += size_kb))
    done < <(
      find "$mirror" -maxdepth 1 -type f -name '*.pkg.tar.*' \
        ! -name '*.sig' -printf '%k %p\n' | sort -nr
    )
  ) &
  qvos_prefetch_pid=$!
}

stop_qvos_package_prefetch() {
  [[ -n ${qvos_prefetch_pid:-} ]] || return 0
  kill "$qvos_prefetch_pid" 2>/dev/null || true
  wait "$qvos_prefetch_pid" 2>/dev/null || true
  qvos_prefetch_pid=""
}

bind_qvos_target() {
  local source=$1
  local target=$2

  [[ $source == /* && $target == /mnt/* ]] || {
    echo "Refusing an unsafe qvOS installer bind mount." >&2
    return 1
  }
  [[ ! -L $source && ! -L $target ]] || {
    echo "Refusing a symbolic-link qvOS installer bind mount." >&2
    return 1
  }
  if [[ -d $source ]]; then
    [[ -d $target ]] || {
      echo "Missing qvOS installer bind directory: $target" >&2
      return 1
    }
  elif [[ -f $source ]]; then
    [[ -f $target ]] || {
      echo "Missing qvOS installer bind file: $target" >&2
      return 1
    }
  else
    echo "Missing qvOS installer bind source: $source" >&2
    return 1
  fi
  if mountpoint -q -- "$target"; then
    echo "Refusing to replace an existing target mount: $target" >&2
    return 1
  fi

  mount --bind -- "$source" "$target"
  qvos_target_mounts+=("$target")
}

cleanup_qvos_target_mounts() {
  local index
  local status=0
  local target

  for ((index = ${#qvos_target_mounts[@]} - 1; index >= 0; index--)); do
    target=${qvos_target_mounts[index]}
    if mountpoint -q -- "$target" && ! umount -- "$target"; then
      printf 'Could not unmount qvOS installer target: %s\n' "$target" >&2
      status=1
    fi
  done
  (( status == 0 )) && qvos_target_mounts=()

  target=/mnt/var/log/qvos-install.log
  if (( status == 0 )) &&
    [[ -f /var/log/qvos-install.log && ! -L /var/log/qvos-install.log &&
      -d /mnt/var/log && ! -L /mnt/var/log && ! -L $target ]]; then
    install -m0640 /var/log/qvos-install.log "$target" || status=1
  fi

  return "$status"
}

# qvcore/install/helpers/errors invokes this optional lifecycle hook exactly
# once before it presents the final status. It must preserve the original
# failure status while leaving no ISO-only process, governor, or bind mount.
qvos_install_exit_cleanup() {
  stop_qvos_package_prefetch
  restore_qvos_cpu_governors
  cleanup_qvos_target_mounts
}

boost_qvos_cpu_governors() {
  local governor_path
  local governor

  qvos_governor_paths=()
  qvos_governor_values=()
  for governor_path in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -f $governor_path ]] || continue
    governor=$(<"$governor_path") || continue
    if printf 'performance\n' >"$governor_path" 2>/dev/null; then
      qvos_governor_paths+=("$governor_path")
      qvos_governor_values+=("$governor")
    fi
  done
}

restore_qvos_cpu_governors() {
  local index

  for index in "${!qvos_governor_paths[@]}"; do
    printf '%s\n' "${qvos_governor_values[$index]}" \
      >"${qvos_governor_paths[$index]}" 2>/dev/null || true
  done
  qvos_governor_paths=()
  qvos_governor_values=()
}

start_qvos_iso_progress() {
  if command -v qvos-tui >/dev/null 2>&1; then
    QVOS_TUI_FULLSCREEN=1 qvos-tui --iso-progress --log /var/log/qvos-install.log --no-input &
    # Used by the sourced native logging owner.
    # shellcheck disable=SC2034
    QVOS_ISO_PROGRESS_PID=$!
  else
    start_log_output
  fi
}

stop_qvos_iso_progress() {
  stop_log_output
  clear
}

install_arch() {
  if ! command -v qvos-tui >/dev/null 2>&1; then
    clear_logo
    gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Installing..."
    echo
  fi

  touch /var/log/qvos-install.log

  start_qvos_iso_progress
  boost_qvos_cpu_governors

  # Set CURRENT_SCRIPT for the trap to display better when nothing is returned for some reason
  local install_status
  # Used by the sourced native error owner.
  # shellcheck disable=SC2034
  CURRENT_SCRIPT="install_base_system"
  set +e
  install_base_system > >(sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g' >>/var/log/qvos-install.log) 2>&1
  install_status=$?
  restore_qvos_cpu_governors
  unset CURRENT_SCRIPT
  set -e

  if (( install_status != 0 )); then
    stop_qvos_iso_progress
    return "$install_status"
  fi

  if [[ -x /usr/local/bin/qvos-tui ]]; then
    install -Dm755 /usr/local/bin/qvos-tui /mnt/usr/local/bin/qvos-tui
  fi
  install -Dm0640 /dev/null /mnt/var/log/qvos-install.log
  bind_qvos_target /var/log/qvos-install.log /mnt/var/log/qvos-install.log
  stop_qvos_iso_progress
  return 0
}

install_qvos() {
  local target_installer="/home/$QVOS_USER/.local/share/qvos/install.sh"

  [[ -f /mnt$target_installer && ! -L /mnt$target_installer ]] || {
    echo "The installed qvOS source is missing its native installer." >&2
    return 1
  }

  # Archinstall owns every package needed to enter the native installer,
  # including Gum. Execute the tracked entry point directly so login-profile
  # state cannot alter the handoff and no hidden Pacman transaction sits
  # outside the native install log.
  # Used by the sourced native error owner.
  # shellcheck disable=SC2034
  CURRENT_SCRIPT=$target_installer
  chroot_bash "$target_installer"
  unset CURRENT_SCRIPT

  [[ -f /mnt/var/tmp/qvos-install-completed ]] || {
    echo "qvOS installation returned without a completion marker." >&2
    return 1
  }
}

# Set the qvOS black, grayscale, and red color scheme for the terminal
set_qvos_console_colors() {
  if [[ $(tty) == "/dev/tty"* ]]; then
    # Keep every non-red ANSI slot neutral on the reduced-color Linux VT.
    echo -en "\e]P0000000" # black (background)
    echo -en "\e]P1b00000" # red
    echo -en "\e]P2707070" # grayscale
    echo -en "\e]P38a8a8a" # grayscale
    echo -en "\e]P4a0a0a0" # grayscale
    echo -en "\e]P5b8b8b8" # grayscale
    echo -en "\e]P6909090" # grayscale
    echo -en "\e]P7c8c8c8" # foreground
    echo -en "\e]P8404040" # bright black
    echo -en "\e]P9d00000" # bright red
    echo -en "\e]PA9a9a9a" # grayscale
    echo -en "\e]PBb0b0b0" # grayscale
    echo -en "\e]PCc6c6c6" # grayscale
    echo -en "\e]PDdddddd" # grayscale
    echo -en "\e]PEa8a8a8" # grayscale
    echo -en "\e]PFffffff" # bright foreground

    # Set default foreground and background
    echo -en "\033[0m"
    clear
  fi
}

install_disk() {
  jq -er 'first(.disk_config.device_modifications[]? | select(.wipe == true) | .device)' user_configuration.json
}

cleanup_install_disk() {
  local disk="$1"

  if [[ -z "$disk" || ! -b "$disk" ]]; then
    echo "Could not determine install disk for cleanup" >&2
    return 1
  fi

  echo "Cleaning up existing holders on install disk: $disk"

  # Ensure that no mounts exist from past install attempts.
  findmnt -R /mnt >/dev/null && umount -R /mnt || true

  # Turn off swap and unmount anything backed by the selected disk, including
  # device-mapper children from a previous install. Active LVM/swap holders can
  # prevent the kernel from re-reading the partition table after archinstall
  # wipes and recreates it.
  while read -r dev; do
    [[ -b "$dev" ]] || continue

    swapoff "$dev" 2>/dev/null || true

    while read -r target; do
      [[ -n "$target" ]] || continue
      umount "$target" 2>/dev/null || true
    done < <(findmnt -rn -S "$dev" -o TARGET 2>/dev/null || true)
  done < <(lsblk -rnpo PATH "$disk")

  # Deactivate any LVM volume groups whose physical volumes live on the selected
  # disk. This is the common case when replacing Fedora/Alma/RHEL installs.
  while read -r dev type; do
    [[ "$type" == "disk" || "$type" == "part" || "$type" == "crypt" ]] || continue

    while read -r vg; do
      [[ -n "$vg" ]] || continue
      vgchange -an "$vg" 2>/dev/null || true
    done < <(pvs --noheadings -o vg_name "$dev" 2>/dev/null | awk '{$1=$1; print}' | sort -u)
  done < <(lsblk -rnpo PATH,TYPE "$disk")

  # Close any LUKS mappings stacked on the selected disk after filesystems and
  # swap have been released.
  while read -r dev type; do
    [[ "$type" == "crypt" ]] || continue
    cryptsetup close "$dev" 2>/dev/null || true
  done < <(lsblk -rnpo PATH,TYPE "$disk")

  blockdev --flushbufs "$disk" 2>/dev/null || true
  partprobe "$disk" 2>/dev/null || true
  udevadm settle || true
}

mount_qvos_target_boot() {
  local boot_fstype
  local boot_source

  [[ -d /mnt/boot && ! -L /mnt/boot ]] || {
    echo "The installed qvOS boot path is missing or unsafe." >&2
    return 1
  }
  if ! mountpoint -q -- /mnt/boot; then
    arch-chroot /mnt mount /boot
  fi
  read -r boot_source boot_fstype < <(
    findmnt -rn -M /mnt/boot -o SOURCE,FSTYPE
  )
  [[ -n $boot_source && $boot_fstype == "vfat" ]] || {
    echo "The installed qvOS EFI system partition is not mounted at /boot." >&2
    return 1
  }
}

install_base_system() {
  # Wait for Archiso's singular keyring owner. It initializes the runtime
  # keyring and populates every installed keyring package, including the
  # reviewed provider keyring bundled in this image.
  systemctl start pacman-init.service

  # Sync the offline database so pacman can find packages
  pacman -Sy --noconfirm

  cleanup_install_disk "$(install_disk)"

  # Install using files generated by the singular qvOS installer TUI.
  # Skip NTP and WKD sync since we're offline (keyring is pre-populated in ISO)
  archinstall \
    --config user_configuration.json \
    --creds user_credentials.json \
    --offline \
    --silent \
    --skip-ntp \
    --skip-wkd \
    --skip-wifi-check

  # Archinstall unmounts the ESP before returning. The native qvOS boot owner
  # reads and replaces its generated Limine input through sudo, so restore the
  # target mount without weakening its root-only permissions.
  mount_qvos_target_boot

  # After archinstall sets up the base system but before our installer runs,
  # we need to ensure the offline pacman.conf is in place
  cp /etc/pacman.conf /mnt/etc/pacman.conf

  # Mount the offline mirror so it's accessible in the chroot
  mkdir -p /mnt/var/cache/qvos/mirror/offline
  bind_qvos_target \
    /var/cache/qvos/mirror/offline \
    /mnt/var/cache/qvos/mirror/offline

  # Mount the packages dir so it's accessible in the chroot
  mkdir -p /mnt/opt/packages
  bind_qvos_target /opt/packages /mnt/opt/packages

  # Preserve the signed offline repository databases in the target before the
  # native installer switches Pacman to Stable. A fresh installation can then
  # resolve its first package operation without an unsafe partial online sync.
  arch-chroot /mnt pacman -Sy --noconfirm

  # qvOS removes this temporary installer policy before allowing reboot.
  mkdir -p /mnt/etc/sudoers.d
  cat >/mnt/etc/sudoers.d/99-qvos-installer <<EOF
root ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
$QVOS_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF
  chmod 440 /mnt/etc/sudoers.d/99-qvos-installer

  # Copy qvOS to its canonical source root and retain one compatibility link.
  mkdir -p "/mnt/home/$QVOS_USER/.local/share"
  cp -a -- /root/qvos "/mnt/home/$QVOS_USER/.local/share/qvos"
  ln -s qvos "/mnt/home/$QVOS_USER/.local/share/omarchy"

  target_uid=$(arch-chroot /mnt id -u "$QVOS_USER")
  target_gid=$(arch-chroot /mnt id -g "$QVOS_USER")
  [[ $target_uid =~ ^[0-9]+$ && $target_gid =~ ^[0-9]+$ ]] || {
    echo "Could not resolve the installed qvOS account ownership." >&2
    return 1
  }
  chown -R "$target_uid:$target_gid" "/mnt/home/$QVOS_USER/.local"
}

chroot_bash() {
  arch-chroot -u "$QVOS_USER" /mnt/ \
    env -i \
    HOME="/home/$QVOS_USER" \
    LANG=C.UTF-8 \
    LOGNAME="$QVOS_USER" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin \
    SHELL=/bin/bash \
    TERM=linux \
    USER="$QVOS_USER" \
    XDG_CONFIG_HOME="/home/$QVOS_USER/.config" \
    XDG_DATA_HOME="/home/$QVOS_USER/.local/share" \
    XDG_CACHE_HOME="/home/$QVOS_USER/.cache" \
    XDG_STATE_HOME="/home/$QVOS_USER/.local/state" \
    OMARCHY_CHROOT_INSTALL=1 \
    QVOS_PROVIDER_CHANNEL="$QVOS_PROVIDER_CHANNEL" \
    QVOS_USER_NAME="$(<user_full_name.txt)" \
    QVOS_USER_EMAIL="$(<user_email_address.txt)" \
    /bin/bash "$@"
}

if [[ $(tty) == "/dev/tty1" ]]; then
  use_qvos_helpers
  run_configurator
  install_arch
  install_qvos
  cleanup_qvos_target_mounts
  reboot
fi
