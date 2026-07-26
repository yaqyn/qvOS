#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
component="$root/qv/core/proton.sh"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
test_state="$test_root/.qvos-test-proton"
action_log="$test_root/actions"
pass_fixture="$test_root/pass-cli"
drive_fixture="$test_root/proton-drive"
skill_source="$root/qv/core/proton/skill"
installed_skill="$test_root/.codex/skills/proton-cli"
codex_pass_root="$test_root/.local/share/qvos-codex/proton-pass"
proton_hook_fixture="$test_root/qvos-proton-on-demand.hook"
thunar_config="$test_root/.config/Thunar/uca.xml"
upload_helper="$test_root/.local/share/qvos/thunar/proton-drive-upload"
desktop_hook="$test_root/.config/omarchy/hooks/post-update.d/qvos-qvcore-proton"
desktop_state="$test_root/.local/state/qvos/qvcore/proton"

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

assert_log() {
  grep -Fqx "$1" "$action_log" || fail "$2"
}

install -d "$test_bin" "$test_root/tmp"

install -m 0755 /dev/stdin "$test_bin/cmp" <<'SCRIPT'
#!/bin/bash
if [[ $* == "-s /etc/pacman.d/hooks/qvos-proton-on-demand.hook -" ]]; then
  [[ -f $QVOS_TEST_PROTON_HOOK_FIXTURE ]] || exit 1
  exec /usr/bin/cmp -s "$QVOS_TEST_PROTON_HOOK_FIXTURE" -
fi
exec /usr/bin/cmp "$@"
SCRIPT

install -m 0755 /dev/stdin "$pass_fixture" <<'PASS'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} == "--version" ]]; then
  printf 'Proton Pass CLI test\n'
  exit
fi

state_root="$HOME/.qvos-test-proton"
session_file="$XDG_DATA_HOME/session"
codex_data="$HOME/.local/share/qvos-codex/proton-pass/data"
fixture_pat="pst_""fixture::fixture-key"
install -d -m 0700 "$state_root"
printf 'pass-cli\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"

is_codex=0
if [[ $XDG_DATA_HOME == "$codex_data" ]]; then
  is_codex=1
fi

case ${1:-} in
info | test)
  [[ -f $session_file ]]
  if [[ $1 == "info" ]]; then
    if ((is_codex)); then
      printf '{"personal_access_token_name":"qvOS Codex test"}\n'
    else
      printf '{"personal_access_token_name":null}\n'
    fi
  fi
  ;;
login)
  if ((is_codex)); then
    [[ ${PROTON_PASS_PERSONAL_ACCESS_TOKEN:-} == "$fixture_pat" ]]
    [[ -f $state_root/pat-grant ]]
  fi
  install -d -m 0700 "$XDG_DATA_HOME"
  install -m 0600 /dev/null "$session_file"
  ;;
logout)
  rm -f "$session_file"
  ;;
vault)
  case ${2:-} in
  list)
    [[ -f $session_file ]]
    if ((is_codex)); then
      if [[ ${QVOS_TEST_PASS_SCOPE_FAIL:-0} == "1" ]]; then
        printf '{"vaults":[{"name":"Unexpected","share_id":"share_other","vault_id":"vault_other"}]}\n'
      else
        printf '{"vaults":[{"name":"Codex Vault","share_id":"share_codex","vault_id":"vault_codex"}]}\n'
      fi
    elif [[ -f $state_root/codex-vault ]]; then
      printf '{"vaults":[{"name":"Personal","share_id":"share_personal","vault_id":"vault_personal"},{"name":"Codex Vault","share_id":"share_codex","vault_id":"vault_codex"}]}\n'
    else
      printf '{"vaults":[{"name":"Personal","share_id":"share_personal","vault_id":"vault_personal"}]}\n'
    fi
    ;;
  create)
    [[ $* == *'--name Codex Vault'* ]]
    install -m 0600 /dev/null "$state_root/codex-vault"
    ;;
  *)
    exit 1
    ;;
  esac
  ;;
pat)
  case "${2:-} ${3:-}" in
  "create --name")
    install -m 0600 /dev/null "$state_root/pat-present"
    printf '{"env_var":"PROTON_PASS_PERSONAL_ACCESS_TOKEN=%s","pat_id":"pat_fixture"}\n' "$fixture_pat"
    ;;
  "list --output")
    if [[ -f $state_root/pat-present ]]; then
      printf '[{"pat_id":"pat_fixture","name":"qvOS Codex test","expire_time":null,"is_agent":false}]\n'
    else
      printf '[]\n'
    fi
    ;;
  "access grant")
    [[ $* == *'--personal-access-token-id pat_fixture'* ]]
    [[ $* == *'--share-id share_codex'* ]]
    [[ $* == *'--role viewer'* ]]
    install -m 0600 /dev/null "$state_root/pat-grant"
    ;;
  "delete --personal-access-token-id")
    rm -f "$state_root/pat-grant" "$state_root/pat-present"
    ;;
  *)
    exit 1
    ;;
  esac
  ;;
*)
  exit 1
  ;;
esac
PASS

install -m 0755 /dev/stdin "$drive_fixture" <<'DRIVE'
#!/bin/bash
set -euo pipefail

state_root="$HOME/.qvos-test-proton"
install -d -m 0700 "$state_root"

case $* in
version)
  printf 'Proton Drive CLI test\n'
  ;;
"filesystem info -j /my-files")
  [[ -f $state_root/drive-auth ]]
  ;;
"auth login")
  printf 'drive\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  install -m 0600 /dev/null "$state_root/drive-auth"
  ;;
"auth logout")
  printf 'drive\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  rm -f "$state_root/drive-auth"
  ;;
*)
  exit 1
  ;;
esac
DRIVE

drive_checksum=$(sha512sum "$drive_fixture" | cut -d " " -f 1)

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
if omarchy-cmd-present "$1"; then
  exit 1
fi
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
curl | jq | openssl | ss)
  exit 0
  ;;
protonmail-bridge-core)
  [[ -f $HOME/.qvos-test-proton/bridge-installed ]]
  ;;
protonvpn)
  [[ -f $HOME/.qvos-test-proton/account-cli-installed ]]
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
install -d -m 0700 "$HOME/.qvos-test-proton"

for package in "$@"; do
  case $package in
  protonmail-bridge-core)
    install -m 0600 /dev/null "$HOME/.qvos-test-proton/bridge-installed"
    install -m 0600 /dev/null "$HOME/.qvos-test-proton/bridge-enabled"
    ;;
  proton-vpn-cli)
    install -m 0600 /dev/null "$HOME/.qvos-test-proton/account-cli-installed"
    install -m 0600 /dev/null "$HOME/.qvos-test-proton/account-cli-enabled"
    ;;
  esac
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/protonmail-bridge-core" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

if [[ $* == "--cli" ]]; then
  if [[ ${QVOS_PROTON_BRIDGE_MODE:-} == "inspect" ]]; then
    if [[ -f $HOME/.qvos-test-proton/bridge-auth ]]; then
      printf '# : account              (status,          address mode)\n'
      printf '0: Yaqyn                (connected,       combined)\n'
    else
      printf 'No active accounts.\n'
    fi
    exit
  fi

  printf 'bridge\t%s\n' "${QVOS_PROTON_BRIDGE_MODE:-login}" \
    >>"$QVOS_TEST_ACTION_LOG"
  install -d -m 0700 "$HOME/.qvos-test-proton"
  install -m 0600 /dev/null "$HOME/.qvos-test-proton/bridge-auth"
  exit
fi

exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

state_root="$HOME/.qvos-test-proton"
install -d -m 0700 "$state_root"
printf 'systemctl\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"

case $* in
"is-enabled --quiet proton.VPN.service")
  [[ -f $state_root/account-cli-enabled ]]
  ;;
"is-active --quiet proton.VPN.service")
  exit 1
  ;;
"disable --now proton.VPN.service")
  rm -f "$state_root/account-cli-enabled"
  ;;
"--user is-enabled --quiet protonmail-bridge.service")
  [[ -f $state_root/bridge-enabled ]]
  ;;
"--user disable protonmail-bridge.service")
  rm -f "$state_root/bridge-enabled"
  ;;
"--user start protonmail-bridge.service")
  if [[ -f $state_root/bridge-auth ]]; then
    install -m 0600 /dev/null "$state_root/bridge-active"
  fi
  ;;
"--user stop protonmail-bridge.service")
  rm -f "$state_root/bridge-active"
  ;;
"--user is-active --quiet protonmail-bridge.service")
  [[ -f $state_root/bridge-active ]]
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/ss" <<'SCRIPT'
#!/bin/bash
if [[ -f $HOME/.qvos-test-proton/bridge-active ]]; then
  printf '%s\n' \
    'LISTEN 0 4096 127.0.0.1:1025 0.0.0.0:* users:(("protonmail-brid",pid=1,fd=1))' \
    'LISTEN 0 4096 127.0.0.1:1143 0.0.0.0:* users:(("protonmail-brid",pid=1,fd=2))'
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sleep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ $1 == "systemctl" ]]; then
  exec systemctl "${@:2}"
elif [[ $1 == "install" ]]; then
  if [[ $* == "install -d -m 0755 /etc/pacman.d/hooks" ]]; then
    exit
  elif [[ $* == "install -m 0644 /dev/stdin /etc/pacman.d/hooks/qvos-proton-on-demand.hook" ]]; then
    exec install -m 0644 /dev/stdin "$QVOS_TEST_PROTON_HOOK_FIXTURE"
  fi
  exec install "${@:2}"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
printf 'curl\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"

output_path=""
previous=""
for argument in "$@"; do
  if [[ $previous == "-o" ]]; then
    output_path=$argument
  fi
  previous=$argument
done

case $* in
*"https://proton.me/download/pass-cli/install.sh"*)
  printf '%s\n' \
    '#!/bin/bash' \
    'printf "pass-installer\t%s\n" "$PROTON_PASS_CLI_INSTALL_DIR" >>"$QVOS_TEST_ACTION_LOG"' \
    'install -d "$PROTON_PASS_CLI_INSTALL_DIR"' \
    'install -m 0755 "$QVOS_TEST_PASS_FIXTURE" "$PROTON_PASS_CLI_INSTALL_DIR/pass-cli"'
  ;;
*"https://proton.me/download/drive/cli/version.json"*)
  printf '%s\n' \
    '{"Releases":[{"CategoryName":"Stable","Files":[' \
    "{\"Url\":\"https://proton.me/download/drive/cli/test/linux-x64/proton-drive\",\"Sha512CheckSum\":\"$QVOS_TEST_DRIVE_CHECKSUM\",\"Platform\":\"linux/x64\"}" \
    ']}]}'
  ;;
*"https://proton.me/download/drive/cli/test/linux-x64/proton-drive"*)
  install -m 0644 "$QVOS_TEST_DRIVE_FIXTURE" "$output_path"
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

run_component() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_DRIVE_CHECKSUM="$drive_checksum" \
    QVOS_TEST_DRIVE_FIXTURE="$drive_fixture" \
    QVOS_TEST_PASS_FIXTURE="$pass_fixture" \
    QVOS_TEST_PASS_SCOPE_FAIL="${QVOS_TEST_PASS_SCOPE_FAIL:-0}" \
    QVOS_TEST_PROTON_HOOK_FIXTURE="$proton_hook_fixture" \
    HOME="$test_root" \
    TMPDIR="$test_root/tmp" \
    XDG_CONFIG_HOME="$test_root/.config" \
    PATH="$test_bin:/usr/bin" \
    "$component" "$@"
}

: >"$action_log"
component_output=$(run_component)

assert_log $'package\tprotonmail-bridge-core' "official Bridge core package"
assert_log $'package\tproton-vpn-cli' "official account CLI package"
assert_log $'curl\t-fsSL https://proton.me/download/pass-cli/install.sh' "official Pass installer"
assert_log $'curl\t-fsSL https://proton.me/download/drive/cli/version.json' "official Drive metadata"
assert_log $'pass-installer\t'"$test_root/.local/bin" "Pass install directory"
assert_log $'sudo\t-v' "single explicit sudo authorization"
assert_log $'sudo\tsystemctl disable --now proton.VPN.service' "VPN boot disable"
assert_log $'systemctl\t--user disable protonmail-bridge.service' "Bridge login disable"
grep -Fq 'Proton component inventory: 0/5 installed' <<<"$component_output" ||
  fail "initial component inventory"
grep -Fq 'No Proton authentication was found; continuing with setup.' \
  <<<"$component_output" ||
  fail "fresh authentication continues automatically"

[[ $("$test_root/.local/bin/pass-cli" --version) == "Proton Pass CLI test" ]] ||
  fail "Pass CLI install"
[[ $("$test_root/.local/bin/proton-drive" version) == "Proton Drive CLI test" ]] ||
  fail "Drive CLI install"
[[ $(stat -c '%a' "$test_root/.local/bin/pass-cli") == "755" ]] ||
  fail "Pass CLI executable mode"
grep -Fqx "  \"\$drive_cli\" filesystem info -j /my-files >/dev/null 2>&1" \
  "$component" ||
  fail "Drive JSON option placement"
if grep -RqE 'proton-drive -j|["][$]drive_cli["] -j' \
  "$component" "$skill_source"; then
  fail "Drive JSON option precedes its leaf command"
fi
pass "Proton installs official CLI and headless Bridge entry points"

(( $(grep -Fc $'pass-cli\tlogin' "$action_log") == 2 )) ||
  fail "temporary and isolated Pass login count"
grep -Fq $'pass-cli\tvault create --name Codex Vault' "$action_log" ||
  fail "Codex Vault creation"
grep -Fq $'pass-cli\tpat create --name qvOS Codex ' "$action_log" ||
  fail "viewer PAT creation"
grep -Fq $'pass-cli\tpat access grant --personal-access-token-id pat_fixture --share-id share_codex --role viewer' "$action_log" ||
  fail "viewer PAT grant"
assert_log $'drive\tauth login' "Drive browser authentication"
assert_log $'bridge\tlogin' "Mail Bridge authentication"
grep -Fq 'Proton setup is complete:' <<<"$component_output" ||
  fail "complete setup result"
if grep -Fq 'fixture-key' "$action_log" ||
  grep -Fq 'fixture-key' <<<"$component_output"; then
  fail "PAT leaked into setup output"
fi
pass "Proton runs Pass, Drive, and Mail authentication without leaking the PAT"

cmp -s "$skill_source/SKILL.md" "$installed_skill/SKILL.md" ||
  fail "Codex Proton skill install"
cmp -s "$skill_source/agents/openai.yaml" "$installed_skill/agents/openai.yaml" ||
  fail "Codex Proton skill metadata install"
[[ $(stat -c '%a' "$installed_skill/SKILL.md") == "644" ]] ||
  fail "Codex Proton skill mode"
for isolated_dir in \
  "$codex_pass_root" \
  "$codex_pass_root/data" \
  "$codex_pass_root/config" \
  "$codex_pass_root/cache"; do
  [[ $(stat -c '%a' "$isolated_dir") == "700" ]] ||
    fail "Codex Pass isolation mode"
done
[[ $(stat -c '%a' "$codex_pass_root/data/session") == "600" ]] ||
  fail "Codex Pass session mode"
if find "$test_root/tmp" -maxdepth 1 -type d -name 'qvos-proton-pass-admin.*' |
  grep -q .; then
  fail "temporary Pass admin session remains"
fi
pass "Proton installs the skill and keeps only the isolated Codex session"

cmp -s "$root/qv/thunar/proton-drive-upload" "$upload_helper" ||
  fail "Proton Drive upload helper installation"
cmp -s "$root/qv/core/proton/post-update.sh" "$desktop_hook" ||
  fail "Proton desktop post-update hook"
[[ -f $desktop_state ]] || fail "Proton desktop enabled state"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-proton-drive-upload'])" "$thunar_config") == "1" ]] ||
  fail "Proton Drive Thunar action"
run_component --status >/dev/null ||
  fail "complete Proton lifecycle status"
pass "Proton exposes an update-repairable Thunar upload integration"

rm -f "$test_root/.local/bin/proton-drive"
rm -rf "$installed_skill"
: >"$action_log"
rerun_output=$(printf 'k\n' | run_component)
cmp -s "$skill_source/SKILL.md" "$installed_skill/SKILL.md" ||
  fail "rerun Codex Proton skill"
grep -Fq 'Proton component inventory: 3/5 installed' <<<"$rerun_output" ||
  fail "partial component inventory"
assert_log $'curl\t-fsSL https://proton.me/download/drive/cli/version.json' \
  "partial Drive install"
if grep -Fq $'curl\t-fsSL https://proton.me/download/pass-cli/install.sh' \
  "$action_log" ||
  grep -Fq $'package\t' "$action_log" ||
  grep -Fq $'sudo\t' "$action_log"; then
  fail "partial rerun reinstalls ready components"
fi
if grep -Eq $'pass-cli\t(login|vault create|pat create|pat access grant)' "$action_log" ||
  grep -Fq $'drive\tauth login' "$action_log" ||
  grep -Fq $'bridge\tlogin' "$action_log" ||
  grep -Fq $'bridge\treset' "$action_log"; then
  fail "rerun repeats authentication"
fi
grep -Fq 'Proton Pass Codex access is already ready; keeping it.' \
  <<<"$rerun_output" ||
  fail "rerun Pass readiness"
grep -Fq 'Proton Drive is already ready; keeping it.' <<<"$rerun_output" ||
  fail "rerun Drive readiness"
grep -Fq 'Proton Mail Bridge is already authenticated; keeping it.' \
  <<<"$rerun_output" ||
  fail "rerun Bridge readiness"
pass "Proton installs only the missing components from a 3/5 inventory"

: >"$action_log"
complete_rerun_output=$(printf 'skip\n' | run_component)
grep -Fq 'Proton component inventory: 5/5 installed' \
  <<<"$complete_rerun_output" ||
  fail "complete component inventory"
if grep -Eq $'^(package|curl|pass-installer|sudo)\t' "$action_log" ||
  grep -Eq $'pass-cli\t(login|vault create|pat create|pat access grant)' \
    "$action_log" ||
  grep -Eq $'drive\tauth (login|logout)' "$action_log" ||
  grep -Eq $'bridge\t(login|reset)' "$action_log"; then
  fail "complete rerun changes installation or authentication"
fi
pass "Proton skips installation when all five components are ready"

: >"$action_log"
reset_output=$(printf 'reset\n' | run_component)
grep -Fq 'Existing Proton authentication was found.' <<<"$reset_output" ||
  fail "existing authentication prompt"
grep -Fq $'pass-cli\tpat list --output json' "$action_log" ||
  fail "Pass reset PAT lookup"
grep -Fq $'pass-cli\tpat delete --personal-access-token-id pat_fixture' \
  "$action_log" ||
  fail "Pass reset PAT revocation"
assert_log $'drive\tauth logout' "Drive reset logout"
assert_log $'drive\tauth login' "Drive reset login"
assert_log $'bridge\treset' "Mail Bridge reset"
if grep -Eq $'^(package|curl|pass-installer|sudo)\t' "$action_log"; then
  fail "authentication reset reinstalls components"
fi
grep -Fq 'Proton setup is complete:' <<<"$reset_output" ||
  fail "reset completion"
pass "Proton reset revokes and reauthenticates the ready services"

rm -f "$codex_pass_root/data/session" "$test_state/pat-grant"
: >"$action_log"
set +e
failed_output=$(QVOS_TEST_PASS_SCOPE_FAIL=1 run_component 2>&1)
failed_status=$?
set -e
((failed_status != 0)) || fail "failed Pass scope succeeds"
grep -Fq $'pass-cli\tpat delete --personal-access-token-id pat_fixture' "$action_log" ||
  fail "failed Pass setup PAT cleanup"
if grep -Fq 'Proton setup is complete:' <<<"$failed_output" ||
  grep -Fq 'fixture-key' <<<"$failed_output"; then
  fail "failed setup reports completion or leaks PAT"
fi
pass "failed Pass scope removes its PAT and cannot report completion"

grep -Fqx 'Target = proton-vpn-daemon' "$component" ||
  fail "VPN package hook trigger"
grep -Fqx 'Exec = /usr/bin/systemctl disable --now proton.VPN.service' "$component" ||
  fail "VPN package hook action"
if grep -Eq '^[[:space:]]*(sudo[[:space:]]+)?systemctl ([^[:space:]]+[[:space:]]+)*enable([[:space:]]|$)' "$component"; then
  fail "Proton setup enables a boot service"
fi
pass "Proton services stay disabled at boot and login"

grep -Fqx '  omarchy-pkg-add protonmail-bridge-core' "$component" ||
  fail "Bridge core package"
grep -Fqx '  omarchy-pkg-add proton-vpn-cli' "$component" ||
  fail "account CLI package"
[[ ! -e $root/bin/omarchy-launch-proton-bridge ]] ||
  fail "redundant Bridge polling launcher"
if grep -Fq 'omarchy-pkg-add protonmail-bridge proton-vpn-cli' "$component" ||
  grep -Eq 'Proton Mail Bridge[.]desktop|Hidden=true' "$component"; then
  fail "Bridge GUI or autostart workaround remains"
fi
grep -Fq 'systemctl --user start protonmail-bridge.service' "$component" ||
  fail "on-demand Bridge start"
pass "Bridge remains CLI-only, authenticated, and active on demand"

if grep -Eq '^[[:space:]]*protonvpn (signin|connect)([[:space:]]|$)' "$component"; then
  fail "Proton setup starts a network connection"
fi
pass "Proton account authentication does not start a network connection"

if grep -Eqi 'warp|blocked locally|regional' "$component"; then
  fail "Proton setup contains a regional network workaround"
fi
pass "Proton setup stays universal and network-agnostic"

if grep -RqF '/home/qv' "$skill_source"; then
  fail "Codex Proton skill hard-codes the original user"
fi
grep -Fq "proton_pass_root=\"\$HOME/.local/share/qvos-codex/proton-pass\"" \
  "$skill_source/SKILL.md" ||
  fail "Codex Proton skill portable home"
pass "Codex Proton skill supports any fresh-install user home"

disable_output=$(run_component --disable)
[[ ! -e $upload_helper && ! -e $desktop_hook && ! -e $desktop_state ]] ||
  fail "Proton desktop disable owned-file removal"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-proton-drive-upload'])" "$thunar_config") == "0" ]] ||
  fail "Proton desktop disable action removal"
[[ -x $test_root/.local/bin/proton-drive ]] ||
  fail "Proton desktop disable preserves Drive CLI"
grep -Fq 'Proton services remain installed.' <<<"$disable_output" ||
  fail "Proton desktop disable boundary"
pass "Proton desktop integration can be disabled without removing services"
