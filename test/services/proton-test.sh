#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_bin="$test_root/bin"
packages="$test_root/packages"
log="$test_root/actions.log"
install_output="$test_root/install-output.log"
recovery_output="$test_root/recovery-output.log"
thunar_config="$test_root/home/.config/Thunar/uca.xml"
auth_root="$test_root/home/.local/share/qvos-codex/proton-pass"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/services/proton/skill/agents" \
  "$source_root/qvcore/direct" \
  "$source_root/qvcore/install" \
  "$source_root/qvcore/thunar" \
  "$test_bin" \
  "$packages" \
  "$(dirname -- "$thunar_config")"
cp "$root/services/proton/manage" "$source_root/services/proton/manage"
cp "$root/services/proton/skill/SKILL.md" "$source_root/services/proton/skill/SKILL.md"
cp "$root/services/proton/skill/agents/openai.yaml" \
  "$source_root/services/proton/skill/agents/openai.yaml"
cp "$root/qvcore/install/migrate-structure" "$source_root/qvcore/install/migrate-structure"
cp "$root/qvcore/thunar/actions.sh" "$source_root/qvcore/thunar/actions.sh"
cp "$root/qvcore/thunar/proton-drive-upload" "$source_root/qvcore/thunar/proton-drive-upload"
printf '<?xml version="1.0" encoding="UTF-8"?><actions/>\n' >"$thunar_config"

install -m 0755 /dev/stdin "$source_root/qvcore/direct/tool" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
action=$1
tool_id=$2
target="$HOME/.local/bin/${tool_id/proton-drive/proton-drive}"
[[ $tool_id != "pass-cli" ]] || target="$HOME/.local/bin/pass-cli"
case $action in
install)
  install -d "$HOME/.local/bin"
  if [[ $tool_id == "pass-cli" ]]; then
    install -m 0755 /dev/stdin "$target" <<'PASS'
#!/bin/bash
if [[ ${1:-} != "--version" &&
  ${PROTON_PASS_LINUX_KEYRING:-} != "dbus" ]]; then
  exit 91
fi
session_dir="$XDG_DATA_HOME/proton-pass-cli/.session"
case ${1:-} in
--version) echo "pass-cli 1.0.0" ;;
info)
  install -d -m 0700 "$session_dir"
  install -m 0600 /dev/null "$session_dir/pass-cli.db"
  [[ -f $session_dir/session.json ]] || exit 1
  [[ ! -f $session_dir/invalid ]] || exit 1
  echo '{"personal_access_token_name":"qvOS Codex"}'
  ;;
test) exit 88 ;;
login)
  install -d -m 0700 "$session_dir"
  install -m 0600 /dev/null "$session_dir/pass-cli.db"
  printf 'session\n' >"$session_dir/session.json"
  chmod 0600 "$session_dir/session.json"
  ;;
logout)
  rm -rf -- "$session_dir"
  ;;
vault)
  case ${2:-} in
  list)
    [[ -f $session_dir/session.json ]] || exit 1
    [[ ! -f $session_dir/invalid ]] || exit 1
    echo '{"vaults":[{"name":"Codex Vault","share_id":"share-1"}]}'
    ;;
  create) exit 0 ;;
  *) exit 1 ;;
  esac
  ;;
pat) exit 89 ;;
personal-access-token)
  case ${2:-} in
  create)
    echo '{"pat_id":"pat-1","env_var":"pst_test::key"}'
    ;;
  access) exit 0 ;;
  delete)
    printf 'pat-delete\t%s\n' "$*" >>"$QVOS_TEST_LOG"
    ;;
  list)
    case ${QVOS_TEST_PAT_MODE:-none} in
    none) echo '[]' ;;
    one) echo '[{"name":"qvOS Codex 20260801T000000Z","pat_id":"old-pat"}]' ;;
    multiple)
      echo '[{"name":"qvOS Codex 20260801T000000Z","pat_id":"old-pat-1"},{"name":"qvOS Codex 20260801T000001Z","pat_id":"old-pat-2"}]'
      ;;
    *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
  esac
  ;;
*) exit 0 ;;
esac
PASS
  else
    install -m 0755 /dev/stdin "$target" <<'DRIVE'
#!/bin/bash
case ${1:-} in
version) echo "proton-drive 1.0.0" ;;
filesystem) exit 0 ;;
auth) exit 0 ;;
*) exit 0 ;;
esac
DRIVE
  fi
  printf 'direct-install\t%s\n' "$tool_id" >>"$QVOS_TEST_LOG"
  ;;
verify | installed)
  [[ -x $target ]] &&
    "$target" "$([[ $tool_id == pass-cli ]] && echo --version || echo version)" >/dev/null
  ;;
remove) rm -f "$target"; printf 'direct-remove\t%s\n' "$tool_id" >>"$QVOS_TEST_LOG" ;;
esac
SCRIPT

for name in omarchy-cmd-present omarchy-cmd-missing omarchy-pkg-add \
  omarchy-pkg-drop pacman systemctl sudo ss protonmail-bridge-core protonvpn \
  gio gum; do
  install -m 0755 /dev/stdin "$test_bin/$name" <<'SCRIPT'
#!/bin/bash
case ${0##*/} in
omarchy-cmd-present)
  case $1 in
  protonmail-bridge-core) [[ -f $QVOS_TEST_PACKAGES/protonmail-bridge-core ]] ;;
  protonvpn) [[ -f $QVOS_TEST_PACKAGES/proton-vpn-cli ]] ;;
  *) command -v "$1" >/dev/null 2>&1 ;;
  esac
  ;;
omarchy-cmd-missing)
  ! omarchy-cmd-present "$1"
  ;;
omarchy-pkg-add)
  for package in "$@"; do
    install -m 0644 /dev/null "$QVOS_TEST_PACKAGES/$package"
    printf 'package-add\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
omarchy-pkg-drop)
  for package in "$@"; do
    rm -f "$QVOS_TEST_PACKAGES/$package"
    printf 'package-drop\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
pacman)
  if [[ ${1:-} == "-Q" ]]; then
    [[ -f $QVOS_TEST_PACKAGES/$2 ]]
  else
    exit 0
  fi
  ;;
systemctl)
  [[ $* != *is-enabled* ]]
  ;;
sudo) exit 0 ;;
gum)
  printf 'gum-confirm\t%s\n' "$*" >>"$QVOS_TEST_LOG"
  [[ ${QVOS_TEST_GUM_CANCEL:-0} != "1" ]]
  ;;
ss)
  printf 'LISTEN 0 1 127.0.0.1:1143 users:(("protonmail-brid",pid=1,fd=1))\n'
  printf 'LISTEN 0 1 127.0.0.1:1025 users:(("protonmail-brid",pid=1,fd=2))\n'
  ;;
protonmail-bridge-core)
  printf '1: user@example.test ( connected, bridge )\n'
  ;;
protonvpn) exit 0 ;;
gio)
  [[ $1 == "trash" ]]
  rm -rf -- "$2"
  ;;
esac
SCRIPT
done

run_proton() {
  HOME="$test_root/home" \
    XDG_STATE_HOME="$test_root/home/.local/state" \
    PATH="$test_bin:/usr/bin" \
    QVOS_THUNAR_CONFIG="$thunar_config" \
    QVOS_TEST_PACKAGES="$packages" \
    QVOS_TEST_LOG="$log" \
    "$source_root/services/proton/manage" "$@"
}

run_proton install </dev/null >"$install_output" 2>&1
if rg -qi 'choose .*reset|choose .*skip|reset or skip' "$install_output"; then
  fail "Proton Install-only authentication flow"
fi
grep -Fq 'Continuing past the unauthenticated Proton Pass probe cache.' \
  "$install_output" ||
  fail "Proton probe cache blocks fresh authentication"
[[ -f $test_root/home/.local/state/qvos/services/proton ]] ||
  fail "Proton enrollment"
[[ $(stat -c '%a' "$test_root/home/.local/state/qvos/services") == "700" &&
  $(stat -c '%a' "$test_root/home/.local/state/qvos/services/proton") == "600" ]] ||
  fail "private Proton enrollment"
[[ -x $test_root/home/.local/bin/pass-cli &&
  -x $test_root/home/.local/bin/proton-drive ]] ||
  fail "Proton direct tools"
[[ -f $packages/protonmail-bridge-core && -f $packages/proton-vpn-cli ]] ||
  fail "Proton packages"
[[ -f $test_root/home/.codex/skills/proton-cli/SKILL.md ]] ||
  fail "Proton Codex skill"
[[ -f $auth_root/data/proton-pass-cli/.session/session.json ]] ||
  fail "Proton Codex authentication"
[[ -x $test_root/home/.local/lib/qvos/thunar/proton-drive-upload ]] ||
  fail "Proton desktop integration"

printf 'stale integration\n' \
  >"$test_root/home/.local/lib/qvos/thunar/proton-drive-upload"
printf 'stale skill\n' \
  >"$test_root/home/.codex/skills/proton-cli/SKILL.md"
action_count=$(wc -l <"$log")
auth_hash=$(sha256sum "$auth_root/data/proton-pass-cli/.session/session.json")
run_proton reconcile >/dev/null
cmp -s \
  "$source_root/qvcore/thunar/proton-drive-upload" \
  "$test_root/home/.local/lib/qvos/thunar/proton-drive-upload" ||
  fail "Proton enrolled desktop reconciliation"
cmp -s \
  "$source_root/services/proton/skill/SKILL.md" \
  "$test_root/home/.codex/skills/proton-cli/SKILL.md" ||
  fail "Proton enrolled Codex reconciliation"
[[ $(wc -l <"$log") == "$action_count" ]] ||
  fail "Proton reconciliation changed packages, tools, or authentication"
[[ $(sha256sum "$auth_root/data/proton-pass-cli/.session/session.json") == "$auth_hash" ]] ||
  fail "Proton reconciliation changed authentication state"
printf 'credential state\n' >"$auth_root/data/preserved"

run_proton remove --yes >/dev/null
[[ ! -e $test_root/home/.local/bin/pass-cli &&
  ! -e $test_root/home/.local/bin/proton-drive ]] ||
  fail "Proton direct-tool removal"
[[ -z $(find "$packages" -type f -print -quit) ]] ||
  fail "Proton package removal"
[[ ! -e $test_root/home/.codex/skills/proton-cli ]] ||
  fail "Proton skill removal"
[[ ! -e $test_root/home/.local/lib/qvos/thunar/proton-drive-upload ]] ||
  fail "Proton desktop integration removal"
[[ $(<"$auth_root/data/preserved") == "credential state" ]] ||
  fail "Proton authentication preservation"

session_dir="$auth_root/data/proton-pass-cli/.session"
install -m 0600 /dev/null "$session_dir/invalid"
export QVOS_TEST_PAT_MODE=none
run_proton install </dev/null >"$recovery_output" 2>&1
grep -Fq 'Cleared the invalid local session; no matching qvOS Codex PAT remained.' \
  "$recovery_output" || fail "Proton invalid local-session recovery"
[[ ! -e $session_dir/invalid ]] || fail "Proton invalid local session remains"
grep -Fq $'gum-confirm\tconfirm Replace the invalid isolated qvOS Codex Pass session?' \
  "$log" || fail "Proton invalid-session replacement confirmation"
if grep -Fq $'pat-delete\t' "$log"; then
  fail "Proton recovery revoked an unrelated PAT"
fi
run_proton remove --yes >/dev/null

install -d -m 0700 "$session_dir"
install -m 0600 /dev/stdin "$session_dir/session.json" <<'SESSION'
stale session
SESSION
install -m 0600 /dev/null "$session_dir/invalid"
export QVOS_TEST_PAT_MODE=one
run_proton install </dev/null >"$recovery_output" 2>&1
grep -Fq $'pat-delete\tpersonal-access-token delete --personal-access-token-id old-pat' \
  "$log" || fail "Proton exact stale PAT revocation"
[[ ! -e $session_dir/invalid ]] || fail "Proton stale PAT session remains"
run_proton remove --yes >/dev/null

install -d -m 0700 "$session_dir"
install -m 0600 /dev/stdin "$session_dir/session.json" <<'SESSION'
ambiguous session
SESSION
install -m 0600 /dev/null "$session_dir/invalid"
export QVOS_TEST_PAT_MODE=multiple
if run_proton install </dev/null >"$recovery_output" 2>&1; then
  fail "Proton replaced an ambiguous stale session"
fi
grep -Fq 'Multiple qvOS Codex PATs exist; none were changed.' \
  "$recovery_output" || fail "Proton ambiguous PAT diagnosis"
[[ -f $session_dir/invalid ]] || fail "Proton ambiguous session was not preserved"

printf 'ok - Proton installs one verified stack and preserves cloud authentication on Remove\n'
printf 'ok - Proton replaces only explicitly approved, uniquely scoped stale sessions\n'
