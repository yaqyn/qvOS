#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
capture="$test_root/capture"
owner_log="$test_root/owner.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/qv/tui/task/presenters" \
  "$source_root/qv/tui" \
  "$test_home" \
  "$test_bin"
install -m 0755 "$root/qv/tui/task/run" "$source_root/qv/tui/task/run"
install -m 0644 /dev/stdin "$source_root/qv/tui/task/actions.psv" <<'CATALOG'
# slug|title|summary|rings|presentation|requires_sudo|primary|active|complete|owner
refresh-test|Test Config|Restore a test config|1|tui|false|Restore|Restoring|Restored|test-owner apply
presented-test|Presented State|Read back a silent owner|1|tui|false|Inspect|Inspecting|Inspected|test-owner presented
critical-test|Critical Config|Restore a critical config|3|tui|true|Restore|Restoring|Restored|test-owner critical
firmware-test|Firmware|Retain native firmware prompts|3|native|true|Update|Updating|Updated|test-native firmware
CATALOG
install -m 0755 /dev/stdin "$source_root/qv/tui/task/presenters/presented-test" <<'PRESENTER'
#!/bin/bash
"$@"
printf 'Verified state: ready\n'
PRESENTER
install -m 0755 /dev/stdin "$source_root/qv/tui/launch" <<'LAUNCH'
#!/bin/bash
{
  printf '%s\n' "$*"
  printf '%s\n' "$QVOS_ACTION_SLUG"
  printf '%s\n' "$QVOS_ACTION_OPERATION"
  printf '%s\n' "$QVOS_ACTION_RINGS"
  printf '%s\n' "$QVOS_ACTION_PRIMARY"
  printf '%s\n' "$QVOS_ACTION_ACTIVE"
  printf '%s\n' "$QVOS_ACTION_COMPLETE"
  printf '%s\n' "$QVOS_ACTION_REQUIRES_SUDO"
  printf '%s\n' "$QVOS_ACTION_SCRIPT"
} >"$QVOS_TASK_TEST_CAPTURE"
LAUNCH
install -m 0755 /dev/stdin "$test_bin/test-owner" <<'OWNER'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TASK_TEST_OWNER_LOG"
printf 'Owner result: %s\n' "$*"
OWNER
install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'NATIVE'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TASK_TEST_CAPTURE"
NATIVE
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SYSTEMCTL'
#!/bin/bash
[[ $1 == "is-active" && $2 == "systemd-timesyncd" ]] || exit 2
printf 'active\n'
SYSTEMCTL
install -m 0755 /dev/stdin "$test_bin/timedatectl" <<'TIMEDATECTL'
#!/bin/bash
case $* in
*"NTPSynchronized"*) printf 'yes\n' ;;
*"Timezone"*) printf 'Africa/Cairo\n' ;;
*"NTP"*) printf 'yes\n' ;;
*) exit 2 ;;
esac
TIMEDATECTL

HOME="$test_home" \
OMARCHY_PATH="$source_root" \
PATH="$test_bin:$PATH" \
QVOS_TASK_TEST_CAPTURE="$capture" \
QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
  "$root/qv/tui/task/launch" refresh-test

[[ $(sed -n '1p' "$capture") == "Test Config qvos-tui --action" ]] ||
  fail "task launcher did not reuse the shared qvOS action mode"
[[ $(sed -n '2,9p' "$capture") == $'refresh-test\ntask\n1\nRestore\nRestoring\nRestored\n0\n'"$source_root/qv/tui/task/run" ]] ||
  fail "task launcher lost its classified TUI contract"

HOME="$test_home" \
OMARCHY_PATH="$source_root" \
PATH="$test_bin:$PATH" \
QVOS_ACTION_SLUG=refresh-test \
QVOS_ACTION_OPERATION=task \
QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
  "$root/qv/tui/task/run" --check

task_output=$(
  HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_ACTION_SLUG=refresh-test \
  QVOS_ACTION_OPERATION=task \
  QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
    "$root/qv/tui/task/run"
)
[[ $task_output == "Owner result: apply" ]] ||
  fail "one-ring task hid its owner information behind synthetic milestones"
[[ $(wc -l <"$owner_log") == 1 && $(<"$owner_log") == "apply" ]] ||
  fail "task runner did not delegate exactly once"

presented_output=$(
  HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_ACTION_SLUG=presented-test \
  QVOS_ACTION_OPERATION=task \
  QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
    "$root/qv/tui/task/run"
)
[[ $presented_output == $'Owner result: presented\nVerified state: ready' ]] ||
  fail "one-ring presenter did not replace vague output with verified state"
[[ $(wc -l <"$owner_log") == 2 && $(tail -n 1 "$owner_log") == "presented" ]] ||
  fail "one-ring presenter did not delegate exactly once"

readback_owner_log="$test_root/readback-owner.log"
readback_output=$(
  PATH="$test_bin:$PATH" \
  QVOS_TASK_TEST_OWNER_LOG="$readback_owner_log" \
    "$root/qv/tui/task/presenters/time-sync" test-owner time-sync
)
[[ $readback_output == $'Status: Synchronized\nService: Active\nNetwork time: Enabled\nTimezone: Africa/Cairo' ]] ||
  fail "System Time presenter did not replace activity copy with verified readback"
[[ $(wc -l <"$readback_owner_log") == 1 && $(<"$readback_owner_log") == "time-sync" ]] ||
  fail "System Time presenter did not delegate exactly once"

set +e
failure_output=$(
  "$root/qv/tui/task/presenters/time-sync" \
    bash -c 'echo "exact owner failure" >&2; exit 7' 2>&1
)
failure_status=$?
set -e
[[ $failure_status == 7 && $failure_output == "exact owner failure" ]] ||
  fail "System Time presenter did not preserve the exact owner failure"

critical_output=$(
  HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_ACTION_SLUG=critical-test \
  QVOS_ACTION_OPERATION=task \
  QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
    "$root/qv/tui/task/run"
)
[[ $critical_output == $'qvOS action: preparing\nqvOS action: applying\nOwner result: critical\nqvOS action: complete' ]] ||
  fail "three-ring task lost its guarded progress milestones"

HOME="$test_home" \
OMARCHY_PATH="$source_root" \
PATH="$test_bin:$PATH" \
QVOS_TASK_TEST_CAPTURE="$capture" \
  "$root/qv/tui/task/launch" firmware-test
[[ $(<"$capture") == "test-native firmware" ]] ||
  fail "native task lost its interactive owner"

awk -F '|' '
  $1 ~ /^#/ { next }
  NF != 10 { exit 1 }
  seen[$1]++ { exit 1 }
  $4 !~ /^[123]$/ { exit 1 }
  $5 != "tui" && $5 != "native" { exit 1 }
  $6 != "true" && $6 != "false" { exit 1 }
  $7 == "" || $8 == "" || $9 == "" || $10 == "" { exit 1 }
  $5 == "tui" { tui++ }
  $5 == "native" { native++ }
  END { exit !(tui >= 18 && native >= 12) }
' "$root/qv/tui/task/actions.psv" ||
  fail "tracked task catalog schema, uniqueness, or coverage"

awk -F '|' '
  $1 ~ /^#/ { next }
  $1 ~ /^refresh-/ {
    refresh_count++
    if ($4 != "3") {
      invalid = 1
    }
  }
  END { exit !(refresh_count >= 9 && !invalid) }
' "$root/qv/tui/task/actions.psv" ||
  fail "configuration refreshes must retain three-ring confirmation"

while IFS= read -r owner; do
  awk -F '|' -v wanted="$owner" '
    $1 !~ /^#/ && NF == 10 && $10 == wanted { found = 1 }
    END { exit !found }
  ' "$root/qv/tui/task/actions.psv" ||
    fail "concept presentation is not classified: $owner"
done < <(
  awk -F '|' '
    $1 !~ /^#/ {
      for (field = 7; field <= NF; field += 2) {
        if ($field ~ /^present:/) {
          sub(/^present:/, "", $field)
          print $field
        }
      }
    }
  ' "$root/qv/menu/concepts.psv"
)

while IFS= read -r slug; do
  awk -F '|' -v wanted="$slug" '
    $1 !~ /^#/ && NF == 10 && $1 == wanted { found = 1 }
    END { exit !found }
  ' "$root/qv/tui/task/actions.psv" ||
    fail "Elephant task route is not classified: $slug"
done < <(
  sed -n 's/.*task_action("\([^"]*\)").*/\1/p' \
    "$root/qv/menu/elephant/qvos_omarchy_menu.lua" |
    sort -u
)

for slug in \
  font-cascadia-mono \
  font-meslo-mono \
  font-fira-code \
  font-victor-code \
  font-bitstream-vera \
  font-iosevka; do
  awk -F '|' -v wanted="$slug" '
    $1 !~ /^#/ && NF == 11 && $1 == wanted && $6 == "tui" { found = 1 }
    END { exit !found }
  ' "$root/qv/menu/software-installers.psv" ||
    fail "font installer does not use the shared two-ring flow: $slug"
done

printf 'ok - classified qvOS tasks reuse 3, 2, and 1-ring owners without capturing interactive flows\n'
