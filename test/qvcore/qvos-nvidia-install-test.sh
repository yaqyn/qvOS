#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
stage="$root/qvcore/install/config/hardware/nvidia.sh"
default_env="$root/qvcore/config/files/hypr/envs.lua"
gsp_env="$root/qvcore/install/hardware/nvidia/env-gsp.lua"
legacy_env="$root/qvcore/install/hardware/nvidia/env-legacy.lua"
modprobe_source="$root/qvcore/install/hardware/nvidia/modprobe.conf"
mkinitcpio_source="$root/qvcore/install/hardware/nvidia/mkinitcpio.conf"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
package_log="$test_root/packages.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/lspci" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_LSPCI:-}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $# == 1 && $1 == "lspci" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_PACKAGE_LOG"
SCRIPT

prepare_fixture() {
  local fixture=$1

  install -d "$fixture/system" "$fixture/home/.config/hypr"
  install -m 0644 "$default_env" "$fixture/home/.config/hypr/envs.lua"
}

run_stage() {
  local fixture=$1
  local inventory=$2

  : >"$package_log"
  QVOS_PATH="$root" \
  HOME="$fixture/home" \
  QVOS_INSTALL_HARDWARE_TESTING=1 \
  QVOS_INSTALL_HARDWARE_SYSTEM_ROOT="$fixture/system" \
  QVOS_HARDWARE_TESTING=1 \
  QVOS_HARDWARE_FIXTURE_ROOT="$fixture/system" \
  QVOS_TEST_LSPCI="$inventory" \
  QVOS_TEST_PACKAGE_LOG="$package_log" \
  QVOS_TEST_CONTINUE_FILE="$fixture/continued" \
  PATH="$test_bin:$root/bin:/usr/bin" \
    bash -euc 'source "$1"; : >"$QVOS_TEST_CONTINUE_FILE"' _ "$stage"
}

legacy_root="$test_root/legacy"
prepare_fixture "$legacy_root"
run_stage "$legacy_root" \
  '01:00.0 VGA compatible controller: NVIDIA Corporation GeForce GTX 1060 [10de:1c20]'
[[ $(<"$package_log") == \
  'linux-headers nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils' ]] ||
  fail "legacy NVIDIA package selection"
cmp -s "$legacy_env" "$legacy_root/home/.config/hypr/envs.lua" ||
  fail "legacy NVIDIA environment"
cmp -s "$modprobe_source" \
  "$legacy_root/system/etc/modprobe.d/qvos-nvidia.conf" ||
  fail "legacy NVIDIA modprobe policy"
cmp -s "$mkinitcpio_source" \
  "$legacy_root/system/etc/mkinitcpio.conf.d/qvos-nvidia.conf" ||
  fail "legacy NVIDIA initramfs policy"
[[ -f $legacy_root/continued ]] || fail "supported NVIDIA stage returned to installer"

gsp_root="$test_root/gsp"
prepare_fixture "$gsp_root"
run_stage "$gsp_root" \
  '01:00.0 VGA compatible controller: NVIDIA Corporation GeForce RTX 4060 [10de:2882]'
[[ $(<"$package_log") == \
  'linux-headers nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver' ]] ||
  fail "GSP NVIDIA package selection"
cmp -s "$gsp_env" "$gsp_root/home/.config/hypr/envs.lua" ||
  fail "GSP NVIDIA environment"
[[ -f $gsp_root/continued ]] || fail "GSP NVIDIA stage returned to installer"

unsupported_root="$test_root/unsupported"
prepare_fixture "$unsupported_root"
run_stage "$unsupported_root" \
  '01:00.0 VGA compatible controller: NVIDIA Corporation GeForce GTX 780 [10de:1004]'
[[ ! -s $package_log ]] || fail "unsupported NVIDIA GPU requested packages"
cmp -s "$default_env" "$unsupported_root/home/.config/hypr/envs.lua" ||
  fail "unsupported NVIDIA GPU changed its environment"
[[ ! -e $unsupported_root/system/etc/modprobe.d/qvos-nvidia.conf &&
  ! -e $unsupported_root/system/etc/mkinitcpio.conf.d/qvos-nvidia.conf &&
  -f $unsupported_root/continued ]] ||
  fail "unsupported NVIDIA stage terminated or installed boot policy"

modified_root="$test_root/modified"
prepare_fixture "$modified_root"
printf 'user environment\n' >"$modified_root/home/.config/hypr/envs.lua"
if run_stage "$modified_root" \
  '01:00.0 VGA compatible controller: NVIDIA Corporation GeForce RTX 4060 [10de:2882]' \
  >/dev/null 2>&1; then
  fail "modified NVIDIA environment was accepted"
fi
[[ $(<"$modified_root/home/.config/hypr/envs.lua") == "user environment" &&
  ! -s $package_log &&
  ! -e $modified_root/system/etc/modprobe.d/qvos-nvidia.conf ]] ||
  fail "modified NVIDIA environment was changed after partial setup"

printf 'ok - NVIDIA setup is native, source-owned, preservation-safe, and return-safe\n'
