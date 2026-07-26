#!/bin/bash
# qvcore:lifecycle=1
set -euo pipefail

component_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_file="$HOME/.local/state/qvos/qvcore/proton"
hook_source="$component_dir/proton/post-update.sh"
hook_target="$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-proton"
pass_installer_url="https://proton.me/download/pass-cli/install.sh"
drive_metadata_url="https://proton.me/download/drive/cli/version.json"
proton_skill_source="$component_dir/proton/skill"
codex_skill_dir="$HOME/.codex/skills/proton-cli"
codex_pass_root="$HOME/.local/share/qvos-codex/proton-pass"
pass_cli="$HOME/.local/bin/pass-cli"
drive_cli="$HOME/.local/bin/proton-drive"
proton_hook_path="/etc/pacman.d/hooks/qvos-proton-on-demand.hook"
thunar_actions_source="$component_dir/../thunar/actions.sh"
thunar_upload_source="$component_dir/../thunar/proton-drive-upload"
thunar_upload_runtime="$HOME/.local/share/qvos/thunar/proton-drive-upload"
thunar_upload_command="/bin/bash -c '\"\$HOME/.local/share/qvos/thunar/proton-drive-upload\" \"\$@\"' qvos-thunar %F"
drive_download=""
pass_admin_root=""
created_pat_id=""
codex_pat=""
restart_bridge_on_cleanup=0

pass_installed=0
drive_installed=0
bridge_installed=0
account_cli_installed=0
codex_integration_installed=0

pass_auth_ready=0
drive_auth_ready=0
mail_auth_ready=0
auth_ready_count=0
auth_action="setup"
mode="install"
upload_helper_ready=0
upload_action_ready=0
maintenance_ready=0
drive_desktop_auth_ready=0

# Thunar integration inventory and lifecycle

# shellcheck source=qv/thunar/actions.sh
source "$thunar_actions_source"

cleanup() {
  unset codex_pat pat_env pat_json

  if [[ -n $created_pat_id && -n $pass_admin_root && -d $pass_admin_root ]]; then
    run_pass_admin pat delete \
      --personal-access-token-id "$created_pat_id" >/dev/null 2>&1 || true
    run_pass_codex logout --force >/dev/null 2>&1 || true
  fi

  cleanup_pass_admin

  if [[ -n $drive_download && -f $drive_download ]]; then
    rm -f "$drive_download"
  fi

  if ((restart_bridge_on_cleanup)); then
    systemctl --user start protonmail-bridge.service >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

vpn_policy_ready() {
  [[ -f $proton_hook_path ]] || return 1

  cmp -s "$proton_hook_path" - <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = proton-vpn-daemon

[Action]
Description = Keep Proton VPN available on demand
When = PostTransaction
Exec = /usr/bin/systemctl disable --now proton.VPN.service
HOOK
}

install_vpn_on_demand_policy() {
  sudo install -d -m 0755 "$(dirname -- "$proton_hook_path")"
  sudo install -m 0644 /dev/stdin "$proton_hook_path" <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = proton-vpn-daemon

[Action]
Description = Keep Proton VPN available on demand
When = PostTransaction
Exec = /usr/bin/systemctl disable --now proton.VPN.service
HOOK
}

pass_cli_installed() {
  [[ -x $pass_cli ]] && "$pass_cli" --version >/dev/null 2>&1
}

drive_cli_installed() {
  [[ -x $drive_cli ]] && "$drive_cli" version >/dev/null 2>&1
}

bridge_cli_installed() {
  omarchy-cmd-present protonmail-bridge-core
}

account_cli_is_installed() {
  omarchy-cmd-present protonvpn
}

status_label() {
  local state=$1
  local ready_label=$2
  local missing_label=$3

  if ((state)); then
    printf '%s\n' "$ready_label"
  else
    printf '%s\n' "$missing_label"
  fi
}

upload_action_is_installed() {
  qvos_thunar_action_matches \
    "qvos-proton-drive-upload" \
    "folder-remote" \
    "Upload to Proton Drive" \
    "$thunar_upload_command" \
    "Upload the selected files and folders to private Proton Drive storage." \
    "*" \
    directories audio-files image-files other-files text-files video-files
}

inventory_desktop_integration() {
  upload_helper_ready=0
  upload_action_ready=0
  maintenance_ready=0
  drive_desktop_auth_ready=0

  [[ -x $thunar_upload_runtime ]] &&
    cmp -s "$thunar_upload_source" "$thunar_upload_runtime" &&
    upload_helper_ready=1
  upload_action_is_installed && upload_action_ready=1
  [[ -f $state_file ]] &&
    [[ -f $hook_target ]] &&
    cmp -s "$hook_source" "$hook_target" &&
    maintenance_ready=1
  drive_ready && drive_desktop_auth_ready=1
  return 0
}

print_desktop_inventory() {
  local ready_count=$((upload_helper_ready +
    upload_action_ready +
    maintenance_ready +
    drive_desktop_auth_ready))

  echo "Proton desktop inventory: $ready_count/4 ready"
  printf '  %-16s %s\n' "Drive helper" \
    "$(status_label "$upload_helper_ready" "ready" "missing")"
  printf '  %-16s %s\n' "Thunar action" \
    "$(status_label "$upload_action_ready" "ready" "missing")"
  printf '  %-16s %s\n' "Update repair" \
    "$(status_label "$maintenance_ready" "ready" "missing")"
  printf '  %-16s %s\n' "Drive access" \
    "$(status_label "$drive_desktop_auth_ready" "ready" "needs-login")"
}

install_desktop_integration() {
  install -d "$HOME/.local/share/qvos/thunar"
  install -m 0755 "$thunar_upload_source" "$thunar_upload_runtime"
  qvos_thunar_ensure_action \
    "qvos-proton-drive-upload" \
    "folder-remote" \
    "Upload to Proton Drive" \
    "$thunar_upload_command" \
    "Upload the selected files and folders to private Proton Drive storage." \
    "*" \
    directories audio-files image-files other-files text-files video-files
  install -D -m 0644 "$hook_source" "$hook_target"
  install -D -m 0644 /dev/null "$state_file"
}

disable_desktop_integration() {
  qvos_thunar_remove_action "qvos-proton-drive-upload"
  rm -f "$state_file" "$hook_target" "$thunar_upload_runtime"
  echo "qvCORE Proton desktop integration is disabled; Proton services remain installed."
}

codex_integration_is_installed() {
  local isolated_dir

  [[ -f $codex_skill_dir/SKILL.md ]] &&
    [[ -f $codex_skill_dir/agents/openai.yaml ]] &&
    cmp -s "$proton_skill_source/SKILL.md" "$codex_skill_dir/SKILL.md" &&
    cmp -s \
      "$proton_skill_source/agents/openai.yaml" \
      "$codex_skill_dir/agents/openai.yaml" ||
    return 1

  for isolated_dir in \
    "$codex_pass_root" \
    "$codex_pass_root/data" \
    "$codex_pass_root/config" \
    "$codex_pass_root/cache"; do
    [[ -d $isolated_dir ]] &&
      [[ $(stat -c '%a' "$isolated_dir") == "700" ]] ||
      return 1
  done
}

inventory_components() {
  local installed_count=0

  pass_installed=0
  drive_installed=0
  bridge_installed=0
  account_cli_installed=0
  codex_integration_installed=0

  pass_cli_installed && pass_installed=1
  drive_cli_installed && drive_installed=1
  bridge_cli_installed && bridge_installed=1
  account_cli_is_installed && account_cli_installed=1
  codex_integration_is_installed && codex_integration_installed=1

  installed_count=$((installed_count + pass_installed))
  installed_count=$((installed_count + drive_installed))
  installed_count=$((installed_count + bridge_installed))
  installed_count=$((installed_count + account_cli_installed))
  installed_count=$((installed_count + codex_integration_installed))

  echo "Proton component inventory: $installed_count/5 installed"
  printf '  %-16s %s\n' "Pass CLI" \
    "$(status_label "$pass_installed" "ready" "missing")"
  printf '  %-16s %s\n' "Drive CLI" \
    "$(status_label "$drive_installed" "ready" "missing")"
  printf '  %-16s %s\n' "Mail Bridge" \
    "$(status_label "$bridge_installed" "ready" "missing")"
  printf '  %-16s %s\n' "Account CLI" \
    "$(status_label "$account_cli_installed" "ready" "missing")"
  printf '  %-16s %s\n' "Codex skill" \
    "$(status_label "$codex_integration_installed" "ready" "missing")"
}

install_pass_cli() {
  echo "Installing Proton Pass CLI from Proton..."
  curl -fsSL "$pass_installer_url" |
    PROTON_PASS_CLI_INSTALL_DIR="$HOME/.local/bin" bash
  chmod 0755 "$pass_cli"
}

install_drive_cli() {
  local drive_arch
  local drive_checksum
  local drive_info
  local drive_metadata
  local drive_platform
  local drive_url

  case $(uname -m) in
  x86_64 | amd64)
    drive_arch="x64"
    ;;
  aarch64 | arm64)
    drive_arch="arm64"
    ;;
  *)
    echo "Proton Drive CLI does not support architecture: $(uname -m)" >&2
    return 1
    ;;
  esac

  drive_platform="linux/$drive_arch"
  drive_metadata=$(curl -fsSL "$drive_metadata_url")
  drive_info=$(
    jq -r --arg platform "$drive_platform" '
      (
        [
          .Releases[]
          | select(.CategoryName == "Stable")
          | .Files[]
          | select(.Platform == $platform)
        ][0] // {}
      )
      | [(.Url // ""), (.Sha512CheckSum // "")]
      | @tsv
    ' <<<"$drive_metadata"
  )
  IFS=$'\t' read -r drive_url drive_checksum <<<"$drive_info"

  if [[ $drive_url != "https://proton.me/download/drive/cli/"*"/proton-drive" ]] ||
    [[ ! $drive_checksum =~ ^[[:xdigit:]]{128}$ ]]; then
    echo "Could not resolve a verified Proton Drive CLI download for $drive_platform" >&2
    return 1
  fi

  drive_download=$(mktemp)
  curl -fsSL -o "$drive_download" "$drive_url"

  if ! printf '%s  %s\n' "$drive_checksum" "$drive_download" | sha512sum --check --status; then
    echo "Proton Drive CLI checksum verification failed" >&2
    return 1
  fi

  install -d "$HOME/.local/bin"
  install -m 0755 "$drive_download" "$drive_cli"
  echo "Installed Proton Drive CLI from Proton."
}

install_codex_integration() {
  local isolated_dir

  if [[ ! -f $proton_skill_source/SKILL.md ]] ||
    [[ ! -f $proton_skill_source/agents/openai.yaml ]]; then
    echo "Missing Proton Codex skill assets: $proton_skill_source" >&2
    return 1
  fi

  install -d -m 0700 \
    "$codex_pass_root" \
    "$codex_pass_root/data" \
    "$codex_pass_root/config" \
    "$codex_pass_root/cache"
  install -d -m 0755 "$codex_skill_dir/agents"
  install -m 0644 "$proton_skill_source/SKILL.md" "$codex_skill_dir/SKILL.md"
  install -m 0644 \
    "$proton_skill_source/agents/openai.yaml" \
    "$codex_skill_dir/agents/openai.yaml"

  cmp -s "$proton_skill_source/SKILL.md" "$codex_skill_dir/SKILL.md" ||
    return 1
  cmp -s \
    "$proton_skill_source/agents/openai.yaml" \
    "$codex_skill_dir/agents/openai.yaml" ||
    return 1

  for isolated_dir in \
    "$codex_pass_root" \
    "$codex_pass_root/data" \
    "$codex_pass_root/config" \
    "$codex_pass_root/cache"; do
    if [[ $(stat -c '%a' "$isolated_dir") != "700" ]]; then
      echo "Unsafe Proton Codex directory mode: $isolated_dir" >&2
      return 1
    fi
  done
}

run_pass_codex() {
  env \
    XDG_DATA_HOME="$codex_pass_root/data" \
    XDG_CONFIG_HOME="$codex_pass_root/config" \
    XDG_CACHE_HOME="$codex_pass_root/cache" \
    PROTON_PASS_AGENT_REASON="Set up qvOS Codex access" \
    "$pass_cli" "$@"
}

run_pass_admin() {
  env \
    XDG_DATA_HOME="$pass_admin_root/data" \
    XDG_CONFIG_HOME="$pass_admin_root/config" \
    XDG_CACHE_HOME="$pass_admin_root/cache" \
    PROTON_PASS_AGENT_REASON="Set up qvOS Codex Vault access" \
    "$pass_cli" "$@"
}

cleanup_pass_admin() {
  if [[ -n $pass_admin_root && -d $pass_admin_root ]]; then
    run_pass_admin logout --force >/dev/null 2>&1 || true
    rm -rf "$pass_admin_root"
    pass_admin_root=""
  fi
}

open_pass_admin() {
  pass_admin_root=$(mktemp -d "${TMPDIR:-/tmp}/qvos-proton-pass-admin.XXXXXX")
  install -d -m 0700 \
    "$pass_admin_root/data" \
    "$pass_admin_root/config" \
    "$pass_admin_root/cache"

  echo ""
  echo "Proton Pass authentication"
  echo "A browser will open for a temporary full-access setup session."
  run_pass_admin login
  run_pass_admin test >/dev/null
}

pass_codex_ready() {
  local info_json
  local vault_json

  info_json=$(run_pass_codex info --output json 2>/dev/null) || return 1
  jq -e '
    .personal_access_token_name
    | type == "string" and length > 0
  ' <<<"$info_json" >/dev/null || return 1
  run_pass_codex test >/dev/null 2>&1 || return 1
  vault_json=$(run_pass_codex vault list --output json 2>/dev/null) || return 1
  jq -e '
    (.vaults // [])
    | length == 1 and .[0].name == "Codex Vault"
  ' <<<"$vault_json" >/dev/null
}

reset_pass_auth() {
  local existing_pat_id
  local existing_pat_name
  local info_json
  local pat_count
  local pat_list

  info_json=$(run_pass_codex info --output json)
  existing_pat_name=$(
    jq -er '
      .personal_access_token_name
      | select(type == "string" and length > 0)
    ' <<<"$info_json"
  )
  if [[ $existing_pat_name == "[Agent] "* ]]; then
    existing_pat_name=${existing_pat_name#"[Agent] "}
  fi

  pat_list=$(run_pass_admin pat list --output json)
  pat_count=$(
    jq --arg name "$existing_pat_name" \
      '[.[] | select(.name == $name)] | length' <<<"$pat_list"
  )

  if ((pat_count == 0)); then
    echo "The existing Codex PAT was not found; its local session was preserved." >&2
    return 1
  elif ((pat_count > 1)); then
    echo "Multiple PATs match the Codex session; none were changed." >&2
    return 1
  fi

  existing_pat_id=$(
    jq -er --arg name "$existing_pat_name" '
      [.[] | select(.name == $name)]
      | if length == 1 then .[0].pat_id else error("PAT is not unique") end
    ' <<<"$pat_list"
  )
  run_pass_admin pat delete \
    --personal-access-token-id "$existing_pat_id" >/dev/null
  run_pass_codex logout --force >/dev/null 2>&1 || true
  echo "Reset the isolated Proton Pass Codex session."
}

setup_pass_auth() {
  local auth_action=$1
  local existing_ready=0
  local pat_env=""
  local pat_json=""
  local pat_name
  local vault_count
  local vault_json
  local vault_share_id

  if pass_codex_ready; then
    existing_ready=1
    if [[ $auth_action != "reset" ]]; then
      echo "Proton Pass Codex access is already ready; keeping it."
      return
    fi
  fi

  if ((existing_ready == 0)) &&
    run_pass_codex info --output json >/dev/null 2>&1; then
    if ! run_pass_codex test >/dev/null 2>&1; then
      echo "Existing Proton Pass Codex access could not be verified." >&2
      echo "Retry when Proton Pass is reachable; the session was not changed." >&2
      return 1
    fi

    if ! vault_json=$(run_pass_codex vault list --output json 2>/dev/null); then
      echo "Could not inspect the existing Proton Pass Codex scope." >&2
      return 1
    fi

    echo "Replacing an isolated Proton Pass session with an unexpected vault scope."
    run_pass_codex logout --force >/dev/null
  elif ((existing_ready == 0)) &&
    find "$codex_pass_root/data" -type f -print -quit | grep -q .; then
    echo "Existing Proton Pass Codex session data could not be verified." >&2
    echo "The session was preserved; resolve or remove it before retrying." >&2
    return 1
  fi

  open_pass_admin
  if ((existing_ready)); then
    reset_pass_auth
  fi

  vault_json=$(run_pass_admin vault list --output json)
  vault_count=$(
    jq '[.vaults[] | select(.name == "Codex Vault")] | length' <<<"$vault_json"
  )

  if ((vault_count == 0)); then
    echo "Creating Codex Vault..."
    run_pass_admin vault create --name "Codex Vault" >/dev/null
    vault_json=$(run_pass_admin vault list --output json)
  elif ((vault_count > 1)); then
    echo "Multiple vaults named Codex Vault exist; resolve them before retrying." >&2
    return 1
  fi

  vault_share_id=$(
    jq -er '
      [.vaults[] | select(.name == "Codex Vault")]
      | if length == 1 then .[0].share_id else error("Codex Vault is not unique") end
    ' <<<"$vault_json"
  )

  pat_name="qvOS Codex $(date -u +%Y%m%dT%H%M%SZ)"
  pat_json=$(
    run_pass_admin pat create \
      --name "$pat_name" \
      --expiration 1y \
      --output json
  )
  created_pat_id=$(jq -er '.pat_id | select(length > 0)' <<<"$pat_json")
  pat_env=$(jq -er '.env_var | select(length > 0)' <<<"$pat_json")
  unset pat_json

  if [[ $pat_env != PROTON_PASS_PERSONAL_ACCESS_TOKEN=* ]]; then
    echo "Proton Pass returned an unexpected PAT response." >&2
    return 1
  fi

  codex_pat=${pat_env#PROTON_PASS_PERSONAL_ACCESS_TOKEN=}
  unset pat_env

  if [[ $codex_pat != pst_*::* ]]; then
    echo "Proton Pass returned an invalid PAT format." >&2
    return 1
  fi

  run_pass_admin pat access grant \
    --personal-access-token-id "$created_pat_id" \
    --share-id "$vault_share_id" \
    --role viewer >/dev/null

  env \
    XDG_DATA_HOME="$codex_pass_root/data" \
    XDG_CONFIG_HOME="$codex_pass_root/config" \
    XDG_CACHE_HOME="$codex_pass_root/cache" \
    PROTON_PASS_AGENT_REASON="Authorize qvOS Codex Vault access" \
    PROTON_PASS_PERSONAL_ACCESS_TOKEN="$codex_pat" \
    "$pass_cli" login >/dev/null
  unset codex_pat

  if ! pass_codex_ready; then
    echo "Proton Pass Codex access failed its scope verification." >&2
    return 1
  fi

  created_pat_id=""
  cleanup_pass_admin
  echo "Proton Pass is ready with viewer access to Codex Vault only."
}

drive_ready() {
  "$drive_cli" filesystem info -j /my-files >/dev/null 2>&1
}

setup_drive_auth() {
  local auth_action=$1

  if drive_ready; then
    if [[ $auth_action != "reset" ]]; then
      echo "Proton Drive is already ready; keeping it."
      return
    fi

    "$drive_cli" auth logout
    echo "Reset Proton Drive authentication."
  fi

  echo ""
  echo "Proton Drive authentication"
  echo "A browser will open; keep this terminal open until authentication completes."
  "$drive_cli" auth login

  if ! drive_ready; then
    echo "Proton Drive authentication could not access /my-files." >&2
    return 1
  fi

  echo "Proton Drive is ready."
}

bridge_listener_count() {
  ss -ltnp 2>/dev/null |
    awk '
      $4 ~ /^127[.]0[.]0[.]1:/ && /protonmail-brid/ { count++ }
      END { print count + 0 }
    '
}

bridge_ready() {
  local listener_count

  systemctl --user is-active --quiet protonmail-bridge.service ||
    return 1
  listener_count=$(bridge_listener_count)
  ((listener_count >= 2))
}

wait_for_bridge() {
  local attempts=$1
  local attempt

  for ((attempt = 0; attempt < attempts; attempt++)); do
    if bridge_ready; then
      return
    fi
    sleep 1
  done

  return 1
}

inspect_bridge_auth() {
  local bridge_output
  local was_active=0

  if systemctl --user is-active --quiet protonmail-bridge.service; then
    was_active=1
    restart_bridge_on_cleanup=1
    systemctl --user stop protonmail-bridge.service
  fi

  if ! bridge_output=$(
    printf 'list\nexit\n' |
      QVOS_PROTON_BRIDGE_MODE=inspect protonmail-bridge-core --cli 2>/dev/null
  ); then
    if ((was_active)); then
      systemctl --user start protonmail-bridge.service
      restart_bridge_on_cleanup=0
    fi
    return 1
  fi

  if ((was_active)); then
    systemctl --user start protonmail-bridge.service
    restart_bridge_on_cleanup=0
  fi

  grep -Eq \
    '\([[:space:]]*(connected|signed out|locked)[[:space:]]*,' \
    <<<"$bridge_output"
}

inventory_authentication() {
  pass_auth_ready=0
  drive_auth_ready=0
  mail_auth_ready=0
  auth_ready_count=0

  pass_codex_ready && pass_auth_ready=1
  drive_ready && drive_auth_ready=1
  inspect_bridge_auth && mail_auth_ready=1

  auth_ready_count=$((auth_ready_count + pass_auth_ready))
  auth_ready_count=$((auth_ready_count + drive_auth_ready))
  auth_ready_count=$((auth_ready_count + mail_auth_ready))

  echo ""
  echo "Proton authentication inventory: $auth_ready_count/3 configured"
  printf '  %-16s %s\n' "Pass" \
    "$(status_label "$pass_auth_ready" "configured" "needs-setup")"
  printf '  %-16s %s\n' "Drive" \
    "$(status_label "$drive_auth_ready" "configured" "needs-setup")"
  printf '  %-16s %s\n' "Mail Bridge" \
    "$(status_label "$mail_auth_ready" "configured" "needs-setup")"
}

choose_auth_action() {
  local auth_choice

  if ((auth_ready_count == 0)); then
    echo "No Proton authentication was found; continuing with setup."
    auth_action="setup"
    return
  fi

  echo ""
  echo "Existing Proton authentication was found."
  echo "  reset  Revoke/sign out ready services, then authenticate all services."
  echo "  skip   Keep ready services and authenticate only missing services."

  while true; do
    printf 'Choose reset or skip [skip]: ' >&2
    if ! IFS= read -r auth_choice; then
      auth_choice="skip"
    fi

    case ${auth_choice,,} in
    "" | k | keep | s | skip)
      auth_action="skip"
      return
      ;;
    r | reset)
      auth_action="reset"
      return
      ;;
    *)
      echo "Enter reset or skip." >&2
      ;;
    esac
  done
}

setup_mail_auth() {
  local auth_action=$1
  local bridge_mode="login"

  if ((mail_auth_ready)) && [[ $auth_action != "reset" ]]; then
    systemctl --user start protonmail-bridge.service
    if wait_for_bridge 30; then
      echo "Proton Mail Bridge is already authenticated; keeping it."
      return
    fi

    systemctl --user stop protonmail-bridge.service >/dev/null 2>&1 || true
    echo "The existing Proton Mail Bridge account needs authentication."
    echo "At the Bridge prompt: type list, then login <account name or index>,"
    echo "complete authentication, and type exit."
  fi

  systemctl --user stop protonmail-bridge.service >/dev/null 2>&1 || true

  echo ""
  echo "Proton Mail Bridge authentication"
  if ((mail_auth_ready)) && [[ $auth_action == "reset" ]]; then
    bridge_mode="reset"
    echo "At the Bridge prompt:"
    echo "  1. Type list."
    echo "  2. Type delete <account name or index> and confirm the removal."
    echo "  3. Type login and complete authentication."
    echo "  4. Type exit."
  else
    echo "At the Bridge prompt: type login, complete authentication, then type exit."
  fi
  QVOS_PROTON_BRIDGE_MODE="$bridge_mode" protonmail-bridge-core --cli

  systemctl --user start protonmail-bridge.service
  if ! wait_for_bridge 30; then
    echo "Proton Mail Bridge did not expose local IMAP and SMTP listeners." >&2
    return 1
  fi

  echo "Proton Mail Bridge is ready."
}

verify_proton_setup() {
  pass_codex_ready ||
    {
      echo "Proton Pass verification failed." >&2
      return 1
    }
  drive_ready ||
    {
      echo "Proton Drive verification failed." >&2
      return 1
    }
  bridge_ready ||
    {
      echo "Proton Mail Bridge verification failed." >&2
      return 1
    }
}

# Entry point

if (($# > 1)); then
  echo "Usage: proton.sh [--status|--repair|--adopt|--disable]" >&2
  exit 2
fi

case ${1:-} in
"") ;;
--status) mode="status" ;;
--repair) mode="repair" ;;
--adopt) mode="adopt" ;;
--disable) mode="disable" ;;
*)
  echo "Usage: proton.sh [--status|--repair|--adopt|--disable]" >&2
  exit 2
  ;;
esac

if [[ $mode != "install" ]]; then
  inventory_components
  inventory_desktop_integration
  print_desktop_inventory

  if [[ $mode == "status" ]]; then
    ((pass_installed && drive_installed && bridge_installed &&
      account_cli_installed && codex_integration_installed &&
      upload_helper_ready && upload_action_ready && maintenance_ready &&
      drive_desktop_auth_ready))
    exit
  fi

  if [[ $mode == "disable" ]]; then
    disable_desktop_integration
    exit
  fi

  if [[ $mode == "repair" && ! -f $state_file ]]; then
    echo "qvCORE Proton desktop integration is not enabled; nothing was repaired."
    exit 0
  fi

  if ((drive_installed == 0)); then
    echo "Proton Drive is not installed; desktop integration was not changed." >&2
    exit 1
  fi

  if ! drive_ready; then
    echo "Proton Drive cannot access /my-files; authenticate it before enabling the desktop integration." >&2
    exit 1
  fi

  install_codex_integration
  install_desktop_integration
  inventory_components
  inventory_desktop_integration
  print_desktop_inventory
  ((codex_integration_installed && upload_helper_ready &&
    upload_action_ready && maintenance_ready && drive_desktop_auth_ready))
  exit
fi

dependency_packages=()
system_changes_needed=0

inventory_components

for dependency in curl jq openssl; do
  if omarchy-cmd-missing "$dependency"; then
    dependency_packages+=("$dependency")
  fi
done
if omarchy-cmd-missing ss; then
  dependency_packages+=("iproute2")
fi

if ((${#dependency_packages[@]} > 0)) ||
  ((bridge_installed == 0 || account_cli_installed == 0)) ||
  ! vpn_policy_ready ||
  systemctl is-enabled --quiet proton.VPN.service ||
  systemctl is-active --quiet proton.VPN.service; then
  system_changes_needed=1
fi

if ((system_changes_needed)); then
  echo ""
  echo "Authorizing missing Proton system components..."
  sudo -v
fi

if ((${#dependency_packages[@]} > 0)); then
  omarchy-pkg-add "${dependency_packages[@]}"
fi

if ! vpn_policy_ready; then
  install_vpn_on_demand_policy
fi

if ((bridge_installed == 0)); then
  omarchy-pkg-add protonmail-bridge-core
fi

if ((account_cli_installed == 0)); then
  omarchy-pkg-add proton-vpn-cli
fi

if ((pass_installed == 0)); then
  install_pass_cli
fi

if ((drive_installed == 0)); then
  install_drive_cli
fi

if ((codex_integration_installed == 0)); then
  install_codex_integration
fi

if systemctl is-enabled --quiet proton.VPN.service ||
  systemctl is-active --quiet proton.VPN.service; then
  sudo systemctl disable --now proton.VPN.service
fi

if systemctl --user is-enabled --quiet protonmail-bridge.service; then
  systemctl --user disable protonmail-bridge.service
fi

if systemctl is-enabled --quiet proton.VPN.service; then
  echo "Proton VPN daemon is still enabled at boot" >&2
  exit 1
fi

if systemctl --user is-enabled --quiet protonmail-bridge.service; then
  echo "Proton Mail Bridge is still enabled at login" >&2
  exit 1
fi

echo ""
inventory_components
if ((pass_installed == 0 || drive_installed == 0 || bridge_installed == 0 ||
  account_cli_installed == 0 || codex_integration_installed == 0)); then
  echo "Proton component installation is incomplete." >&2
  exit 1
fi

inventory_authentication
choose_auth_action

setup_pass_auth "$auth_action"
setup_drive_auth "$auth_action"
setup_mail_auth "$auth_action"
verify_proton_setup
install_desktop_integration

echo ""
echo "Proton setup is complete:"
echo "  Pass CLI:    pass-cli"
echo "  Drive CLI:   proton-drive"
echo "  Account CLI: protonvpn"
echo "  Mail Bridge: protonmail-bridge-core --cli"
echo "  Bridge run:  systemctl --user start protonmail-bridge.service"
echo "  Codex skill: ~/.codex/skills/proton-cli"
echo "  Codex Pass:  ~/.local/share/qvos-codex/proton-pass"
echo "  Drive upload: Thunar > Upload to Proton Drive"
