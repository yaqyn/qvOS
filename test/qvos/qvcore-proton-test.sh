#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_bin="$test_root/bin"
packages="$test_root/packages"
log="$test_root/actions.log"
install_output="$test_root/install-output.log"
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
  "$source_root/qv/core/proton/skill/agents" \
  "$source_root/qv/direct" \
  "$source_root/qv/thunar" \
  "$test_bin" \
  "$packages" \
  "$(dirname -- "$thunar_config")"
cp "$root/qv/core/proton.sh" "$source_root/qv/core/proton.sh"
cp "$root/qv/core/proton/skill/SKILL.md" "$source_root/qv/core/proton/skill/SKILL.md"
cp "$root/qv/core/proton/skill/agents/openai.yaml" \
  "$source_root/qv/core/proton/skill/agents/openai.yaml"
cp "$root/qv/thunar/actions.sh" "$source_root/qv/thunar/actions.sh"
cp "$root/qv/thunar/proton-drive-upload" "$source_root/qv/thunar/proton-drive-upload"
printf '<?xml version="1.0" encoding="UTF-8"?><actions/>\n' >"$thunar_config"

install -m 0755 /dev/stdin "$source_root/qv/direct/tool" <<'SCRIPT'
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
case ${1:-} in
--version) echo "pass-cli 1.0.0" ;;
info) echo '{"personal_access_token_name":"qvOS Codex"}' ;;
test) exit 0 ;;
vault) echo '{"vaults":[{"name":"Codex Vault"}]}' ;;
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
sudo | gum) exit 0 ;;
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
    PATH="$test_bin:/usr/bin" \
    QVOS_THUNAR_CONFIG="$thunar_config" \
    QVOS_TEST_PACKAGES="$packages" \
    QVOS_TEST_LOG="$log" \
    "$source_root/qv/core/proton.sh" "$@"
}

run_proton install </dev/null >"$install_output" 2>&1
if rg -qi 'choose .*reset|choose .*skip|reset or skip' "$install_output"; then
  fail "Proton Install-only authentication flow"
fi
[[ -f $test_root/home/.local/state/qvos/qvcore/proton ]] ||
  fail "Proton enrollment"
[[ -x $test_root/home/.local/bin/pass-cli &&
  -x $test_root/home/.local/bin/proton-drive ]] ||
  fail "Proton direct tools"
[[ -f $packages/protonmail-bridge-core && -f $packages/proton-vpn-cli ]] ||
  fail "Proton packages"
[[ -f $test_root/home/.codex/skills/proton-cli/SKILL.md ]] ||
  fail "Proton Codex skill"
[[ -x $test_root/home/.local/share/qvos/thunar/proton-drive-upload ]] ||
  fail "Proton desktop integration"
printf 'credential state\n' >"$auth_root/data/preserved"

run_proton remove --yes >/dev/null
[[ ! -e $test_root/home/.local/bin/pass-cli &&
  ! -e $test_root/home/.local/bin/proton-drive ]] ||
  fail "Proton direct-tool removal"
[[ -z $(find "$packages" -type f -print -quit) ]] ||
  fail "Proton package removal"
[[ ! -e $test_root/home/.codex/skills/proton-cli ]] ||
  fail "Proton skill removal"
[[ ! -e $test_root/home/.local/share/qvos/thunar/proton-drive-upload ]] ||
  fail "Proton desktop integration removal"
[[ $(<"$auth_root/data/preserved") == "credential state" ]] ||
  fail "Proton authentication preservation"

printf 'ok - Proton installs one verified stack and preserves cloud authentication on Remove\n'
