#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
capture="$test_root/capture"
owner_log="$test_root/owner.log"

# Exercise the explicit compatibility root without inheriting a live source.
unset QVOS_PATH

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/bin" \
  "$source_root/qvcore/tui/task/presenters" \
  "$source_root/qvcore/tui" \
  "$test_home/.local/lib/qvos/tui/task" \
  "$test_bin"
install -m 0755 "$root/qvcore/tui/task/launch" "$source_root/qvcore/tui/task/launch"
install -m 0755 "$root/qvcore/tui/task/run" "$source_root/qvcore/tui/task/run"
install -m 0755 "$root/qvcore/tui/selection-owner" "$source_root/qvcore/tui/selection-owner"
install -m 0755 "$root/qvcore/tui/owner-resolver" "$source_root/qvcore/tui/owner-resolver"
install -m 0644 /dev/stdin "$source_root/qvcore/tui/task/actions.psv" <<'CATALOG'
# slug|title|summary|rings|behavior|presentation|requires_sudo|primary|active|complete|owner
information-test|Test State|Inspect a test state|1|information|tui|false||||test-owner inspect
presented-test|Presented State|Read back a silent owner|1|information|tui|false||||test-owner presented
mutation-test|Test Config|Restore a test config|1|mutation|tui|false|Restore|Restoring|Restored|test-owner apply
critical-test|Critical Config|Restore a critical config|3|mutation|tui|true|Restore|Restoring|Restored|test-owner critical
firmware-test|Firmware|Retain native firmware prompts|3|mutation|native|true|Update|Updating|Updated|test-native firmware
selection-test|Selectable Config|Choose fixtures to remove|2|mutation|tui|false|Remove|Removing|Removed|qvcore/tui/task/fixture-selection-owner
CATALOG
install -m 0644 /dev/stdin "$source_root/qvcore/tui/task/selections.psv" <<'SELECTIONS'
# slug|title|mode|empty message
selection-test|Select Fixtures|multi|No fixtures are installed.
SELECTIONS
install -m 0644 /dev/stdin "$source_root/qvcore/tui/success-guidance.psv" <<'GUIDANCE'
# slug|operation|next step
mutation-test|task|Open the restored fixture to continue.
GUIDANCE
install -m 0755 /dev/stdin "$source_root/qvcore/tui/task/presenters/presented-test" <<'PRESENTER'
#!/bin/bash
"$@"
printf 'Verified state: ready\n'
PRESENTER
install -m 0755 /dev/stdin "$source_root/qvcore/tui/launch" <<'LAUNCH'
#!/bin/bash
{
  printf '%s\n' "$*"
  printf '%s\n' "$QVOS_ACTION_SLUG"
  printf '%s\n' "$QVOS_ACTION_OPERATION"
  printf '%s\n' "$QVOS_ACTION_RINGS"
  printf '%s\n' "$QVOS_ACTION_BEHAVIOR"
  printf '%s\n' "$QVOS_ACTION_PRIMARY"
  printf '%s\n' "$QVOS_ACTION_ACTIVE"
  printf '%s\n' "$QVOS_ACTION_COMPLETE"
  printf '%s\n' "$QVOS_ACTION_REQUIRES_SUDO"
  printf '%s\n' "$QVOS_ACTION_SCRIPT"
  printf '%s\n' "${QVOS_ACTION_SELECTION_MODE:-}"
  printf '%s\n' "${QVOS_ACTION_SELECTION_TITLE:-}"
  printf '%s\n' "${QVOS_ACTION_SELECTION_EMPTY:-}"
  printf '%s\n' "${QVOS_ACTION_NEXT_STEP:-}"
} >"$QVOS_TASK_TEST_CAPTURE"
LAUNCH
install -m 0755 /dev/stdin "$source_root/bin/test-owner" <<'OWNER'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TASK_TEST_OWNER_LOG"
printf 'Owner result: %s\n' "$*"
OWNER
install -m 0755 /dev/stdin "$test_bin/test-owner" <<'OWNER'
#!/bin/bash
echo "stale installed owner was used" >&2
exit 77
OWNER
install -m 0755 /dev/stdin "$test_bin/readback-owner" <<'OWNER'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TASK_TEST_OWNER_LOG"
printf 'Owner result: %s\n' "$*"
OWNER
install -m 0755 /dev/stdin "$source_root/qvcore/tui/task/fixture-selection-owner" <<'OWNER'
#!/bin/bash
case ${1:-} in
--list)
  printf 'Alpha\nBeta\nGamma\n'
  ;;
--)
  shift
  printf 'selected:%s\n' "$*" >>"$QVOS_TASK_TEST_OWNER_LOG"
  ;;
*)
  exit 2
  ;;
esac
OWNER
install -m 0755 /dev/stdin "$test_home/.local/lib/qvos/tui/task/fixture-selection-owner" <<'OWNER'
#!/bin/bash
echo "stale installed qvOS owner was used" >&2
exit 77
OWNER
install -m 0755 /dev/stdin "$test_bin/qv-launch-floating-terminal-with-presentation" <<'NATIVE'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TASK_TEST_CAPTURE"
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
  "$source_root/qvcore/tui/task/launch" information-test

[[ $(sed -n '1p' "$capture") == "Test State qvos-tui --action" ]] ||
  fail "task launcher did not reuse the shared qvOS action mode"
[[ $(sed -n '2,10p' "$capture") == $'information-test\ntask\n1\ninformation\n\n\n\n0\n'"$source_root/qvcore/tui/task/run" ]] ||
  fail "task launcher lost its classified TUI contract"
[[ -z $(sed -n '14p' "$capture") ]] ||
  fail "information task received irrelevant success guidance"

HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_TASK_TEST_CAPTURE="$capture" \
  "$source_root/qvcore/tui/task/launch" mutation-test
[[ $(sed -n '14p' "$capture") == "Open the restored fixture to continue." ]] ||
  fail "mutation task lost its optional success guidance"

HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_ACTION_SLUG=information-test \
  QVOS_ACTION_OPERATION=task \
  QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
  "$source_root/qvcore/tui/task/run" --check

task_output=$(
  HOME="$test_home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:$PATH" \
    QVOS_ACTION_SLUG=information-test \
    QVOS_ACTION_OPERATION=task \
    QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
    "$source_root/qvcore/tui/task/run"
)
[[ $task_output == "Owner result: inspect" ]] ||
  fail "information task hid its owner output behind synthetic milestones"
[[ $(wc -l <"$owner_log") == 1 && $(<"$owner_log") == "inspect" ]] ||
  fail "information task runner did not delegate exactly once"
[[ $(
  HOME="$test_home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:$PATH" \
    QVOS_ACTION_SLUG=mutation-test \
    QVOS_ACTION_OPERATION=task \
    "$source_root/qvcore/tui/task/run" --cancel-status
) == "unknown" ]] ||
  fail "task cancellation invented a final-state probe"
[[ $(wc -l <"$owner_log") == 1 ]] ||
  fail "task cancellation status delegated to the mutation owner"

mutation_output=$(
  HOME="$test_home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:$PATH" \
    QVOS_ACTION_SLUG=mutation-test \
    QVOS_ACTION_OPERATION=task \
    QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
    "$source_root/qvcore/tui/task/run"
)
[[ $mutation_output == $'qvOS action: preparing\nqvOS action: applying\nOwner result: apply\nqvOS action: complete' ]] ||
  fail "one-ring mutation lost its transaction milestones"
[[ $(wc -l <"$owner_log") == 2 && $(tail -n 1 "$owner_log") == "apply" ]] ||
  fail "one-ring mutation did not delegate exactly once"

presented_output=$(
  HOME="$test_home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:$PATH" \
    QVOS_ACTION_SLUG=presented-test \
    QVOS_ACTION_OPERATION=task \
    QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
    "$source_root/qvcore/tui/task/run"
)
[[ $presented_output == $'Owner result: presented\nVerified state: ready' ]] ||
  fail "information presenter did not replace vague output with verified state"
[[ $(wc -l <"$owner_log") == 3 && $(tail -n 1 "$owner_log") == "presented" ]] ||
  fail "information presenter did not delegate exactly once"

selection_options=$(
  HOME="$test_home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:$PATH" \
    QVOS_ACTION_SLUG=selection-test \
    QVOS_ACTION_OPERATION=task \
    "$source_root/qvcore/tui/task/run" --options
)
[[ $selection_options == $'Alpha\nBeta\nGamma' ]] ||
  fail "task selection options did not come from the owner"
HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_ACTION_SLUG=selection-test \
  QVOS_ACTION_OPERATION=task \
  QVOS_ACTION_SELECTIONS=$'Beta\nGamma' \
  QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
  "$source_root/qvcore/tui/task/run" >/dev/null
[[ $(tail -n 1 "$owner_log") == "selected:Beta Gamma" ]] ||
  fail "task runner did not validate and delegate selected owner arguments"
if HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_ACTION_SLUG=selection-test \
  QVOS_ACTION_OPERATION=task \
  QVOS_ACTION_SELECTIONS="Unknown" \
  QVOS_TASK_TEST_OWNER_LOG="$owner_log" \
  "$source_root/qvcore/tui/task/run" >/dev/null 2>&1; then
  fail "task runner accepted a choice outside the owner inventory"
fi

readback_owner_log="$test_root/readback-owner.log"
readback_output=$(
  PATH="$test_bin:$PATH" \
    QVOS_TASK_TEST_OWNER_LOG="$readback_owner_log" \
    "$root/qvcore/tui/task/presenters/time-sync" readback-owner time-sync
)
[[ $readback_output == $'Status: Synchronized\nService: Active\nNetwork time: Enabled\nTimezone: Africa/Cairo' ]] ||
  fail "System Time presenter did not replace activity copy with verified readback"
[[ $(wc -l <"$readback_owner_log") == 1 && $(<"$readback_owner_log") == "time-sync" ]] ||
  fail "System Time presenter did not delegate exactly once"

set +e
failure_output=$(
  "$root/qvcore/tui/task/presenters/time-sync" \
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
    "$source_root/qvcore/tui/task/run"
)
[[ $critical_output == $'qvOS action: preparing\nqvOS action: applying\nOwner result: critical\nqvOS action: complete' ]] ||
  fail "three-ring task lost its guarded progress milestones"

HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_TASK_TEST_CAPTURE="$capture" \
  "$source_root/qvcore/tui/task/launch" firmware-test
[[ $(<"$capture") == $'test-native\nfirmware' ]] ||
  fail "native task lost its owner argument boundaries"

HOME="$test_home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:$PATH" \
  QVOS_TASK_TEST_CAPTURE="$capture" \
  "$source_root/qvcore/tui/task/launch" selection-test
[[ $(sed -n '11,13p' "$capture") == $'multi\nSelect Fixtures\nNo fixtures are installed.' ]] ||
  fail "task launcher lost its searchable selection contract"

awk -F '|' '
  $1 ~ /^#/ { next }
  NF != 11 { exit 1 }
  seen[$1]++ { exit 1 }
  $4 !~ /^[123]$/ { exit 1 }
  $5 != "information" && $5 != "mutation" { exit 1 }
  $6 != "tui" && $6 != "native" { exit 1 }
  $7 != "true" && $7 != "false" { exit 1 }
  $11 == "" { exit 1 }
  $5 == "information" && ($8 != "" || $9 != "" || $10 != "") { exit 1 }
  $5 == "mutation" && ($8 == "" || $9 == "" || $10 == "") { exit 1 }
  $6 == "tui" { tui++ }
  $6 == "native" { native++ }
  END { exit !(tui >= 18 && native >= 12) }
' "$root/qvcore/tui/task/actions.psv" ||
  fail "tracked task catalog schema, uniqueness, or coverage"

awk -F '|' '
  $1 ~ /^#/ { next }
  NF != 4 { exit 1 }
  seen[$1]++ { exit 1 }
  $2 == "" || $4 == "" { exit 1 }
  $3 != "single" && $3 != "multi" { exit 1 }
  END { exit !(seen["theme-remove"] && seen["webapp-remove"] &&
    seen["tui-remove"] && seen["timezone"]) }
' "$root/qvcore/tui/task/selections.psv" ||
  fail "tracked task selection schema or searchable conversion coverage"

while IFS='|' read -r slug _ _ _; do
  [[ -n $slug && $slug != "#"* ]] || continue
  awk -F '|' -v wanted="$slug" '
    $1 == wanted && $6 == "tui" { found = 1 }
    END { exit !found }
  ' "$root/qvcore/tui/task/actions.psv" ||
    fail "task selection does not resolve to a TUI action: $slug"
done <"$root/qvcore/tui/task/selections.psv"

awk -F '|' '
  $1 ~ /^#/ { next }
  $1 == "battery-status" || $1 == "battery-report" {
    information++
    if ($5 != "information") {
      invalid = 1
    }
    next
  }
  $1 == "theme-update" || $1 == "time-sync" || $1 ~ /^restart-/ {
    mutations++
    if ($5 != "mutation") {
      invalid = 1
    }
  }
  END { exit !(information == 2 && mutations >= 11 && !invalid) }
' "$root/qvcore/tui/task/actions.psv" ||
  fail "task behavior must describe effects independently from ring role"

awk -F '|' '
  $1 ~ /^#/ { next }
  $1 ~ /^refresh-/ {
    refresh_count++
    if ($4 != "3") {
      invalid = 1
    }
  }
  END { exit !(refresh_count >= 9 && !invalid) }
' "$root/qvcore/tui/task/actions.psv" ||
  fail "configuration refreshes must retain three-ring classification"

while IFS= read -r owner; do
  awk -F '|' -v wanted="$owner" '
    $1 !~ /^#/ && NF == 11 && $11 == wanted { found = 1 }
    END { exit !found }
  ' "$root/qvcore/tui/task/actions.psv" ||
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
  ' "$root/qvcore/menu/concepts.psv"
)

while IFS= read -r slug; do
  awk -F '|' -v wanted="$slug" '
    $1 !~ /^#/ && NF == 11 && $1 == wanted { found = 1 }
    END { exit !found }
  ' "$root/qvcore/tui/task/actions.psv" ||
    fail "Elephant task route is not classified: $slug"
done < <(
  sed -n 's/.*task_action("\([^"]*\)").*/\1/p' \
    "$root/qvcore/menu/elephant/qvos_menu.lua" |
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
  ' "$root/qvcore/menu/software-installers.psv" ||
    fail "font installer does not use the shared two-ring flow: $slug"
done

printf 'ok - classified qvOS tasks keep ring presentation separate from information and mutation behavior\n'
