#!/bin/bash
set -Eeuo pipefail

component_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install_dir="$HOME/.local/bin"
python_tools_dir="$HOME/.local/share/qvos/dev-tools"
semgrep_binary="$python_tools_dir/semgrep/bin/semgrep"
state_file="$HOME/.local/state/qvos/qvcore/dev"
hook_source="$component_dir/dev/post-update.sh"
hook_target="$HOME/.config/omarchy/hooks/post-update.d/qvos-qvcore-dev"
work_dir=""
update_only=0
use_authenticated_gh=0
failure_context="preflight"
current_step=0
ready_count=0
outdated_count=0
missing_count=0
development_action="install"

component_ids=(
  node
  bun
  mkcert
  hurl
  supabase
  infisical
  cloudflared
  sentry-cli
  act
  sops
  age
  gitleaks
  osv-scanner
  semgrep
  gh
  docker
)
total_components=${#component_ids[@]}
provider_ids=(
  supabase
  infisical
  cloudflared
  sentry-cli
  act
  sops
  age
  gitleaks
  osv-scanner
)

declare -A component_names=(
  [node]="Node.js LTS"
  [bun]="Bun"
  [mkcert]="mkcert"
  [hurl]="Hurl + Hurlfmt"
  [supabase]="Supabase CLI"
  [infisical]="Infisical CLI"
  [cloudflared]="cloudflared"
  [sentry-cli]="Sentry CLI"
  [act]="act"
  [sops]="SOPS"
  [age]="age + age-keygen"
  [gitleaks]="Gitleaks"
  [osv-scanner]="OSV-Scanner"
  [semgrep]="Semgrep"
  [gh]="GitHub CLI"
  [docker]="Docker + Compose"
)
declare -A component_state=()
declare -A component_current=()
declare -A component_latest=()
declare -A mise_expected=()
declare -A provider_display=()
declare -A provider_repository=()
declare -A provider_asset_template=()
declare -A provider_arch=()
declare -A provider_asset_kind=()
declare -A provider_binaries=()
declare -A provider_release_version=()
declare -A provider_asset_name=()
declare -A provider_asset_url=()
declare -A provider_asset_digest=()

cleanup() {
  if [[ -n $work_dir && -d $work_dir ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

report_failure() {
  local status=$?
  local failed_command=$BASH_COMMAND

  trap - ERR
  echo ""
  echo "qvCORE Devel stopped during $failure_context." >&2
  echo "Command failed with exit $status: $failed_command" >&2
  if ((current_step > 0)); then
    echo "Completed components were preserved." >&2
    echo "Run Devel again to verify them and continue from the remaining work." >&2
  else
    echo "No component changes were started." >&2
  fi
  exit "$status"
}
trap report_failure ERR

usage() {
  echo "Usage: dev.sh [--update]" >&2
}

require_command() {
  local command=$1

  if omarchy-cmd-missing "$command"; then
    echo "qvCORE Devel requires the qvOS base command: $command" >&2
    return 1
  fi
}

run_bounded() {
  local duration=$1
  shift

  timeout --foreground --kill-after=5s "$duration" "$@"
}

github_release_metadata() {
  local repository=$1

  if ((use_authenticated_gh)); then
    run_bounded 20s gh api "repos/$repository/releases/latest"
  else
    run_bounded 20s curl \
      --connect-timeout 10 \
      --max-time 20 \
      --retry 2 \
      --retry-delay 1 \
      -fsSL \
      "https://api.github.com/repos/$repository/releases/latest"
  fi
}

ensure_work_dir() {
  if [[ -z $work_dir ]]; then
    work_dir=$(mktemp -d)
  fi
}

binary_version() {
  local binary=$1
  local output

  output=$(run_bounded 15s "$binary" --version 2>&1) || return 1
  if [[ $output =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

register_provider_tools() {
  local act_arch
  local gitleaks_arch
  local release_arch
  local sentry_arch

  case $(uname -m) in
  x86_64 | amd64)
    act_arch="x86_64"
    gitleaks_arch="x64"
    release_arch="amd64"
    sentry_arch="x86_64"
    ;;
  aarch64 | arm64)
    act_arch="arm64"
    gitleaks_arch="arm64"
    release_arch="arm64"
    sentry_arch="aarch64"
    ;;
  *)
    echo "qvCORE Devel does not support architecture: $(uname -m)" >&2
    return 1
    ;;
  esac

  provider_display[supabase]="Supabase CLI"
  provider_repository[supabase]="supabase/cli"
  provider_asset_template[supabase]='supabase_%VERSION%_linux_%ARCH%.tar.gz'
  provider_arch[supabase]=$release_arch
  provider_asset_kind[supabase]="archive"
  provider_binaries[supabase]="supabase"

  provider_display[infisical]="Infisical CLI"
  provider_repository[infisical]="Infisical/cli"
  provider_asset_template[infisical]='cli_%VERSION%_linux_%ARCH%.tar.gz'
  provider_arch[infisical]=$release_arch
  provider_asset_kind[infisical]="archive"
  provider_binaries[infisical]="infisical"

  provider_display[cloudflared]="cloudflared"
  provider_repository[cloudflared]="cloudflare/cloudflared"
  provider_asset_template[cloudflared]='cloudflared-linux-%ARCH%'
  provider_arch[cloudflared]=$release_arch
  provider_asset_kind[cloudflared]="binary"
  provider_binaries[cloudflared]="cloudflared"

  provider_display[sentry-cli]="Sentry CLI"
  provider_repository[sentry-cli]="getsentry/sentry-cli"
  provider_asset_template[sentry-cli]='sentry-cli-Linux-%ARCH%'
  provider_arch[sentry-cli]=$sentry_arch
  provider_asset_kind[sentry-cli]="binary"
  provider_binaries[sentry-cli]="sentry-cli"

  provider_display[act]="act"
  provider_repository[act]="nektos/act"
  provider_asset_template[act]='act_Linux_%ARCH%.tar.gz'
  provider_arch[act]=$act_arch
  provider_asset_kind[act]="archive"
  provider_binaries[act]="act"

  provider_display[sops]="SOPS"
  provider_repository[sops]="getsops/sops"
  provider_asset_template[sops]='sops-v%VERSION%.linux.%ARCH%'
  provider_arch[sops]=$release_arch
  provider_asset_kind[sops]="binary"
  provider_binaries[sops]="sops"

  provider_display[age]="age"
  provider_repository[age]="FiloSottile/age"
  provider_asset_template[age]='age-v%VERSION%-linux-%ARCH%.tar.gz'
  provider_arch[age]=$release_arch
  provider_asset_kind[age]="archive"
  provider_binaries[age]="age age-keygen"

  provider_display[gitleaks]="Gitleaks"
  provider_repository[gitleaks]="gitleaks/gitleaks"
  provider_asset_template[gitleaks]='gitleaks_%VERSION%_linux_%ARCH%.tar.gz'
  provider_arch[gitleaks]=$gitleaks_arch
  provider_asset_kind[gitleaks]="archive"
  provider_binaries[gitleaks]="gitleaks"

  provider_display[osv-scanner]="OSV-Scanner"
  provider_repository[osv-scanner]="google/osv-scanner"
  provider_asset_template[osv-scanner]='osv-scanner_linux_%ARCH%'
  provider_arch[osv-scanner]=$release_arch
  provider_asset_kind[osv-scanner]="binary"
  provider_binaries[osv-scanner]="osv-scanner"
}

resolve_provider_release() {
  local id=$1
  local repository=${provider_repository[$id]}
  local release_json
  local release_tag
  local release_version
  local asset_name
  local asset_info
  local asset_url
  local asset_digest
  local expected_url_prefix="https://github.com/$repository/releases/download/"

  release_json=$(github_release_metadata "$repository")
  release_tag=$(jq -er '.tag_name | select(type == "string" and length > 0)' <<<"$release_json")
  release_version=${release_tag#v}

  if [[ ! $release_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid ${provider_display[$id]} release tag: $release_tag" >&2
    return 1
  fi

  asset_name=${provider_asset_template[$id]//%VERSION%/$release_version}
  asset_name=${asset_name//%ARCH%/${provider_arch[$id]}}
  asset_info=$(
    jq -er --arg asset "$asset_name" '
      .assets[]
      | select(.name == $asset)
      | [(.browser_download_url // ""), (.digest // "")]
      | @tsv
    ' <<<"$release_json"
  )
  IFS=$'\t' read -r asset_url asset_digest <<<"$asset_info"

  if [[ $asset_url != $expected_url_prefix* ]] ||
    [[ ! $asset_digest =~ ^sha256:[[:xdigit:]]{64}$ ]]; then
    echo "Release $release_tag does not expose a verified $asset_name asset" >&2
    return 1
  fi

  provider_release_version[$id]=$release_version
  provider_asset_name[$id]=$asset_name
  provider_asset_url[$id]=$asset_url
  provider_asset_digest[$id]=$asset_digest
  component_latest[$id]=$release_version
}

find_release_binary() {
  local extract_dir=$1
  local binary=$2
  local candidates=()

  mapfile -t candidates < <(find "$extract_dir" -type f -name "$binary" -print)
  if ((${#candidates[@]} != 1)); then
    echo "Expected one $binary binary in the verified release archive" >&2
    return 1
  fi

  printf '%s\n' "${candidates[0]}"
}

install_verified_release() {
  local id=$1
  local release_version=${provider_release_version[$id]}
  local asset_name=${provider_asset_name[$id]}
  local asset_url=${provider_asset_url[$id]}
  local asset_digest=${provider_asset_digest[$id]}
  local expected_digest=${asset_digest#sha256:}
  local actual_digest
  local tool_work_dir
  local download_path
  local extract_dir=""
  local primary_binary
  local primary_candidate
  local candidate_version
  local binary
  local candidate
  local target
  local pending
  local binaries=()

  read -r -a binaries <<<"${provider_binaries[$id]}"
  primary_binary=${binaries[0]}

  ensure_work_dir
  tool_work_dir="$work_dir/$id"
  download_path="$tool_work_dir/$asset_name"
  install -d "$tool_work_dir"
  run_bounded 300s curl \
    --connect-timeout 15 \
    --max-time 300 \
    --retry 3 \
    --retry-delay 1 \
    --silent \
    --show-error \
    -fL \
    -o "$download_path" \
    "$asset_url"

  actual_digest=$(sha256sum "$download_path" | awk '{print $1}')
  if [[ $actual_digest != "$expected_digest" ]]; then
    echo "${provider_display[$id]} release checksum verification failed" >&2
    return 1
  fi

  if [[ ${provider_asset_kind[$id]} == "archive" ]]; then
    extract_dir="$tool_work_dir/extracted"
    install -d "$extract_dir"
    tar -xzf "$download_path" -C "$extract_dir"
    primary_candidate=$(find_release_binary "$extract_dir" "$primary_binary")
  elif [[ ${provider_asset_kind[$id]} == "binary" ]]; then
    primary_candidate=$download_path
  else
    echo "Unsupported ${provider_display[$id]} release asset kind" >&2
    return 1
  fi

  chmod 0755 "$primary_candidate"
  candidate_version=$(binary_version "$primary_candidate") || {
    echo "Could not verify the ${provider_display[$id]} binary version" >&2
    return 1
  }
  if [[ $candidate_version != "$release_version" ]]; then
    echo "${provider_display[$id]} binary reports $candidate_version, expected $release_version" >&2
    return 1
  fi

  install -d -m 0755 "$install_dir"
  for binary in "${binaries[@]}"; do
    if [[ $binary == "$primary_binary" ]]; then
      candidate=$primary_candidate
    else
      candidate=$(find_release_binary "$extract_dir" "$binary")
    fi

    target="$install_dir/$binary"
    pending="$target.next.$$"
    install -m 0755 "$candidate" "$pending"
    mv -f "$pending" "$target"
  done
}

resolve_expected_versions() {
  local id

  echo "Checking the latest Devel component versions..."

  mise_expected[node]=$(run_bounded 30s mise latest node@lts)
  mise_expected[bun]=$(run_bounded 30s mise latest bun)
  mise_expected[mkcert]=$(run_bounded 30s mise latest aqua:FiloSottile/mkcert)
  mise_expected[hurl]=$(run_bounded 30s mise latest cargo:hurl)
  mise_expected[hurlfmt]=$(run_bounded 30s mise latest cargo:hurlfmt)
  mise_expected[semgrep]=$(run_bounded 30s mise latest pipx:semgrep)

  component_latest[node]=${mise_expected[node]}
  component_latest[bun]=${mise_expected[bun]}
  component_latest[mkcert]=${mise_expected[mkcert]}
  if [[ ${mise_expected[hurl]} == "${mise_expected[hurlfmt]}" ]]; then
    component_latest[hurl]=${mise_expected[hurl]}
  else
    component_latest[hurl]="${mise_expected[hurl]} / ${mise_expected[hurlfmt]}"
  fi
  component_latest[semgrep]=${mise_expected[semgrep]}

  for id in "${provider_ids[@]}"; do
    resolve_provider_release "$id"
  done

  component_latest[gh]="qvOS base"
  component_latest[docker]="qvOS base"
}

mise_current_version() {
  local tool=$1

  run_bounded 15s mise current "$tool" 2>/dev/null |
    awk 'NR == 1 { print $1 }'
}

inspect_mise_component() {
  local id=$1
  local current
  local current_key=$id
  local secondary

  case $id in
  node | bun | mkcert)
    if [[ $id == "mkcert" ]]; then
      current_key="aqua:FiloSottile/mkcert"
    fi
    current=$(mise_current_version "$current_key" || true)
    component_current[$id]=${current:-unknown}
    if [[ -z $current ]] ||
      ! run_bounded 15s mise which "$id" >/dev/null 2>&1; then
      component_state[$id]="missing"
    elif [[ $current == "${mise_expected[$id]}" ]]; then
      component_state[$id]="ready"
    else
      component_state[$id]="outdated"
    fi
    ;;
  semgrep)
    current=$(binary_version "$install_dir/semgrep" 2>/dev/null || true)
    component_current[$id]=${current:-unknown}
    if [[ ! -x $semgrep_binary ]] ||
      [[ ! -x $install_dir/semgrep ]] ||
      [[ ! $install_dir/semgrep -ef $semgrep_binary ]]; then
      component_state[$id]="missing"
    elif [[ $current == "${mise_expected[semgrep]}" ]]; then
      component_state[$id]="ready"
    else
      component_state[$id]="outdated"
    fi
    ;;
  hurl)
    current=$(mise_current_version cargo:hurl || true)
    secondary=$(mise_current_version cargo:hurlfmt || true)
    component_current[$id]="${current:-missing} / ${secondary:-missing}"
    if [[ -z $current || -z $secondary ]] ||
      ! run_bounded 15s mise which hurl >/dev/null 2>&1 ||
      ! run_bounded 15s mise which hurlfmt >/dev/null 2>&1; then
      component_state[$id]="missing"
    elif [[ $current == "${mise_expected[hurl]}" &&
      $secondary == "${mise_expected[hurlfmt]}" ]]; then
      component_state[$id]="ready"
    else
      component_state[$id]="outdated"
    fi
    ;;
  esac
}

inspect_provider_component() {
  local id=$1
  local binary
  local current
  local all_current=1
  local first_version=""
  local index
  local binaries=()
  local versions=()

  read -r -a binaries <<<"${provider_binaries[$id]}"
  component_current[$id]="missing"

  for binary in "${binaries[@]}"; do
    if [[ ! -x $install_dir/$binary ]]; then
      component_state[$id]="missing"
      return
    fi

    current=$(binary_version "$install_dir/$binary" 2>/dev/null || true)
    versions+=("$binary ${current:-unknown}")
    [[ -n $first_version ]] || first_version=${current:-unknown}
    if [[ $current != "${provider_release_version[$id]}" ]]; then
      all_current=0
    fi
  done

  if ((${#binaries[@]} == 1)); then
    component_current[$id]=$first_version
  else
    component_current[$id]=${versions[0]}
    for ((index = 1; index < ${#versions[@]}; index++)); do
      component_current[$id]+=" / ${versions[$index]}"
    done
  fi

  if ((all_current)); then
    component_state[$id]="ready"
  else
    component_state[$id]="outdated"
  fi
}

inspect_base_component() {
  local id=$1
  local current

  case $id in
  gh)
    current=$(binary_version "$(command -v gh 2>/dev/null)" 2>/dev/null || true)
    if omarchy-cmd-present gh && [[ -n $current ]]; then
      component_state[$id]="ready"
      component_current[$id]=$current
    else
      component_state[$id]="missing"
      component_current[$id]="missing"
    fi
    ;;
  docker)
    current=$(binary_version "$(command -v docker 2>/dev/null)" 2>/dev/null || true)
    if omarchy-cmd-present docker &&
      run_bounded 15s docker compose version >/dev/null 2>&1 &&
      [[ -n $current ]]; then
      component_state[$id]="ready"
      component_current[$id]=$current
    else
      component_state[$id]="missing"
      component_current[$id]="missing"
    fi
    ;;
  esac
}

inspect_component() {
  local id=$1

  case $id in
  node | bun | mkcert | hurl | semgrep)
    inspect_mise_component "$id"
    ;;
  supabase | infisical | cloudflared | sentry-cli | act | sops | age | gitleaks | osv-scanner)
    inspect_provider_component "$id"
    ;;
  gh | docker)
    inspect_base_component "$id"
    ;;
  esac
}

inventory_components() {
  local id

  ready_count=0
  outdated_count=0
  missing_count=0

  for id in "${component_ids[@]}"; do
    inspect_component "$id"
    case ${component_state[$id]} in
    ready)
      ready_count=$((ready_count + 1))
      ;;
    outdated)
      outdated_count=$((outdated_count + 1))
      ;;
    missing)
      missing_count=$((missing_count + 1))
      ;;
    esac
  done
}

component_status_label() {
  local id=$1

  case ${component_state[$id]} in
  ready)
    printf 'ready (%s)\n' "${component_current[$id]}"
    ;;
  outdated)
    printf 'outdated (%s -> %s)\n' \
      "${component_current[$id]}" "${component_latest[$id]}"
    ;;
  missing)
    if [[ $id == "gh" || $id == "docker" ]]; then
      printf 'missing (qvOS base)\n'
    else
      printf 'missing (latest %s)\n' "${component_latest[$id]}"
    fi
    ;;
  esac
}

print_inventory() {
  local id

  echo ""
  echo "qvCORE Devel inventory: $ready_count/$total_components ready"
  echo "  Outdated: $outdated_count"
  echo "  Missing:  $missing_count"
  echo ""
  for id in "${component_ids[@]}"; do
    printf '  %-20s %s\n' \
      "${component_names[$id]}" \
      "$(component_status_label "$id")"
  done
}

choose_development_action() {
  local choice

  if [[ ${component_state[gh]} == "missing" ||
    ${component_state[docker]} == "missing" ]]; then
    echo ""
    echo "Restore the missing qvOS base components before continuing:" >&2
    [[ ${component_state[gh]} == "missing" ]] && echo "  GitHub CLI" >&2
    [[ ${component_state[docker]} == "missing" ]] && echo "  Docker + Compose" >&2
    return 1
  fi

  if ((ready_count == total_components)); then
    echo ""
    echo "All $total_components Devel components are current; no changes are needed."
    development_action="keep"
    return
  fi

  echo ""
  if ((update_only)); then
    echo "Automatic Devel refresh:"
  else
    echo "Devel changes:"
  fi
  printf '  install %d missing component(s)\n' "$missing_count"
  printf '  update  %d outdated component(s)\n' "$outdated_count"
  printf '  keep    %d ready component(s)\n' "$ready_count"
  echo "  accounts, credentials, and project files remain unchanged"

  if ((update_only)); then
    development_action="install"
    return
  fi

  while true; do
    printf 'Choose install or cancel [install]: ' >&2
    if ! IFS= read -r choice; then
      choice="install"
    fi

    case ${choice,,} in
    "" | i | install | y | yes)
      development_action="install"
      return
      ;;
    c | cancel | n | no)
      development_action="cancel"
      echo "Devel changes canceled; no components were modified."
      return
      ;;
    *)
      echo "Enter install or cancel." >&2
      ;;
    esac
  done
}

install_mise_component() {
  local id=$1

  case $id in
  node)
    omarchy-install-dev-env node
    ;;
  bun)
    omarchy-install-dev-env bun
    ;;
  mkcert)
    mise use -g aqua:FiloSottile/mkcert@latest
    ;;
  hurl)
    mise use -g cargo:hurl@latest
    mise use -g cargo:hurlfmt@latest
    ;;
  semgrep)
    UV_TOOL_DIR="$python_tools_dir" \
      UV_TOOL_BIN_DIR="$install_dir" \
      mise x uv@latest -- \
      uv tool install --force --managed-python \
      "semgrep==${mise_expected[semgrep]}"
    ;;
  esac
}

apply_component_changes() {
  local id
  local action

  current_step=0
  for id in "${component_ids[@]}"; do
    current_step=$((current_step + 1))
    failure_context="[$current_step/$total_components] ${component_names[$id]}"

    if [[ ${component_state[$id]} == "ready" ]]; then
      printf '[%02d/%d] %-20s ready (%s)\n' \
        "$current_step" "$total_components" \
        "${component_names[$id]}" "${component_current[$id]}"
      continue
    fi

    if [[ ${component_state[$id]} == "missing" ]]; then
      action="installing"
    else
      action="updating"
    fi
    printf '[%02d/%d] %-20s %s %s\n' \
      "$current_step" "$total_components" \
      "${component_names[$id]}" "$action" "${component_latest[$id]}"

    case $id in
    node | bun | mkcert | hurl | semgrep)
      install_mise_component "$id"
      ;;
    supabase | infisical | cloudflared | sentry-cli | act | sops | age | gitleaks | osv-scanner)
      install_verified_release "$id"
      ;;
    gh | docker)
      echo "${component_names[$id]} must be restored through the qvOS base system." >&2
      return 1
      ;;
    esac

    inspect_component "$id"
    if [[ ${component_state[$id]} != "ready" ]]; then
      echo "${component_names[$id]} did not pass its post-install verification." >&2
      return 1
    fi
    printf '         %-20s verified (%s)\n' \
      "${component_names[$id]}" "${component_current[$id]}"
  done
}

install_update_hook() {
  if [[ ! -f $hook_source ]]; then
    echo "Missing qvCORE Devel update hook: $hook_source" >&2
    return 1
  fi

  install -D -m 0644 "$hook_source" "$hook_target"
}

if (($# > 1)); then
  usage
  exit 1
fi

case ${1:-} in
"")
  ;;
--update)
  update_only=1
  ;;
*)
  usage
  exit 1
  ;;
esac

for required_command in curl jq tar sha256sum awk find mise timeout; do
  require_command "$required_command"
done

if omarchy-cmd-present gh &&
  run_bounded 15s gh auth status --hostname github.com >/dev/null 2>&1; then
  use_authenticated_gh=1
fi

register_provider_tools
resolve_expected_versions
inventory_components
print_inventory
choose_development_action

if [[ $development_action == "cancel" ]]; then
  exit 130
fi

if [[ $development_action == "install" ]]; then
  echo ""
  echo "Applying qvCORE Devel changes..."
  apply_component_changes

  failure_context="final verification"
  inventory_components
  print_inventory
fi

if ((ready_count != total_components)); then
  echo "qvCORE Devel is incomplete." >&2
  exit 1
fi

failure_context="update-hook installation"
install_update_hook
if ((update_only == 0)); then
  install -D -m 0644 /dev/null "$state_file"
fi

echo ""
if ((update_only)); then
  echo "qvCORE Devel refresh is complete: $ready_count/$total_components ready."
else
  echo "Project-pinned tools:"
  echo "  bun add -d wrangler@latest && bunx wrangler --version"
  echo "  bun add convex && bunx convex --version"
  echo ""
  echo "qvCORE Devel is ready: $ready_count/$total_components."
fi
