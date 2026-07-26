#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
health="$root/qv/core/health.sh"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
fixture="$test_root/omarchy"
state="$test_root/state"
repair_log="$test_root/repair.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
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
  "$test_bin" \
  "$fixture/qv/core/dev" \
  "$state/commands" \
  "$state/packages" \
  "$test_root/.config/hypr/qv" \
  "$test_root/.config/omarchy/hooks/post-update.d" \
  "$test_root/.local/state/qvos/qvcore"

for component in share codex proton; do
  install -m 0755 /dev/stdin "$fixture/qv/core/$component.sh" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--status" ]] || exit 2
[[ -f $QVOS_TEST_HEALTH_STATE/ready-$(basename "$0" .sh) ]]
SCRIPT
  install -m 0644 /dev/null "$state/ready-$component"
done

install -m 0755 /dev/stdin "$fixture/qv/core/media.sh" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--status" ]] || exit 2
count=$(<"$QVOS_TEST_HEALTH_STATE/media-count")
printf 'qvCORE Media inventory: %s/7 ready\n' "$count"
((count > 0))
SCRIPT
printf '7\n' >"$state/media-count"

printf 'qvCORE Devel maintenance\n' >"$fixture/qv/core/dev/post-update.sh"
cp \
  "$fixture/qv/core/dev/post-update.sh" \
  "$test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore-dev"
install -m 0644 /dev/null "$test_root/.local/state/qvos/qvcore/dev"

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/commands/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/packages/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-default-browser" <<'SCRIPT'
#!/bin/bash
printf 'brave-origin\n'
SCRIPT

install -m 0755 /dev/stdin "$test_bin/warp-cli" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_HEALTH_STATE/warp-registered ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "choose" ]] || exit 1
printf '%s\n' "${QVOS_TEST_HEALTH_CHOICE:-share}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-install-qvcore" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_HEALTH_REPAIR_LOG"
SCRIPT

for command in warp-cli localsend codex proton-drive bun; do
  install -m 0644 /dev/null "$state/commands/$command"
done
for package in \
  brave-origin-beta-bin \
  steam \
  gimp \
  inkscape \
  krita \
  kdenlive \
  obs-studio \
  audacity \
  blender; do
  install -m 0644 /dev/null "$state/packages/$package"
done
install -m 0644 /dev/null "$state/warp-registered"

printf '%s\n' 'windowrule = workspace name:G silent, class:^(steam)$' \
  >"$test_root/.config/hypr/qv/windows.conf"
printf '%s\n' 'bindd = SUPER CTRL, grave, Steam, exec, steam' \
  >"$test_root/.config/hypr/qv/bindings.conf"

run_health() {
  QVOS_TEST_HEALTH_CHOICE="${QVOS_TEST_HEALTH_CHOICE:-share}" \
    QVOS_TEST_HEALTH_REPAIR_LOG="$repair_log" \
    QVOS_TEST_HEALTH_STATE="$state" \
    HOME="$test_root" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    "$health" "$@"
}

ready_output=$(run_health status)
grep -Fq 'Ready: 8  Partial: 0  Missing: 0' <<<"$ready_output" ||
  fail "all-ready qvCORE health summary"
pass "qvCORE health reports every complete component"

rm -f \
  "$state/ready-share" \
  "$state/ready-codex" \
  "$state/commands/codex" \
  "$state/warp-registered"
printf '6\n' >"$state/media-count"

drift_output=$(run_health status)
grep -Fq 'Ready: 5  Partial: 2  Missing: 1' <<<"$drift_output" ||
  fail "mixed qvCORE health summary"
grep -Fq 'Share          partial' <<<"$drift_output" ||
  fail "Share drift status"
grep -Fq 'Codex          missing' <<<"$drift_output" ||
  fail "Codex missing status"
pass "qvCORE health distinguishes missing components from integration drift"

QVOS_TEST_HEALTH_CHOICE=share run_health repair >/dev/null
[[ $(<"$repair_log") == "share" ]] ||
  fail "qvCORE repair delegates to the existing component route"
pass "qvCORE repair reuses the independently rerunnable installer"

if run_health unknown >/dev/null 2>&1; then
  fail "unknown qvCORE health mode succeeds"
fi
pass "qvCORE health rejects unknown modes without mutation"
