#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home" "$test_bin"
touch "$action_log"
install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'STUB'
#!/bin/bash
printf 'add\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-drop" <<'STUB'
#!/bin/bash
printf 'drop\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'STUB'
#!/bin/bash
for command in "$@"; do
  [[ $command != "lspci" || ${QVOS_TEST_LSPCI_AVAILABLE:-1} == "1" ]] || exit 1
  command -v -- "$command" >/dev/null 2>&1 || exit 1
done
STUB
install -m 0755 /dev/stdin "$test_bin/lspci" <<'STUB'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_PCI_INVENTORY:-}"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-hw-nvidia-gsp" <<'STUB'
#!/bin/bash
[[ ${QVOS_TEST_NVIDIA:-none} == "gsp" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/qv-hw-nvidia-without-gsp" <<'STUB'
#!/bin/bash
[[ ${QVOS_TEST_NVIDIA:-none} == "legacy" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/qv-webapp-install" <<'STUB'
#!/bin/bash
printf 'webapp-install\t%s\t%s\t%s\n' "$1" "$2" "$3" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-webapp-remove" <<'STUB'
#!/bin/bash
printf 'webapp-remove\t%s\n' "$1" >>"$QVOS_TEST_ACTION_LOG"
STUB

run_gaming() {
  HOME="$test_home" \
    QVOS_PATH="$root" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_LSPCI_AVAILABLE="${QVOS_TEST_LSPCI_AVAILABLE:-1}" \
    QVOS_TEST_PCI_INVENTORY="${QVOS_TEST_PCI_INVENTORY:-}" \
    QVOS_TEST_NVIDIA="${QVOS_TEST_NVIDIA:-none}" \
    "$@"
}

QVOS_TEST_PCI_INVENTORY='00:02.0 VGA compatible controller: Intel Corporation UHD Graphics'
QVOS_TEST_NVIDIA=gsp
export QVOS_TEST_PCI_INVENTORY QVOS_TEST_NVIDIA
run_gaming "$root/bin/qv-install-gaming-heroic" >/dev/null
[[ $(<"$action_log") == $'add\theroic-games-launcher-bin lib32-vulkan-intel lib32-nvidia-utils' ]] ||
  fail "Heroic single package transaction with detected graphics"

heroic_data="$test_home/.config/heroic/settings.json"
install -D -m 0600 /dev/stdin "$heroic_data" <<'DATA'
user data
DATA
: >"$action_log"
run_gaming "$root/bin/omarchy-remove-gaming-heroic" >/dev/null
[[ $(<"$action_log") == $'drop\theroic-games-launcher-bin' && -f $heroic_data ]] ||
  fail "Heroic compatibility removal preserves user data"

: >"$action_log"
run_gaming "$root/bin/omarchy-install-gaming-lutris" >/dev/null
[[ $(<"$action_log") == $'add\tlutris lib32-vulkan-intel lib32-nvidia-utils' ]] ||
  fail "Lutris reuses the qvOS gaming runtime without conflicting packages"

: >"$action_log"
run_gaming "$root/bin/qv-install-gaming-moonlight" >/dev/null
[[ $(<"$action_log") == $'add\tmoonlight-qt' ]] ||
  fail "Moonlight package-only install"

: >"$action_log"
run_gaming "$root/bin/qv-install-gaming-minecraft" >/dev/null
run_gaming "$root/bin/omarchy-remove-gaming-minecraft" >/dev/null
[[ $(<"$action_log") == $'add\tminecraft-launcher\ndrop\tminecraft-launcher' ]] ||
  fail "Minecraft native lifecycle"
[[ -x $root/bin/omarchy-install-gaming-minecraft ]] ||
  fail "Minecraft compatibility install adapter"

QVOS_TEST_PCI_INVENTORY='03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi'
QVOS_TEST_NVIDIA=legacy
export QVOS_TEST_PCI_INVENTORY QVOS_TEST_NVIDIA
drivers=$(run_gaming "$root/qvcore/gaming/gpu-lib32" --list)
[[ $drivers == $'lib32-vulkan-radeon\nlib32-nvidia-580xx-utils' ]] ||
  fail "AMD and legacy NVIDIA lib32 detection"

QVOS_TEST_LSPCI_AVAILABLE=0
QVOS_TEST_NVIDIA=none
export QVOS_TEST_LSPCI_AVAILABLE QVOS_TEST_NVIDIA
[[ -z $(run_gaming "$root/qvcore/gaming/gpu-lib32" --list) ]] ||
  fail "absent graphics inventory"
unset QVOS_TEST_LSPCI_AVAILABLE

: >"$action_log"
run_gaming "$root/bin/qv-install-gaming-xbox-cloud" >/dev/null
run_gaming "$root/bin/omarchy-remove-gaming-xbox-cloud" >/dev/null
[[ $(<"$action_log") == $'webapp-install\tXbox Cloud Gaming\thttps://www.xbox.com/en-US/play\tapplications-games\nwebapp-remove\tXbox Cloud Gaming' ]] ||
  fail "Xbox Cloud delegates to the optional native Web App lifecycle"

if run_gaming "$root/qvcore/gaming/app" install unknown >/dev/null 2>&1; then
  fail "unknown gaming app"
fi
if run_gaming "$root/bin/qv-install-gaming-steam" unexpected >/dev/null 2>&1; then
  fail "gaming app argument validation"
fi

for expected_row in \
  'steam|package|steam|tui|true|tui|true|qv-install-gaming-steam|qvcore/gaming/steam-remove' \
  'minecraft|package|minecraft-launcher|tui|true|tui|true|qv-install-gaming-minecraft|qv-remove-gaming-minecraft' \
  'geforce-now|flatpak|com.nvidia.geforcenow|native|true|tui|false|qv-install-gaming-geforce-now|qv-remove-gaming-geforce-now' \
  'xbox-cloud|file|.local/share/applications/Xbox Cloud Gaming.desktop|tui|false|tui|false|qv-install-gaming-xbox-cloud|qv-remove-gaming-xbox-cloud' \
  'moonlight|package|moonlight-qt|tui|true|tui|true|qv-install-gaming-moonlight|qv-remove-gaming-moonlight' \
  'lutris|package|lutris|tui|true|tui|true|qv-install-gaming-lutris|qv-remove-gaming-lutris' \
  'heroic|package|heroic-games-launcher-bin|tui|true|tui|true|qv-install-gaming-heroic|qv-remove-gaming-heroic'; do
  grep -Fqx "$expected_row" "$root/qvcore/menu/software-actions.psv" ||
    fail "native gaming catalog row: ${expected_row%%|*}"
done

"$root/qvcore/gaming/check"
printf 'ok - optional gaming apps use singular native package and Web App owners\n'
