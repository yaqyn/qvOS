#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
state="$test_root/state"
installed="$state/installed"
action_log="$state/actions.log"
integrity_log="$state/integrity.log"
pacman_db="$state/pacman"
pacman_log="$state/pacman.log"
proc_root="$state/proc"
sys_root="$state/sys"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/bin" \
  "$source_root/qv/config/files/hypr/qv" \
  "$source_root/qv/install/packaging" \
  "$source_root/qv/maintenance" \
  "$source_root/qv/shell" \
  "$test_home/.config/hypr/qv" \
  "$test_home/.local/bin" \
  "$test_home/.local/share/qvos/maintenance" \
  "$test_bin" \
  "$state/damaged" \
  "$state/mutable-dirs" \
  "$state/missing-files" \
  "$state/unverified" \
  "$pacman_db" \
  "$proc_root" \
  "$state/usr/lib/modules/test-kernel" \
  "$sys_root/bus/acpi/devices" \
  "$sys_root/class/dmi/id" \
  "$sys_root/class/power_supply" \
  "$sys_root"
printf 'linux\n' >"$state/usr/lib/modules/test-kernel/pkgbase"
touch "$proc_root/cpuinfo" "$state/lspci"
touch \
  "$sys_root/class/dmi/id/product_family" \
  "$sys_root/class/dmi/id/product_name" \
  "$sys_root/class/dmi/id/sys_vendor"

install -m 0755 \
  "$root/qv/maintenance/qvos-repair" \
  "$source_root/qv/maintenance/qvos-repair"
install -m 0755 \
  "$root/qv/maintenance/qv" \
  "$source_root/qv/maintenance/qv"
install -m 0755 \
  "$root/qv/maintenance/qvos-system" \
  "$source_root/qv/maintenance/qvos-system"
install -m 0755 \
  "$root/qv/maintenance/personal-software" \
  "$source_root/qv/maintenance/personal-software"
install -m 0755 \
  "$root/qv/maintenance/personal-software-baseline" \
  "$source_root/qv/maintenance/personal-software-baseline"
install -m 0644 \
  "$root/qv/maintenance/essential-packages" \
  "$source_root/qv/maintenance/essential-packages"
install -m 0755 \
  "$root/qv/config/refresh" \
  "$source_root/qv/config/refresh"
install -m 0755 \
  "$root/qv/shell/install" \
  "$source_root/qv/shell/install"
install -m 0755 \
  "$root/qv/shell/status" \
  "$source_root/qv/shell/status"
install -m 0755 \
  "$root/bin/omarchy-qvos-health" \
  "$source_root/bin/omarchy-qvos-health"
install -m 0755 \
  "$root/bin/omarchy-qvos-personal-software" \
  "$source_root/bin/omarchy-qvos-personal-software"
install -m 0755 \
  "$root/bin/omarchy-qvos-repair" \
  "$source_root/bin/omarchy-qvos-repair"
install -m 0755 \
  "$root/bin/omarchy-qvos-system" \
  "$source_root/bin/omarchy-qvos-system"

install -m 0644 /dev/stdin \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" <<'CONFIG'
misc {
  allow_session_lock_restore = true
}
CONFIG
install -m 0644 /dev/stdin \
  "$source_root/qv/config/files/hypr/qv/windows.conf" <<'CONFIG'
windowrule = float on, match:class ^test$
CONFIG
cp -a \
  "$source_root/qv/config/files/hypr/qv/." \
  "$test_home/.config/hypr/qv/"
printf 'source = ~/.config/hypr/qv/looknfeel.conf\n' \
  >"$test_home/.config/hypr/hyprland.conf"

install -m 0644 /dev/stdin \
  "$source_root/qv/install/packaging/base.packages" <<'PACKAGES'
alacritty
chromium
hyprland
hyprlock
PACKAGES
install -m 0755 /dev/stdin \
  "$source_root/qv/install/desktop-status" <<'SCRIPT'
#!/bin/bash
if [[ -e $QVOS_TEST_STATE/runtime-drift ]]; then
  echo "test runtime bytes or modes differ"
  exit 1
fi
SCRIPT
install -m 0644 /dev/stdin \
  "$source_root/qv/install/desktop" <<'SCRIPT'
# shellcheck shell=bash
rm -f "$QVOS_TEST_STATE/runtime-drift"
install -D -m 0644 \
  "$OMARCHY_PATH/qv/maintenance/essential-packages" \
  "$HOME/.local/share/qvos/maintenance/essential-packages"
install -D -m 0755 \
  "$OMARCHY_PATH/qv/maintenance/qvos-repair" \
  "$HOME/.local/share/qvos/maintenance/qvos-repair"
install -D -m 0755 \
  "$OMARCHY_PATH/qv/maintenance/qvos-system" \
  "$HOME/.local/share/qvos/maintenance/qvos-system"
install -D -m 0755 \
  "$OMARCHY_PATH/qv/maintenance/qv" \
  "$HOME/.local/bin/qv"
SCRIPT

git -C "$source_root" init -q -b OS
git -C "$source_root" config user.name "qvOS Test"
git -C "$source_root" config user.email "test@qvos.invalid"
git -C "$source_root" add -A
git -C "$source_root" commit -qm "Create recovery fixture"
git -C "$source_root" remote add origin https://github.com/Yaqyn-qvOS/qvOS.git
git -C "$source_root" update-ref refs/remotes/origin/OS HEAD

load_installed_defaults() {
  {
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' \
      "$source_root/qv/maintenance/essential-packages"
    printf '%s\n' linux linux-firmware
  } | sort -u >"$installed"
}
load_installed_defaults
touch "$action_log" "$integrity_log" "$pacman_log"

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Dk)
  if [[ -e $QVOS_TEST_STATE/database-bad ]]; then
    echo "database dependency error"
    exit 1
  fi
  echo "No database errors have been found!"
  ;;
-Qq)
  cat "$QVOS_TEST_INSTALLED"
  ;;
-Qk)
  printf 'Qk\t%s\n' "${*:2}" \
    >>"${QVOS_TEST_INTEGRITY_LOG:-/dev/null}"
  status=0
  shift
  for package in "$@"; do
    if [[ -e $QVOS_TEST_STATE/unverified/$package ]] &&
      [[ ${QVOS_TEST_PRIVILEGED:-0} != "1" ]]; then
      echo "error: $package: Permission denied"
      status=1
    elif [[ -e $QVOS_TEST_STATE/missing-files/$package ]]; then
      echo "$package: 2 total files, 1 missing file"
      status=1
    else
      echo "$package: 2 total files, 0 missing files"
    fi
  done
  exit "$status"
  ;;
-Qkk)
  printf 'Qkk\t%s\n' "${*:2}" \
    >>"${QVOS_TEST_INTEGRITY_LOG:-/dev/null}"
  status=0
  shift
  for package in "$@"; do
    if [[ -e $QVOS_TEST_STATE/unverified/$package ]] &&
      [[ ${QVOS_TEST_PRIVILEGED:-0} != "1" ]]; then
      echo "warning: $package: /root/private (failed to calculate SHA256 checksum)"
      echo "$package: 2 total files, 1 altered file"
      status=1
    elif [[ -e $QVOS_TEST_STATE/damaged/$package ]]; then
      damaged_file="$QVOS_TEST_STATE/damaged-file"
      touch "$damaged_file"
      echo "warning: $package: $damaged_file (SHA256 checksum mismatch)"
      echo "$package: 2 total files, 1 altered file"
      status=1
    elif [[ -e $QVOS_TEST_STATE/mutable-dirs/$package ]]; then
      mutable_dir="$QVOS_TEST_STATE/mutable-directory"
      mkdir -p "$mutable_dir"
      echo "warning: $package: $mutable_dir (GID mismatch)"
      echo "$package: 2 total files, 1 altered file"
      status=1
    else
      echo "$package: 2 total files, 0 altered files"
    fi
  done
  exit "$status"
  ;;
-Qqo)
  echo "linux"
  ;;
-S)
  printf 'pacman\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  for argument in "$@"; do
    rm -f "$QVOS_TEST_STATE/damaged/$argument"
    rm -f "$QVOS_TEST_STATE/missing-files/$argument"
  done
  ;;
*)
  echo "unexpected pacman arguments: $*" >&2
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/git" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"status --porcelain=v1 --untracked-files=all"* ]] &&
  [[ -e $QVOS_TEST_STATE/git-status-bad ]]; then
  echo "unable to read worktree state" >&2
  exit 1
fi
if [[ $* == *"fsck --connectivity-only --no-dangling"* ]] &&
  [[ -e $QVOS_TEST_STATE/git-fsck-bad ]]; then
  echo "broken object connectivity" >&2
  exit 1
fi
exec /usr/bin/git "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
printf 'add\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
for package in "$@"; do
  if ! grep -Fqx "$package" "$QVOS_TEST_INSTALLED"; then
    printf '%s\n' "$package" >>"$QVOS_TEST_INSTALLED"
  fi
done
sort -u -o "$QVOS_TEST_INSTALLED" "$QVOS_TEST_INSTALLED"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == "-v" ]]; then
  printf 'sudo\tvalidate\n' >>"$QVOS_TEST_ACTION_LOG"
  exit
fi
exec env QVOS_TEST_PRIVILEGED=1 "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/snapper" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
if [[ $* == *" list "* ]]; then
  printf '1\n'
  [[ -e $QVOS_TEST_STATE/snapshot-created ]] && printf '2\n'
elif [[ $* == *" create "* ]]; then
  if [[ -e $QVOS_TEST_STATE/snapshot-fail ]]; then
    exit 1
  fi
  printf 'snapshot\tcreate\n' >>"$QVOS_TEST_ACTION_LOG"
  touch "$QVOS_TEST_STATE/snapshot-created"
  printf '2\n'
else
  exit 2
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/findmnt" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"-o TARGET"* ]]; then
  echo "/boot"
else
  echo "rw,relatime"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/df" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
inode=0
[[ ${1:-} == "-Pi" ]] && inode=1
target=${2:-/}
if ((inode)); then
  printf 'Filesystem Inodes IUsed IFree IUse%% Mounted on\n'
  printf 'test 100000 1000 99000 1%% %s\n' "$target"
else
  available=10485760
  [[ $target == "/" ]] &&
    available=${QVOS_TEST_ROOT_AVAILABLE:-10485760}
  [[ $target == "$HOME" ]] &&
    available=${QVOS_TEST_HOME_AVAILABLE:-10485760}
  [[ $target == "/boot" ]] &&
    available=${QVOS_TEST_BOOT_AVAILABLE:-1048576}
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
  printf 'test 20000000 1 %s 1%% %s\n' "$available" "$target"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
arguments=" $* "
if [[ $arguments == *" --user list-units "* ]]; then
  exit
elif [[ $arguments == *" --user show wayland-session-waitenv.service "* ]]; then
  echo "success"
elif [[ $arguments == *" is-failed "* ]]; then
  unit=${!#}
  [[ -e $QVOS_TEST_STATE/failed-$unit ]]
elif [[ $arguments == *" is-enabled "* ]]; then
  unit=${!#}
  [[ ! -e $QVOS_TEST_STATE/disabled-$unit ]]
elif [[ $arguments == *" --user is-active "* ]]; then
  unit=${!#}
  [[ ! -e $QVOS_TEST_STATE/broken-$unit ]]
elif [[ $arguments == *" --user restart "* ]]; then
  unit=${!#}
  printf 'restart\t%s\n' "$unit" >>"$QVOS_TEST_ACTION_LOG"
  rm -f "$QVOS_TEST_STATE/broken-$unit"
elif [[ $arguments == *" enable "* ]]; then
  unit=${!#}
  printf 'enable\t%s\n' "$unit" >>"$QVOS_TEST_ACTION_LOG"
  rm -f "$QVOS_TEST_STATE/disabled-$unit"
else
  exit 2
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/busctl" <<'SCRIPT'
#!/bin/bash
[[ ! -e $QVOS_TEST_STATE/portal-owner-missing ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/Hyprland" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--verify-config" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
instances) exit ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
choose) printf '%s\n' "${QVOS_TEST_GUM_SELECTION:-Cancel}" ;;
confirm) [[ ${QVOS_TEST_GUM_CONFIRM:-1} == "1" ]] ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/ip" <<'SCRIPT'
#!/bin/bash
echo "default via 192.0.2.1"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/getent" <<'SCRIPT'
#!/bin/bash
echo "192.0.2.2 STREAM archlinux.org"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/timedatectl" <<'SCRIPT'
#!/bin/bash
echo "yes"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/uname" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "-r" ]] && echo "test-kernel"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/lspci" <<'SCRIPT'
#!/bin/bash
cat "$QVOS_TEST_STATE/lspci"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/dkms" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/modinfo" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/journalctl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/coredumpctl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy" <<'SCRIPT'
#!/bin/bash
printf 'omarchy\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hw-nvidia-gsp" <<'SCRIPT'
#!/bin/bash
[[ -e $QVOS_TEST_STATE/nvidia-gsp ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hw-nvidia-without-gsp" <<'SCRIPT'
#!/bin/bash
[[ -e $QVOS_TEST_STATE/nvidia-without-gsp ]]
SCRIPT

run_repair() {
  HOME="$test_home" \
    XDG_CACHE_HOME="$state/cache" \
    OMARCHY_PATH="$source_root" \
    QVOS_PACMAN_DB_PATH="$pacman_db" \
    QVOS_PACMAN_LOG="$pacman_log" \
    QVOS_PROC_ROOT="$proc_root" \
    QVOS_SYS_ROOT="$sys_root" \
    QVOS_TEST_STATE="$state" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_INTEGRITY_LOG="$integrity_log" \
    QVOS_INTEGRITY_WORKERS=3 \
    PATH="$test_bin:/usr/bin" \
    "$source_root/qv/maintenance/qvos-repair" "$@"
}

run_health() {
  HOME="$test_home" \
    XDG_CACHE_HOME="$state/cache" \
    OMARCHY_PATH="$source_root" \
    QVOS_PACMAN_DB_PATH="$pacman_db" \
    QVOS_PACMAN_LOG="$pacman_log" \
    QVOS_PROC_ROOT="$proc_root" \
    QVOS_SYS_ROOT="$sys_root" \
    QVOS_TEST_STATE="$state" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_INTEGRITY_LOG="$integrity_log" \
    QVOS_INTEGRITY_WORKERS=3 \
    PATH="$test_bin:/usr/bin" \
    "$source_root/bin/omarchy-qvos-health" "$@"
}

selected_hardware_packages() {
  sed -n \
    's/^.*packages\.hardware-selection[[:space:]]*running-system roots: //p' |
    tr ',' '\n' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

assert_hardware_selected() {
  local inventory=$1
  local package=$2

  grep -Fqx "$package" <<<"$inventory" ||
    fail "hardware package is not selected: $package"
}

assert_hardware_not_selected() {
  local inventory=$1
  local package=$2

  if grep -Fqx "$package" <<<"$inventory"; then
    fail "hardware package is selected unexpectedly: $package"
  fi
}

reset_hardware_fixture() {
  : >"$state/lspci"
  : >"$proc_root/cpuinfo"
  : >"$sys_root/class/dmi/id/product_family"
  : >"$sys_root/class/dmi/id/product_name"
  : >"$sys_root/class/dmi/id/sys_vendor"
  rm -f \
    "$state/nvidia-gsp" \
    "$state/nvidia-without-gsp"
  rm -rf \
    "$sys_root/bus/acpi/devices/"* \
    "$sys_root/class/power_supply/"*
}

touch "$state/unverified/sudo"
touch "$state/mutable-dirs/systemd"
: >"$integrity_log"
healthy_output=$(run_health)
[[ ${healthy_output%%$'\n'*} == "qvOS health: Inspect" ]] ||
  fail "health does not print its inspection state before the report"
grep -Fq '[Informational] packages.defaults-removed' <<<"$healthy_output" ||
  fail "removed defaults are informational"
grep -Fq 'Unverified without sudo: sudo' <<<"$healthy_output" ||
  fail "permission-denied checksum is Unverified"
if grep -Fq '[Repairable   ] packages.essential-damaged' <<<"$healthy_output"; then
  fail "runtime-managed package directory is treated as file corruption"
fi
grep -Fq 'qvOS is ready; no changes were made.' <<<"$healthy_output" ||
  fail "informational findings do not make qvOS unhealthy"
(( $(grep -c $'^Qk\t' "$integrity_log") == 3 )) ||
  fail "required-file integrity does not use bounded batches"
(( $(grep -c $'^Qkk\t' "$integrity_log") == 3 )) ||
  fail "checksum integrity does not use bounded batches"
run_health --check >/dev/null
[[ ! -s $action_log ]] || fail "read-only health mutates the fixture"
pass "status batches integrity and check ignores informational recovery readiness"

: >"$integrity_log"
set +e
cancel_output=$(QVOS_TEST_GUM_SELECTION=Cancel run_repair 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) || fail "interactive repair cancellation succeeds"
grep -Fq 'qvOS repair canceled.' <<<"$cancel_output" ||
  fail "interactive repair cancellation result"
[[ ! -s $integrity_log ]] ||
  fail "interactive repair inspects all packages before showing its menu"
pass "interactive repair shows its action menu before full inspection"

reset_hardware_fixture
printf '%s\n' \
  '03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi' \
  >"$state/lspci"
hardware_inventory=$(run_health | selected_hardware_packages)
assert_hardware_selected "$hardware_inventory" "vulkan-radeon"
if grep -q 'nvidia' <<<"$hardware_inventory"; then
  fail "AMD-only hardware selects NVIDIA packages"
fi

reset_hardware_fixture
cat >"$state/lspci" <<'PCI'
00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 630
00:1f.3 Audio device: Intel Corporation Audio
01:00.0 VGA compatible controller: NVIDIA Corporation GP107M [GeForce GTX 1050 Ti Mobile]
PCI
cat >"$proc_root/cpuinfo" <<'CPU'
vendor_id : GenuineIntel
model     : 158
CPU
install -d "$sys_root/class/power_supply/BAT0"
printf '1\n' >"$sys_root/class/power_supply/BAT0/present"
printf 'Battery\n' >"$sys_root/class/power_supply/BAT0/type"
touch "$state/nvidia-without-gsp"
hardware_inventory=$(run_health | selected_hardware_packages)
for package in vulkan-intel intel-media-driver libvpl vpl-gpu-rt \
  sof-firmware thermald nvidia-580xx-dkms nvidia-580xx-utils \
  lib32-nvidia-580xx-utils dkms linux-headers; do
  assert_hardware_selected "$hardware_inventory" "$package"
done
assert_hardware_not_selected "$hardware_inventory" "libva-nvidia-driver"

reset_hardware_fixture
printf '%s\n' \
  '01:00.0 VGA compatible controller: NVIDIA Corporation AD104 [GeForce RTX 4070]' \
  >"$state/lspci"
touch "$state/nvidia-gsp"
hardware_inventory=$(run_health | selected_hardware_packages)
for package in nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
  libva-nvidia-driver dkms linux-headers; do
  assert_hardware_selected "$hardware_inventory" "$package"
done

reset_hardware_fixture
cat >"$state/lspci" <<'PCI'
00:02.0 VGA compatible controller: Intel Corporation Panther Lake Graphics
00:1f.3 Multimedia audio controller: Intel Corporation Audio
PCI
cat >"$proc_root/cpuinfo" <<'CPU'
vendor_id : GenuineIntel
model     : 151
CPU
printf 'XPS 14 Panther Lake\n' >"$sys_root/class/dmi/id/product_name"
install -d \
  "$sys_root/class/power_supply/BAT0" \
  "$sys_root/bus/acpi/devices/CAMERA0"
printf '1\n' >"$sys_root/class/power_supply/BAT0/present"
printf 'Battery\n' >"$sys_root/class/power_supply/BAT0/type"
printf 'OVTI08F4\n' >"$sys_root/bus/acpi/devices/CAMERA0/hid"
hardware_inventory=$(run_health | selected_hardware_packages)
for package in vulkan-intel intel-media-driver libvpl vpl-gpu-rt \
  sof-firmware thermald intel-lpmd intel-ipu7-camera linux-ptl \
  linux-ptl-headers; do
  assert_hardware_selected "$hardware_inventory" "$package"
done

reset_hardware_fixture
printf '%s\n' \
  '00:02.0 VGA compatible controller: Intel Corporation GMA 4500' \
  >"$state/lspci"
hardware_inventory=$(run_health | selected_hardware_packages)
assert_hardware_selected "$hardware_inventory" "vulkan-intel"
assert_hardware_selected "$hardware_inventory" "libva-intel-driver"
assert_hardware_not_selected "$hardware_inventory" "intel-media-driver"

reset_hardware_fixture
cat >"$state/lspci" <<'PCI'
00:02.0 Display controller: Apple Inc. Display
02:00.0 Network controller [0280]: Broadcom Inc. [14e4:43a0]
03:00.0 Ethernet controller: Motorcomm YT6801
04:00.0 Processing accelerators: Apple Inc. [106b:1801]
PCI
printf 'MacBookPro14,1\n' >"$sys_root/class/dmi/id/product_name"
printf 'TUXEDO Computers\n' >"$sys_root/class/dmi/id/sys_vendor"
hardware_inventory=$(run_health | selected_hardware_packages)
for package in vulkan-asahi broadcom-wl yt6801-dkms \
  tuxedo-drivers-nocompatcheck-dkms macbook12-spi-driver-dkms linux-t2 \
  linux-t2-headers apple-t2-audio-config apple-bcm-firmware t2fanrd \
  tiny-dfr dkms linux-headers; do
  assert_hardware_selected "$hardware_inventory" "$package"
done
reset_hardware_fixture
pass "hardware recovery covers every conditional platform package family"

mapfile -t hardware_install_packages < <(
  for path in $(
    rg -l 'omarchy-pkg-add|PACKAGES=|VULKAN_DRIVERS=' \
      "$root/install/config/hardware"
  ); do
    awk '
      /(PACKAGES|VULKAN_DRIVERS)=\(/ {
        packages = 1
        print
        if (/\)/) packages = 0
        next
      }
      packages {
        print
        if (/\)/) packages = 0
        next
      }
      /omarchy-pkg-add/ {
        print
        continuation = /\\$/
        next
      }
      continuation {
        print
        continuation = /\\$/
      }
    ' "$path"
  done |
    tr '()[]\\"=' '        ' |
    tr '[:space:]' '\n' |
    grep -E '^[a-z0-9][a-z0-9@._+-]*$' |
    grep -Ev '^(declare|omarchy-pkg-add|PACKAGES|VULKAN_DRIVERS)$' |
    sort -u
)
for package in "${hardware_install_packages[@]}"; do
  grep -qw "$package" "$source_root/qv/maintenance/qvos-repair" ||
    fail "hardware installer package lacks a recovery owner: $package"
done
pass "hardware installer package additions stay covered by Recovery"

grep -Fvx jq "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
grep -Fvx linux-firmware "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
touch "$state/damaged/hyprlock"
set +e
unhealthy_output=$(run_health --check 2>&1)
unhealthy_status=$?
set -e
((unhealthy_status == 1)) || fail "check accepts repairable findings"
grep -Fq '[Repairable   ] packages.essential-missing' <<<"$unhealthy_output" ||
  fail "missing essential classification"
grep -Fq '[Repairable   ] packages.essential-damaged' <<<"$unhealthy_output" ||
  fail "damaged essential classification"
grep -Fq '[Repairable   ] packages.hardware-missing' <<<"$unhealthy_output" ||
  fail "missing hardware classification"
[[ ! -s $action_log ]] || fail "package inspection performs repair"
pass "essential, hardware, corruption, and default classes stay distinct"

load_installed_defaults
rm -f "$state/damaged/hyprlock"
touch "$state/database-bad"
grep -Fq '[Blocked      ] pacman.database' < <(run_health) ||
  fail "Pacman database failure"
rm -f "$state/database-bad"

touch "$pacman_db/db.lck"
grep -Fq '[Blocked      ] pacman.lock-ownerless' < <(run_health) ||
  fail "ownerless Pacman lock"
install -d "$proc_root/222/fd"
ln -s "$pacman_db/db.lck" "$proc_root/222/fd/3"
grep -Fq '[Blocked      ] pacman.lock-active' < <(run_health) ||
  fail "active Pacman lock"
rm -f "$proc_root/222/fd/3" "$pacman_db/db.lck"

printf '[ALPM] transaction started\n' >"$pacman_log"
grep -Fq '[Blocked      ] pacman.transaction-incomplete' < <(run_health) ||
  fail "unmatched Pacman transaction"
printf '[ALPM] transaction completed\n' >>"$pacman_log"
pass "Pacman database, lock ownership, and transaction state are explicit"

touch "$source_root/untracked-recovery-test"
grep -Fq '[Blocked      ] source.worktree' < <(run_health) ||
  fail "untracked source state"
rm -f "$source_root/untracked-recovery-test"
touch "$state/git-status-bad"
status_failure_output=$(run_health)
grep -Fq '[Blocked      ] source.worktree' <<<"$status_failure_output" ||
  fail "unreadable worktree state"
grep -Fq 'complete worktree status could not be read' <<<"$status_failure_output" ||
  fail "worktree-status failure detail"
rm -f "$state/git-status-bad"
touch "$state/git-fsck-bad"
grep -Fq '[Blocked      ] source.connectivity' < <(run_health) ||
  fail "Git connectivity failure"
rm -f "$state/git-fsck-bad"
mv \
  "$source_root/qv/config/refresh" \
  "$source_root/qv/config/refresh.missing"
grep -Fq '[Blocked      ] source.required-paths' < <(run_health) ||
  fail "required tracked source deletion"
mv \
  "$source_root/qv/config/refresh.missing" \
  "$source_root/qv/config/refresh"
pass "dirty, disconnected, and missing Git source states block mutation"

storage_output=$(QVOS_TEST_ROOT_AVAILABLE=1048576 run_health)
grep -Fq '[Blocked      ] storage.root-blocked' <<<"$storage_output" ||
  fail "root storage hard threshold"
warning_output=$(QVOS_TEST_ROOT_AVAILABLE=3145728 run_health)
grep -Fq '[Informational] storage.root-warning' <<<"$warning_output" ||
  fail "root storage warning threshold"
boot_output=$(QVOS_TEST_BOOT_AVAILABLE=131072 run_health)
grep -Fq '[Blocked      ] storage.boot-blocked' <<<"$boot_output" ||
  fail "boot storage hard threshold"
pass "root, home, and boot storage thresholds gate persistent repair"

chmod 0600 "$test_home/.config/hypr/qv/windows.conf"
mode_output=$(run_health)
grep -Fq '[Repairable   ] config.mode-drift' <<<"$mode_output" ||
  fail "same-byte config mode drift"
printf '\n# user choice\n' \
  >>"$test_home/.config/hypr/qv/looknfeel.conf"
custom_output=$(run_health)
grep -Fq '[Informational] config.customized' <<<"$custom_output" ||
  fail "custom config preservation"
pass "same-byte mode drift repairs separately from customized config"

cp -a \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" \
  "$test_home/.config/hypr/qv/looknfeel.conf"
chmod 0644 "$test_home/.config/hypr/qv/windows.conf"
grep -Fvx jq "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
touch "$state/snapshot-fail"
: >"$action_log"
set +e
snapshot_output=$(run_repair --yes 2>&1)
snapshot_status=$?
set -e
((snapshot_status == 1)) || fail "failed snapshot allows repair"
grep -Fq 'snapshot creation failed' <<<"$snapshot_output" ||
  fail "failed snapshot explanation"
if grep -Eq $'^(add|pacman|restart|enable)\t' "$action_log"; then
  fail "failed snapshot permits persistent mutation"
fi
rm -f "$state/snapshot-fail"
load_installed_defaults
pass "persistent repair aborts when a newer root snapshot is not proven"

: >"$action_log"
set +e
reset_yes_output=$(run_repair --reset --yes 2>&1)
reset_yes_status=$?
set -e
((reset_yes_status == 2)) || fail "--reset --yes bypasses explicit Reset confirmation"
grep -Fq -- '--yes selects Safe Repair only' <<<"$reset_yes_output" ||
  fail "Reset explains the --yes boundary"
[[ ! -s $action_log ]] || fail "rejected --reset --yes mutates the fixture"
pass "--yes is limited to Safe Repair"

grep -Fvx jq "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
grep -Fvx linux-firmware "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
touch \
  "$state/damaged/hyprlock" \
  "$state/runtime-drift" \
  "$state/broken-xdg-desktop-portal-hyprland.service" \
  "$state/disabled-sddm.service"
rm -f "$test_home/.config/hypr/qv/looknfeel.conf"
chmod 0600 "$test_home/.config/hypr/qv/windows.conf"
: >"$action_log"
repair_output=$(run_repair --yes)
grep -Fq 'qvOS safe repair is complete.' <<<"$repair_output" ||
  fail "safe repair result"
grep -Fq $'add\tjq linux-firmware' "$action_log" ||
  fail "missing essential and hardware repair"
grep -Fq $'pacman\t-S --noconfirm --overwrite * hyprlock' "$action_log" ||
  fail "forced damaged-package reinstall"
grep -Fq $'restart\txdg-desktop-portal-hyprland.service' "$action_log" ||
  fail "targeted portal restart"
grep -Fq $'enable\tsddm.service' "$action_log" ||
  fail "SDDM enable without restart"
[[ ! -e $state/runtime-drift ]] || fail "runtime repair"
cmp -s \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" \
  "$test_home/.config/hypr/qv/looknfeel.conf" ||
  fail "missing config repair"
[[ $(stat -c '%a' "$test_home/.config/hypr/qv/windows.conf") == "644" ]] ||
  fail "config mode repair"
snapshot_line=$(grep -nF $'snapshot\tcreate' "$action_log" | head -n 1 | cut -d: -f1)
package_line=$(
  grep -nE $'^(add|pacman)\t' "$action_log" |
    head -n 1 |
    cut -d: -f1
)
((snapshot_line < package_line)) || fail "snapshot does not precede package mutation"
pass "Safe Repair follows package, runtime, config, and targeted-service order"

grep -Fvx chromium "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
printf '\n# reset me\n' \
  >>"$test_home/.config/hypr/qv/looknfeel.conf"
rm -f "$state/snapshot-created"
: >"$action_log"
reset_output=$(run_repair --reset)
grep -Fq 'qvOS reset is complete.' <<<"$reset_output" ||
  fail "reset result"
grep -Fq $'add\tchromium' "$action_log" ||
  fail "Reset default package restore"
cmp -s \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" \
  "$test_home/.config/hypr/qv/looknfeel.conf" ||
  fail "Reset config restore"
compgen -G "$test_home/.config/hypr/qv/looknfeel.conf.bak.*" >/dev/null ||
  fail "Reset config backup"
pass "Reset remains explicit, snapshot-gated, and backup-backed"

install -m 0644 \
  "$source_root/qv/maintenance/essential-packages" \
  "$test_home/.local/share/qvos/maintenance/essential-packages"
install -m 0755 \
  "$source_root/qv/maintenance/qvos-repair" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair"
install -m 0755 \
  "$source_root/qv/maintenance/qv" \
  "$test_home/.local/bin/qv"
mv \
  "$test_home/.local/share/qvos/maintenance/qvos-repair" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair.missing"
set +e
missing_runtime_output=$(
  HOME="$test_home" PATH="$test_bin:/usr/bin" \
    "$test_home/.local/bin/qv" repair --status 2>&1
)
missing_runtime_status=$?
set -e
((missing_runtime_status == 1)) || fail "qv accepts a missing recovery runtime"
grep -Fq 'qvOS recovery runtime is unavailable' <<<"$missing_runtime_output" ||
  fail "qv missing-runtime explanation"
mv \
  "$test_home/.local/share/qvos/maintenance/qvos-repair.missing" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair"
mv \
  "$source_root/qv/maintenance/qvos-repair" \
  "$source_root/qv/maintenance/qvos-repair.damaged"
runtime_output=$(
  HOME="$test_home" \
    XDG_CACHE_HOME="$state/cache" \
    OMARCHY_PATH="$source_root" \
    QVOS_PACMAN_DB_PATH="$pacman_db" \
    QVOS_PACMAN_LOG="$pacman_log" \
    QVOS_PROC_ROOT="$proc_root" \
    QVOS_SYS_ROOT="$sys_root" \
    QVOS_TEST_STATE="$state" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    "$test_home/.local/bin/qv" repair --status
)
grep -Fq '[Blocked      ] source.required-paths' <<<"$runtime_output" ||
  fail "runtime engine cannot diagnose source-tree damage"
mv \
  "$source_root/qv/maintenance/qvos-repair.damaged" \
  "$source_root/qv/maintenance/qvos-repair"
: >"$action_log"
HOME="$test_home" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$test_home/.local/bin/qv" commands --json
grep -Fq $'omarchy\tcommands --json' "$action_log" ||
  fail "qv non-repair passthrough"
pass "qv repair survives source damage and other qv arguments pass through"

commands=$("$root/bin/omarchy" commands --json)
for binary in omarchy-qvos-health omarchy-qvos-repair omarchy-qvos-system; do
  jq -e --arg binary "$binary" \
    'any(.commands[]; .binary == $binary)' <<<"$commands" >/dev/null ||
    fail "$binary command discovery"
done
pass "system, health, and repair remain discoverable Omarchy commands"
