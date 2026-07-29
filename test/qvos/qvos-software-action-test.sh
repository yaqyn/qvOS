#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_bin="$test_root/bin"
launch_log="$test_root/launch.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/qv/menu" \
  "$source_root/qv/tui/action" \
  "$test_root/home/.local/share/qvos/menu" \
  "$test_bin"
install -m 0755 "$root/qv/menu/software-state" "$source_root/qv/menu/software-state"
install -m 0755 "$root/qv/tui/action/run" "$source_root/qv/tui/action/run"

install -m 0644 /dev/stdin "$source_root/qv/menu/software-actions.psv" <<'CATALOG'
# slug|probe kind|probe value|install presentation|install sudo|uninstall presentation|uninstall sudo|install owner|uninstall owner
demo|file|.demo-installed|tui|true|tui|true|demo-install|demo-uninstall
CATALOG
install -m 0644 /dev/stdin "$test_root/home/.local/share/qvos/menu/concepts.psv" <<'CONCEPTS'
demo|󰏖|Demo|Settings · Software · Test|fixture
CONCEPTS

install -m 0755 /dev/stdin "$test_bin/demo-install" <<'SCRIPT'
#!/bin/bash
# omarchy:summary=Install the Demo fixture
# omarchy:requires-sudo=true
touch "$HOME/.demo-installed"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/demo-uninstall" <<'SCRIPT'
#!/bin/bash
# omarchy:summary=Uninstall the Demo fixture
# omarchy:requires-sudo=true
rm -f "$HOME/.demo-installed"
SCRIPT

run_action() {
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:/usr/bin" \
    QVOS_ACTION_SLUG=demo \
    QVOS_ACTION_OPERATION="$1" \
    "$source_root/qv/tui/action/run" "${@:2}"
}

state=$(
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:/usr/bin" \
    "$source_root/qv/menu/software-state" demo
)
[[ $state == "install" ]] || fail "missing fixture Install state"

run_action install --check
install_output=$(run_action install)
grep -Fqx 'qvOS action: preparing' <<<"$install_output" ||
  fail "action prepare milestone"
grep -Fqx 'qvOS action: applying' <<<"$install_output" ||
  fail "action apply milestone"
grep -Fqx 'qvOS action: verifying' <<<"$install_output" ||
  fail "action verification milestone"
grep -Fqx 'qvOS action: complete' <<<"$install_output" ||
  fail "action completion milestone"
[[ -f $test_root/home/.demo-installed ]] ||
  fail "action delegated to the Install owner"
if run_action install --check >/dev/null 2>&1; then
  fail "stale Install action passed preflight"
fi

run_action uninstall
[[ ! -e $test_root/home/.demo-installed ]] ||
  fail "action delegated to the Uninstall owner"
printf 'ok - software action preflight, owner delegation, and verification\n'

install -m 0755 /dev/stdin "$source_root/qv/tui/launch" <<'SCRIPT'
#!/bin/bash
{
  printf 'args\t%s\n' "$*"
  printf 'slug\t%s\n' "$QVOS_ACTION_SLUG"
  printf 'operation\t%s\n' "$QVOS_ACTION_OPERATION"
  printf 'title\t%s\n' "$QVOS_ACTION_TITLE"
  printf 'summary\t%s\n' "$QVOS_ACTION_SUMMARY"
  printf 'sudo\t%s\n' "$QVOS_ACTION_REQUIRES_SUDO"
} >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT
install -m 0755 "$root/qv/tui/action/launch" "$source_root/qv/tui/action/launch"

HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_LAUNCH_LOG="$launch_log" \
  "$source_root/qv/tui/action/launch" demo

grep -Fqx $'args\tDemo qvos-tui --action' "$launch_log" ||
  fail "shared TUI launch route"
grep -Fqx $'slug\tdemo' "$launch_log" ||
  fail "action slug contract"
grep -Fqx $'operation\tinstall' "$launch_log" ||
  fail "fresh action state at launch"
grep -Fqx $'title\tDemo' "$launch_log" ||
  fail "concept title contract"
grep -Fqx $'summary\tInstall the Demo fixture' "$launch_log" ||
  fail "owner summary contract"
grep -Fqx $'sudo\t1' "$launch_log" ||
  fail "owner sudo contract"
printf 'ok - action launcher derives the shared TUI contract from owners\n'

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
[[ $1 == "-Qq" ]] && exit 0
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/mise" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_MISE_LOG"
if [[ $* == "ls --global" ]]; then
  printf 'go  1.0  fixture\n'
  printf 'node  1.0  fixture\n'
fi
SCRIPT
cat >>"$source_root/qv/menu/software-actions.psv" <<'CATALOG'
go|mise|go|tui|true|tui|true|demo-install|demo-uninstall
node|mise|node|tui|true|tui|true|demo-install|demo-uninstall
CATALOG
mise_log="$test_root/mise.log"
HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_MISE_LOG="$mise_log" \
  "$source_root/qv/menu/software-state" --all >/dev/null
[[ $(wc -l <"$mise_log") == 1 ]] ||
  fail "mise inventory was queried more than once for the software view"
printf 'ok - software state batches shared package-manager inventories\n'

while IFS='|' read -r \
  slug \
  probe_kind \
  probe_value \
  install_presentation \
  install_sudo \
  uninstall_presentation \
  uninstall_sudo \
  install_owner \
  uninstall_owner \
  extra; do
  [[ -n $slug && $slug != "#"* ]] || continue
  [[ -n $probe_kind && -n $probe_value ]] &&
    [[ $install_presentation == "tui" || $install_presentation == "native" ]] &&
    [[ $install_sudo == "true" || $install_sudo == "false" ]] &&
    [[ $uninstall_presentation == "tui" || $uninstall_presentation == "native" ]] &&
    [[ $uninstall_sudo == "true" || $uninstall_sudo == "false" ]] &&
    [[ -n $install_owner && -n $uninstall_owner && -z ${extra:-} ]] ||
    fail "invalid production action catalog entry: $slug"
  [[ $(awk -F '|' -v wanted="$slug" '$1 == wanted { count++ } END { print count + 0 }' \
    "$root/qv/menu/concepts.psv") == 1 ]] ||
    fail "software action concept mismatch: $slug"
done <"$root/qv/menu/software-actions.psv"

if rg -Fq '|Learn|' "$root/qv/menu/concepts.psv"; then
  fail "per-app Learn action remains"
fi
printf 'ok - production software action catalog is unique and Learn-free\n'
