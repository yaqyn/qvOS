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
  "$source_root/bin" \
  "$source_root/qv/menu" \
  "$source_root/qv/tui/action" \
  "$test_root/home/.local/share/qvos/menu" \
  "$test_bin"
install -m 0755 "$root/qv/menu/software-state" "$source_root/qv/menu/software-state"
install -m 0755 "$root/qv/menu/software-installer-state" "$source_root/qv/menu/software-installer-state"
install -m 0755 "$root/qv/tui/action/run" "$source_root/qv/tui/action/run"
install -m 0755 "$root/qv/tui/action/post-run" "$source_root/qv/tui/action/post-run"
install -m 0755 "$root/qv/tui/action/run-installer" "$source_root/qv/tui/action/run-installer"
install -m 0755 "$root/qv/tui/action/rollback-owner" "$source_root/qv/tui/action/rollback-owner"
install -m 0755 "$root/qv/tui/selection-owner" "$source_root/qv/tui/selection-owner"
install -m 0755 "$root/qv/tui/owner-resolver" "$source_root/qv/tui/owner-resolver"
install -m 0644 /dev/stdin "$source_root/qv/tui/action/choices.psv" <<'CHOICES'
# slug|operation|title|mode|empty message|summary choice|choice summary|choice sudo
CHOICES
install -m 0644 /dev/stdin "$source_root/qv/tui/action/forms.psv" <<'FORMS'
# slug|operation|protocol
demo|install|owner-json-v1
FORMS
install -m 0644 /dev/stdin "$source_root/qv/tui/action/post-actions.psv" <<'POST_ACTIONS'
# slug|operation|label|protocol
demo|install|launch|owner-v1
POST_ACTIONS
install -m 0644 /dev/stdin "$source_root/qv/tui/action/rollbacks.psv" <<'ROLLBACKS'
# slug|operation|protocol
ROLLBACKS

install -m 0644 /dev/stdin "$source_root/qv/menu/software-actions.psv" <<'CATALOG'
# slug|probe kind|probe value|install presentation|install sudo|uninstall presentation|uninstall sudo|install owner|uninstall owner
demo|file|.demo-installed|tui|true|tui|true|demo-install|demo-uninstall
CATALOG
install -m 0644 /dev/stdin "$source_root/qv/menu/software-installers.psv" <<'CATALOG'
# slug|icon|name|breadcrumb|keywords|presentation|sudo|probe kind|probe value|summary|owner
demo-installer|󰏖|Demo Installer|Settings · Software · Test|fixture|tui|true|file-lines|.demo-installer-installed enabled=true verified=true|Install the Demo installer fixture|demo-installer-install
native-installer|󰏖|Native Installer|Settings · Software · Test|fixture|native|false|none|-|Run the native installer fixture|test-native install
CATALOG
install -m 0644 /dev/stdin "$source_root/qv/tui/success-guidance.psv" <<'GUIDANCE'
# slug|operation|next step
demo|install|Open the Demo fixture to continue.
demo-installer|install|Open Demo Installer to continue.
GUIDANCE
install -m 0644 /dev/stdin "$test_root/home/.local/share/qvos/menu/concepts.psv" <<'CONCEPTS'
demo|󰏖|Demo|Settings · Software · Test|fixture
CONCEPTS

install -m 0755 /dev/stdin "$source_root/bin/demo-install" <<'SCRIPT'
#!/bin/bash
# omarchy:summary=Install the Demo fixture
# omarchy:requires-sudo=true
if [[ ${1:-} == "--qvos-post-success" ]]; then
  printf 'Windows image download visible\n'
  printf 'opened\n' >"$QVOS_TEST_POST_ACTION"
  exit
fi
case ${1:-} in
--qvos-post-success-rollback-check)
  exit
  ;;
--qvos-post-success-rollback-snapshot)
  install -d -m 0700 "$2"
  printf 'snapshot\n' >"$2/state"
  exit
  ;;
--qvos-post-success-rollback-seal)
  printf 'sealed\n' >"$2/sealed"
  exit
  ;;
--qvos-post-success-rollback-restore)
  [[ -f $2/state ]] || exit 1
  [[ ! -e $QVOS_TEST_POST_ACTION ]] || unlink "$QVOS_TEST_POST_ACTION"
  exit
  ;;
--qvos-post-success-cancel-status)
  [[ -d $2 ]] || exit 1
  if [[ -e $QVOS_TEST_POST_ACTION ]]; then
    printf 'target-reached\n'
  else
    printf 'target-not-detected\n'
  fi
  exit
  ;;
esac
touch "$HOME/.demo-installed"
SCRIPT
install -m 0755 /dev/stdin "$source_root/bin/demo-uninstall" <<'SCRIPT'
#!/bin/bash
# omarchy:summary=Uninstall the Demo fixture
# omarchy:requires-sudo=true
rm -f "$HOME/.demo-installed"
SCRIPT
install -m 0755 /dev/stdin "$source_root/bin/demo-installer-install" <<'SCRIPT'
#!/bin/bash
printf 'enabled=true\nverified=true\n' >"$HOME/.demo-installer-installed"
SCRIPT
for owner in demo-install demo-uninstall demo-installer-install; do
  install -m 0755 /dev/stdin "$test_bin/$owner" <<'SCRIPT'
#!/bin/bash
echo "stale installed owner was used" >&2
exit 77
SCRIPT
done

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

[[ $(run_action install --cancel-status) == "target-not-detected" ]] ||
  fail "absent software cancellation state"
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
[[ $(run_action install --cancel-status) == "target-reached" ]] ||
  fail "completed software cancellation state"
post_action_log="$test_root/post-action.log"
post_rollback_state="$test_root/post-rollback"
printf 'demo|install|owner-state-v1\n' >>"$source_root/qv/tui/action/rollbacks.psv"
post_output=$(HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_ACTION_SLUG=demo \
  QVOS_ACTION_OPERATION=install \
  QVOS_ACTION_SCRIPT="$source_root/qv/tui/action/run" \
  QVOS_ACTION_POST_SUCCESS=owner-v1 \
  QVOS_ACTION_ROLLBACK=owner-state-v1 \
  QVOS_ACTION_ROLLBACK_STATE="$post_rollback_state" \
  QVOS_TEST_POST_ACTION="$post_action_log" \
  "$source_root/qv/tui/action/post-run")
[[ $(<"$post_action_log") == "opened" ]] ||
  fail "verified install post-success owner"
grep -Fq 'Windows image download visible' <<<"$post_output" ||
  fail "post-success owner output was hidden"
HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_ACTION_SLUG=demo \
  QVOS_ACTION_OPERATION=install \
  QVOS_ACTION_SCRIPT="$source_root/qv/tui/action/run" \
  QVOS_ACTION_POST_SUCCESS=owner-v1 \
  QVOS_ACTION_ROLLBACK=owner-state-v1 \
  QVOS_ACTION_ROLLBACK_STATE="$post_rollback_state" \
  QVOS_TEST_POST_ACTION="$post_action_log" \
  "$source_root/qv/tui/action/post-run" --rollback
[[ ! -e $post_action_log ]] || fail "post-success Stop retained its owner result"
printf 'ok - post-success work reuses the visible action stream and exact Stop owner\n'
if stale_output=$(QVOS_ACTION_ROLLBACK=owner-state-v1 run_action install --check 2>&1); then
  fail "stale Install action passed preflight"
fi
grep -Fq 'already installed' <<<"$stale_output" ||
  fail "stale Install action leaked its next-action token"

run_action uninstall
[[ ! -e $test_root/home/.demo-installed ]] ||
  fail "action delegated to the Uninstall owner"
printf 'ok - software action preflight, owner delegation, and verification\n'

HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_ACTION_SLUG=demo-installer \
  QVOS_ACTION_OPERATION=install \
  "$source_root/qv/tui/action/run-installer" --check
[[ $(
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:/usr/bin" \
    QVOS_ACTION_SLUG=demo-installer \
    QVOS_ACTION_OPERATION=install \
    "$source_root/qv/tui/action/run-installer" --cancel-status
) == "target-not-detected" ]] ||
  fail "absent install-only cancellation state"
installer_output=$(
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:/usr/bin" \
    QVOS_ACTION_SLUG=demo-installer \
    QVOS_ACTION_OPERATION=install \
    "$source_root/qv/tui/action/run-installer"
)
grep -Fqx 'qvOS action: complete' <<<"$installer_output" ||
  fail "install-only action completion milestone"
[[ -f $test_root/home/.demo-installer-installed ]] ||
  fail "install-only action delegated to its owner"
[[ $(
  HOME="$test_root/home" \
    OMARCHY_PATH="$source_root" \
    PATH="$test_bin:/usr/bin" \
    QVOS_ACTION_SLUG=demo-installer \
    QVOS_ACTION_OPERATION=install \
    "$source_root/qv/tui/action/run-installer" --cancel-status
) == "target-reached" ]] ||
  fail "completed install-only cancellation state"
HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  "$source_root/qv/menu/software-installer-state" demo-installer >/dev/null ||
  fail "install-only action real-result probe"
printf 'ok - install-only software uses the shared verified action stream\n'

printf 'demo-installer|install|owner-state-v1\n' >>"$source_root/qv/tui/action/rollbacks.psv"

install -m 0755 /dev/stdin "$source_root/qv/tui/launch" <<'SCRIPT'
#!/bin/bash
{
  printf 'args\t%s\n' "$*"
  printf 'slug\t%s\n' "$QVOS_ACTION_SLUG"
  printf 'operation\t%s\n' "$QVOS_ACTION_OPERATION"
  printf 'title\t%s\n' "$QVOS_ACTION_TITLE"
  printf 'summary\t%s\n' "$QVOS_ACTION_SUMMARY"
  printf 'sudo\t%s\n' "$QVOS_ACTION_REQUIRES_SUDO"
  printf 'script\t%s\n' "${QVOS_ACTION_SCRIPT:-}"
  printf 'next\t%s\n' "${QVOS_ACTION_NEXT_STEP:-}"
  printf 'rollback\t%s\n' "${QVOS_ACTION_ROLLBACK:-}"
  printf 'selection-mode\t%s\n' "${QVOS_ACTION_SELECTION_MODE:-}"
  printf 'selection-title\t%s\n' "${QVOS_ACTION_SELECTION_TITLE:-}"
  printf 'summary-selection\t%s\n' "${QVOS_ACTION_SUMMARY_SELECTION:-}"
  printf 'selection-summary\t%s\n' "${QVOS_ACTION_SELECTION_SUMMARY:-}"
  printf 'selection-sudo\t%s\n' "${QVOS_ACTION_SELECTION_REQUIRES_SUDO:-}"
  printf 'form\t%s\n' "${QVOS_ACTION_FORM:-}"
  printf 'primary\t%s\n' "${QVOS_ACTION_PRIMARY:-}"
  printf 'active\t%s\n' "${QVOS_ACTION_ACTIVE:-}"
  printf 'complete\t%s\n' "${QVOS_ACTION_COMPLETE:-}"
  printf 'owner-script\t%s\n' "${QVOS_ACTION_OWNER_SCRIPT:-}"
  printf 'post-label\t%s\n' "${QVOS_ACTION_POST_LABEL:-}"
  printf 'post-action\t%s\n' "${QVOS_ACTION_POST_SUCCESS:-}"
  printf 'post-resume\t%s\n' "${QVOS_ACTION_POST_RESUME:-}"
} >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT
install -m 0755 "$root/qv/tui/action/launch" "$source_root/qv/tui/action/launch"
install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT

HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_LAUNCH_LOG="$launch_log" \
  "$source_root/qv/tui/action/launch" --installer native-installer
[[ $(<"$launch_log") == $'test-native\ninstall' ]] ||
  fail "native software action lost its owner argument boundaries"
printf 'ok - native software actions preserve executable argument boundaries\n'

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
grep -Fqx $'next\tOpen the Demo fixture to continue.' "$launch_log" ||
  fail "state-aware success guidance contract"
grep -Fqx $'form\towner-json-v1' "$launch_log" ||
  fail "state-aware owner-form contract"
grep -Fqx $'post-label\tlaunch' "$launch_log" ||
  fail "state-aware post-success label contract"
grep -Fqx $'post-action\towner-v1' "$launch_log" ||
  fail "state-aware post-success owner contract"
printf 'ok - action launcher derives the shared TUI contract from owners\n'

touch "$test_root/home/.demo-installed"
HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_LAUNCH_LOG="$launch_log" \
  "$source_root/qv/tui/action/launch" --post-success demo
grep -Fqx $'operation\tinstall' "$launch_log" ||
  fail "post-success resume operation contract"
grep -Fqx $'summary\tInstall the Demo fixture' "$launch_log" ||
  fail "post-success resume retained no valid base action summary"
grep -Fqx $'sudo\t0' "$launch_log" ||
  fail "post-success resume unexpectedly requested installation authorization"
grep -Fqx $'post-label\tlaunch' "$launch_log" ||
  fail "post-success resume label contract"
grep -Fqx $'post-action\towner-v1' "$launch_log" ||
  fail "post-success resume owner contract"
grep -Fqx $'post-resume\t1' "$launch_log" ||
  fail "post-success resume shared-copy contract"
grep -Fqx $'script\t'"$source_root"$'/qv/tui/action/post-run' "$launch_log" ||
  fail "post-success resume shared runner"
grep -Fqx $'owner-script\t'"$source_root"$'/qv/tui/action/run' "$launch_log" ||
  fail "post-success resume owner runner"
rm -f "$test_root/home/.demo-installed"
printf 'ok - interrupted completion work resumes as its own truthful TUI action\n'

touch "$test_root/home/.demo-installed"
cat >>"$source_root/qv/tui/action/choices.psv" <<'CHOICES'
demo|uninstall|Remove Demo|action|No Demo removal choices are available.|Remove Demo Data|Remove the Demo fixture and its data|true
CHOICES
HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_LAUNCH_LOG="$launch_log" \
  "$source_root/qv/tui/action/launch" demo

grep -Fqx $'operation\tuninstall' "$launch_log" ||
  fail "scoped action fresh state"
grep -Fqx $'selection-mode\taction' "$launch_log" ||
  fail "scoped action selection mode"
grep -Fqx $'selection-title\tRemove Demo' "$launch_log" ||
  fail "scoped action selection title"
grep -Fqx $'summary-selection\tRemove Demo Data' "$launch_log" ||
  fail "scoped action destructive branch"
grep -Fqx $'selection-summary\tRemove the Demo fixture and its data' "$launch_log" ||
  fail "scoped action authorization copy"
grep -Fqx $'selection-sudo\t1' "$launch_log" ||
  fail "scoped action authorization requirement"
rm -f "$test_root/home/.demo-installed"
printf 'ok - destructive scope is chosen inside the TUI before authorization\n'

mv "$source_root/qv/menu/software-state" "$source_root/qv/menu/software-state.disabled"
HOME="$test_root/home" \
  OMARCHY_PATH="$source_root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_LAUNCH_LOG="$launch_log" \
  "$source_root/qv/tui/action/launch" --installer demo-installer
mv "$source_root/qv/menu/software-state.disabled" "$source_root/qv/menu/software-state"

grep -Fqx $'args\tDemo Installer qvos-tui --action' "$launch_log" ||
  fail "install-only shared TUI launch route"
grep -Fqx $'slug\tdemo-installer' "$launch_log" ||
  fail "install-only action slug contract"
grep -Fqx $'operation\tinstall' "$launch_log" ||
  fail "install-only operation contract"
grep -Fqx $'title\tDemo Installer' "$launch_log" ||
  fail "install-only title contract"
grep -Fqx $'summary\tInstall the Demo installer fixture' "$launch_log" ||
  fail "install-only summary contract"
grep -Fqx $'sudo\t1' "$launch_log" ||
  fail "install-only sudo contract"
grep -Fqx $'script\t'"$source_root"$'/qv/tui/action/run-installer' "$launch_log" ||
  fail "install-only verified runner contract"
grep -Fqx $'next\tOpen Demo Installer to continue.' "$launch_log" ||
  fail "install-only success guidance contract"
grep -Fqx $'rollback\towner-state-v1' "$launch_log" ||
  fail "install-only exact rollback contract"
printf 'ok - install-only launcher reuses the shared two-ring TUI without stateful owners\n'

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
go|mise|go|tui|true|tui|true|qv/menu/demo-install|demo-uninstall
node|mise|node|tui|true|tui|true|qv/menu/demo-install|demo-uninstall
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

tui_installers=""
native_installers=""
while IFS='|' read -r \
  slug \
  icon \
  name \
  breadcrumb \
  keywords \
  presentation \
  requires_sudo \
  probe_kind \
  probe_value \
  summary \
  owner \
  extra; do
  [[ -n $slug && $slug != "#"* ]] || continue
  [[ -n $icon && -n $name ]] &&
    { [[ $breadcrumb == "Settings · Software ·"* ]] ||
      [[ $breadcrumb == "Settings · Appearance · Font" ]]; } &&
    [[ -n $keywords ]] &&
    [[ $presentation == "tui" || $presentation == "native" ]] &&
    [[ $requires_sudo == "true" || $requires_sudo == "false" ]] &&
    [[ -n $probe_kind && -n $probe_value && -n $summary && -n $owner ]] &&
    [[ -z ${extra:-} ]] ||
    fail "invalid software installer entry: $slug"
  if [[ $presentation == "tui" ]]; then
    [[ $probe_kind != "none" ]] ||
      fail "TUI installer lacks a real result probe: $slug"
    tui_installers+="${tui_installers:+ }$slug"
  else
    native_installers+="${native_installers:+ }$slug"
  fi
done <"$root/qv/menu/software-installers.psv"

rollback_installers=""
while IFS='|' read -r slug operation protocol extra; do
  [[ -n $slug && $slug != "#"* ]] || continue
  [[ $operation == "install" ]] &&
    [[ $protocol == "owner-state-v1" && -z ${extra:-} ]] ||
    fail "invalid action rollback contract: $slug"
  installer_matches=$(awk -F '|' -v wanted="$slug" '
    $1 == wanted && $6 == "tui" { count++ }
    END { print count + 0 }
  ' "$root/qv/menu/software-installers.psv")
  action_matches=$(awk -F '|' -v wanted="$slug" '
    $1 == wanted && $4 == "tui" { count++ }
    END { print count + 0 }
  ' "$root/qv/menu/software-actions.psv")
  ((installer_matches + action_matches == 1)) ||
    fail "rollback contract has no captured installer owner: $slug"
  rollback_installers+="${rollback_installers:+ }$slug"
done <"$root/qv/tui/action/rollbacks.psv"

[[ $tui_installers == "dropbox nordvpn bitwarden chromium-account vscode cursor zed sublime-text helix vim emacs font-cascadia-mono font-meslo-mono font-fira-code font-victor-code font-bitstream-vera font-iosevka alacritty foot ghostty kitty lm-studio ollama crush" ]] ||
  fail "complete captured-stream software installer sweep"
[[ $native_installers == "tailscale once docker-db" ]] ||
  fail "interactive software installer native-terminal boundary"
[[ $rollback_installers == "font-cascadia-mono font-meslo-mono font-fira-code font-victor-code font-bitstream-vera font-iosevka alacritty foot ghostty kitty windows" ]] ||
  fail "reviewed exact installer rollback sweep"
if awk -F '|' '
  FNR == NR {
    if ($1 !~ /^#/ && $1 != "") seen[$1] = 1
    next
  }
  $1 !~ /^#/ && $1 != "" && seen[$1] { found = 1 }
  END { exit found ? 0 : 1 }
' "$root/qv/menu/software-actions.psv" "$root/qv/menu/software-installers.psv"; then
  fail "state-aware and install-only software catalogs overlap"
fi
if rg -Fq '"Sublime Text", "Settings · Software' \
  "$root/qv/menu/elephant/qvos_menu.lua"; then
  fail "Sublime Text bypasses the audited software installer registry"
fi
printf 'ok - every remaining Software installer has an explicit TUI or native contract\n'

fallback_sublime_route=$(
  HOME="$test_root/home" OMARCHY_PATH="$root" bash -s -- \
    "$root/qv/menu/extension.sh" <<'SCRIPT'
set -euo pipefail
source "$1"

menu() {
  printf '  Sublime Text\n'
}

launch_software_installer() {
  printf '%s\n' "$1"
}

show_install_editor_menu
SCRIPT
)
[[ $fallback_sublime_route == "sublime-text" ]] ||
  fail "fallback Editor selector shared TUI route"
printf 'ok - Sublime Text uses the same installer route from every menu surface\n'

fallback_stateful_routes=$(
  bash -s -- "$root/qv/menu/extension.sh" <<'SCRIPT'
set -euo pipefail
source "$1"

show_software_menu() {
  printf '%s\n' "$1"
}

show_install_development_menu
show_install_browser_menu
show_install_gaming_menu
show_remove_development_menu
show_remove_browser_menu
show_remove_gaming_menu
SCRIPT
)
[[ $fallback_stateful_routes == $'development\nbrowser\ngaming\ndevelopment\nbrowser\ngaming' ]] ||
  fail "fallback state-aware Software routes"
if rg -q 'present_terminal omarchy-(install|remove)-(browser|dev-env|gaming)' \
  "$root/qv/menu/extension.sh"; then
  fail "fallback state-aware owner bypasses the shared action route"
fi
printf 'ok - legacy Install and Remove surfaces converge on state-aware Software\n'
