#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
test_home="$test_root/home"
test_omarchy_path="$test_root/omarchy"
release_root="$test_root/releases"
action_log="$test_root/actions"
network_log="$test_root/network"
timeout_log="$test_root/timeouts"
mise_state="$test_root/mise-state"
install_output="$test_root/install-output"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

create_fake_binary() {
  local path=$1
  local label=$2
  local version=$3

  install -D -m 0755 /dev/stdin "$path" <<SCRIPT
#!/bin/bash
printf '%s\n' "$label $version"
SCRIPT
}

set_mise_state() {
  local key=$1
  local version=$2
  local pending="$mise_state.next"

  awk -v key="$key" '$1 != key' "$mise_state" >"$pending"
  printf '%s %s\n' "$key" "$version" >>"$pending"
  mv "$pending" "$mise_state"
}

drop_mise_state() {
  local key=$1
  local pending="$mise_state.next"

  awk -v key="$key" '$1 != key' "$mise_state" >"$pending"
  mv "$pending" "$mise_state"
}

write_release_metadata() {
  local repository=$1
  local tag=$2
  local asset=$3
  local repository_dir="$release_root/$repository"
  local digest
  local release_file="$repository_dir/release.json"
  local pending="$repository_dir/release.json.next"

  digest=$(sha256sum "$repository_dir/$asset" | awk '{print $1}')
  if [[ -f $release_file ]]; then
    jq \
      --arg tag "$tag" \
      --arg asset "$asset" \
      --arg url "https://github.com/$repository/releases/download/$tag/$asset" \
      --arg digest "sha256:$digest" \
      '
        select(.tag_name == $tag)
        | .assets += [{
            name: $asset,
            browser_download_url: $url,
            digest: $digest
          }]
      ' "$release_file" >"$pending"
    mv "$pending" "$release_file"
  else
    jq -n \
      --arg tag "$tag" \
      --arg asset "$asset" \
      --arg url "https://github.com/$repository/releases/download/$tag/$asset" \
      --arg digest "sha256:$digest" \
      '{
        tag_name: $tag,
        assets: [{
          name: $asset,
          browser_download_url: $url,
          digest: $digest
        }]
      }' >"$release_file"
  fi
}

create_archive_release() {
  local repository=$1
  local tag=$2
  local asset=$3
  local version=$4
  shift 4
  local repository_dir="$release_root/$repository"
  local payload_dir="$repository_dir/payload"
  local binary

  install -d "$payload_dir/bin"
  for binary in "$@"; do
    create_fake_binary "$payload_dir/bin/$binary" "$binary" "$version"
  done
  tar -czf "$repository_dir/$asset" -C "$payload_dir" .
  write_release_metadata "$repository" "$tag" "$asset"
}

create_binary_release() {
  local repository=$1
  local tag=$2
  local asset=$3
  local binary=$4
  local version=$5
  local repository_dir="$release_root/$repository"

  install -d "$repository_dir"
  create_fake_binary "$repository_dir/$asset" "$binary" "$version"
  write_release_metadata "$repository" "$tag" "$asset"
}

install -d "$test_bin" "$test_home" "$test_omarchy_path/qv/core"
install -m 0755 "$root/qv/core/dev.sh" "$test_omarchy_path/qv/core/dev.sh"

create_archive_release \
  supabase/cli v1.2.3 supabase_1.2.3_linux_amd64.tar.gz 1.2.3 \
  supabase
create_archive_release \
  Infisical/cli v2.3.4 cli_2.3.4_linux_amd64.tar.gz 2.3.4 \
  infisical
create_binary_release \
  cloudflare/cloudflared 2026.1.2 cloudflared-linux-amd64 \
  cloudflared 2026.1.2
create_binary_release \
  getsentry/sentry-cli 3.4.5 sentry-cli-Linux-x86_64 \
  sentry-cli 3.4.5
create_archive_release \
  nektos/act v0.2.99 act_Linux_x86_64.tar.gz 0.2.99 \
  act
create_binary_release \
  getsops/sops v3.12.3 sops-v3.12.3.linux.amd64 \
  sops 3.12.3
create_archive_release \
  FiloSottile/age v1.3.2 age-v1.3.2-linux-amd64.tar.gz 1.3.2 \
  age age-keygen
create_archive_release \
  gitleaks/gitleaks v8.30.1 gitleaks_8.30.1_linux_x64.tar.gz 8.30.1 \
  gitleaks
create_binary_release \
  google/osv-scanner v2.4.0 osv-scanner_linux_amd64 \
  osv-scanner 2.4.0

create_archive_release \
  supabase/cli v1.2.3 supabase_1.2.3_linux_arm64.tar.gz 1.2.3 \
  supabase
create_archive_release \
  Infisical/cli v2.3.4 cli_2.3.4_linux_arm64.tar.gz 2.3.4 \
  infisical
create_binary_release \
  cloudflare/cloudflared 2026.1.2 cloudflared-linux-arm64 \
  cloudflared 2026.1.2
create_binary_release \
  getsentry/sentry-cli 3.4.5 sentry-cli-Linux-aarch64 \
  sentry-cli 3.4.5
create_archive_release \
  nektos/act v0.2.99 act_Linux_arm64.tar.gz 0.2.99 \
  act
create_binary_release \
  getsops/sops v3.12.3 sops-v3.12.3.linux.arm64 \
  sops 3.12.3
create_archive_release \
  FiloSottile/age v1.3.2 age-v1.3.2-linux-arm64.tar.gz 1.3.2 \
  age age-keygen
create_archive_release \
  gitleaks/gitleaks v8.30.1 gitleaks_8.30.1_linux_arm64.tar.gz 8.30.1 \
  gitleaks
create_binary_release \
  google/osv-scanner v2.4.0 osv-scanner_linux_arm64 \
  osv-scanner 2.4.0

: >"$mise_state"
set_mise_state node 24.18.0
set_mise_state bun 1.3.14

create_fake_binary "$test_bin/node" node 24.18.0
create_fake_binary "$test_bin/bun" bun 1.3.14
create_fake_binary "$test_bin/mkcert" mkcert 1.4.4
create_fake_binary "$test_bin/hurl" hurl 8.1.2
create_fake_binary "$test_bin/hurlfmt" hurlfmt 8.1.2
create_fake_binary "$test_bin/semgrep" semgrep 1.171.0
create_fake_binary "$test_home/.local/bin/semgrep" semgrep 1.0.0

install -m 0755 /dev/stdin "$test_bin/uname" <<'SCRIPT'
#!/bin/bash
if [[ ${1:-} == "-m" ]]; then
  printf '%s\n' "${QVOS_TEST_ARCH:-x86_64}"
else
  /usr/bin/uname "$@"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/timeout" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

[[ $1 == "--foreground" ]]
shift
[[ $1 == "--kill-after=5s" ]]
shift
duration=$1
shift

printf '%s\t%s\n' "$duration" "$*" >>"$QVOS_TEST_TIMEOUT_LOG"
"$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-install-dev-env" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

set_state() {
  local key=$1
  local version=$2
  local pending="$QVOS_TEST_MISE_STATE.next"

  awk -v key="$key" '$1 != key' "$QVOS_TEST_MISE_STATE" >"$pending"
  printf '%s %s\n' "$key" "$version" >>"$pending"
  mv "$pending" "$QVOS_TEST_MISE_STATE"
}

printf 'dev-env\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
case $1 in
node)
  set_state node 24.18.0
  ;;
bun)
  set_state bun 1.3.14
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/mise" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

latest_version() {
  case $1 in
  node@lts) echo "24.18.0" ;;
  bun) echo "1.3.14" ;;
  aqua:FiloSottile/mkcert) echo "1.4.4" ;;
  cargo:hurl | cargo:hurlfmt) echo "8.1.2" ;;
  pipx:semgrep) echo "1.171.0" ;;
  *) exit 1 ;;
  esac
}

state_key_for_command() {
  case $1 in
  node | bun) echo "$1" ;;
  mkcert) echo "aqua:FiloSottile/mkcert" ;;
  hurl) echo "cargo:hurl" ;;
  hurlfmt) echo "cargo:hurlfmt" ;;
  *) exit 1 ;;
  esac
}

set_state() {
  local key=$1
  local version=$2
  local pending="$QVOS_TEST_MISE_STATE.next"

  awk -v key="$key" '$1 != key' "$QVOS_TEST_MISE_STATE" >"$pending"
  printf '%s %s\n' "$key" "$version" >>"$pending"
  mv "$pending" "$QVOS_TEST_MISE_STATE"
}

case $1 in
latest)
  latest_version "$2"
  ;;
current)
  awk -v key="$2" '$1 == key { print $2; found=1 } END { exit !found }' \
    "$QVOS_TEST_MISE_STATE"
  ;;
which)
  key=$(state_key_for_command "$2")
  grep -q "^$key " "$QVOS_TEST_MISE_STATE"
  printf '%s/%s\n' "$QVOS_TEST_BIN" "$2"
  ;;
use)
  printf 'mise\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  ref=${*: -1}
  case $ref in
  aqua:FiloSottile/mkcert@latest)
    set_state aqua:FiloSottile/mkcert 1.4.4
    ;;
  cargo:hurl@latest)
    set_state cargo:hurl 8.1.2
    ;;
  cargo:hurlfmt@latest)
    set_state cargo:hurlfmt 8.1.2
    ;;
  *)
    exit 1
    ;;
  esac
  ;;
x)
  printf 'mise\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  [[ $2 == "uv@latest" ]]
  [[ $3 == "--" ]]
  [[ $4 == "uv" ]]
  [[ $5 == "tool" ]]
  [[ $6 == "install" ]]
  [[ ${*: -1} == "semgrep==1.171.0" ]]
  install -d "$UV_TOOL_DIR/semgrep/bin" "$UV_TOOL_BIN_DIR"
  ln -s "$QVOS_TEST_BIN/semgrep" "$UV_TOOL_DIR/semgrep/bin/semgrep"
  pending="$UV_TOOL_BIN_DIR/semgrep.next"
  ln -s "$UV_TOOL_DIR/semgrep/bin/semgrep" "$pending"
  mv -f "$pending" "$UV_TOOL_BIN_DIR/semgrep"
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
if [[ $1 == "docker" && ${QVOS_TEST_DOCKER_MISSING:-0} == "1" ]]; then
  exit 1
fi
command -v "$1" >/dev/null 2>&1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
! command -v "$1" >/dev/null 2>&1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/docker" <<'SCRIPT'
#!/bin/bash
case $1 in
--version)
  printf 'Docker version 29.6.2\n'
  ;;
compose)
  [[ $2 == "version" ]]
  printf 'Docker Compose version 5.3.1\n'
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gh" <<'SCRIPT'
#!/bin/bash
case $1 in
auth)
  [[ ${QVOS_TEST_GH_AUTH:-0} == "1" ]]
  ;;
api)
  repository=${2#repos/}
  repository=${repository%/releases/latest}
  printf 'metadata-gh\t%s\n' "$repository" >>"$QVOS_TEST_NETWORK_LOG"
  cat "$QVOS_TEST_RELEASE_ROOT/$repository/release.json"
  ;;
--version)
  printf 'gh version 2.96.0\n'
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
output=""
url=""

while (($#)); do
  case $1 in
  -o)
    output=$2
    shift 2
    ;;
  http://* | https://*)
    url=$1
    shift
    ;;
  *)
    shift
    ;;
  esac
done

if [[ $url == "https://api.github.com/repos/"*"/releases/latest" ]]; then
  repository=${url#https://api.github.com/repos/}
  repository=${repository%/releases/latest}
  printf 'metadata-curl\t%s\n' "$repository" >>"$QVOS_TEST_NETWORK_LOG"
  cat "$QVOS_TEST_RELEASE_ROOT/$repository/release.json"
  exit
fi

repository=${url#https://github.com/}
repository=${repository%%/releases/download/*}
asset=${url##*/}
printf 'download\t%s\t%s\n' "$repository" "$asset" >>"$QVOS_TEST_NETWORK_LOG"
cp "$QVOS_TEST_RELEASE_ROOT/$repository/$asset" "$output"
SCRIPT

run_dev() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_NETWORK_LOG="$network_log" \
    QVOS_TEST_TIMEOUT_LOG="$timeout_log" \
    QVOS_TEST_RELEASE_ROOT="$release_root" \
    QVOS_TEST_ARCH="${QVOS_TEST_ARCH:-x86_64}" \
    QVOS_TEST_GH_AUTH="${QVOS_TEST_GH_AUTH:-0}" \
    QVOS_TEST_DOCKER_MISSING="${QVOS_TEST_DOCKER_MISSING:-0}" \
    QVOS_TEST_MISE_STATE="$mise_state" \
    QVOS_TEST_BIN="$test_bin" \
    HOME="$test_home" \
    OMARCHY_PATH="$test_omarchy_path" \
    PATH="$test_home/.local/bin:$test_bin:/usr/bin" \
    "$test_omarchy_path/qv/core/dev.sh" "$@"
}

: >"$action_log"
: >"$network_log"
: >"$timeout_log"
set +e
cancel_output=$(printf 'cancel\n' | QVOS_TEST_GH_AUTH=1 run_dev 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) || fail "cancellation status"
grep -Fq 'qvCORE Devel inventory: 4/16 ready' <<<"$cancel_output" ||
  fail "four-component initial inventory"
grep -Fq 'Outdated: 0' <<<"$cancel_output" || fail "fresh outdated count"
grep -Fq 'Missing:  12' <<<"$cancel_output" || fail "fresh missing count"
grep -Fq 'Devel changes canceled; no components were modified.' <<<"$cancel_output" ||
  fail "explicit cancellation"
[[ ! -s $action_log ]] || fail "cancellation performs tool actions"
if grep -q '^download' "$network_log"; then
  fail "cancellation downloads provider binaries"
fi
[[ ! -e $test_home/.local/state/qvos/qvcore/dev ]] ||
  fail "cancellation writes completion state"
[[ $("$test_home/.local/bin/semgrep" --version) == "semgrep 1.0.0" ]] ||
  fail "cancellation replaces unmanaged Semgrep"
pass "qvCORE previews a 4/16 inventory and cancels without changes"

: >"$action_log"
: >"$network_log"
: >"$timeout_log"
printf '\n' | QVOS_TEST_GH_AUTH=1 run_dev >"$install_output"

expected_actions=$'mise\tuse -g aqua:FiloSottile/mkcert@latest\nmise\tuse -g cargo:hurl@latest\nmise\tuse -g cargo:hurlfmt@latest\nmise\tx uv@latest -- uv tool install --force --managed-python semgrep==1.171.0'
[[ $(<"$action_log") == "$expected_actions" ]] ||
  fail "ready runtimes are preserved while missing mise tools install"
[[ $(grep -c '^metadata-gh' "$network_log") == "9" ]] ||
  fail "authenticated GitHub metadata route"
[[ $(grep -c '^download' "$network_log") == "9" ]] ||
  fail "verified provider downloads"
grep -Fq $'20s\tgh api repos/supabase/cli/releases/latest' "$timeout_log" ||
  fail "bounded provider metadata discovery"
grep -Fq $'300s\tcurl --connect-timeout 15 --max-time 300' "$timeout_log" ||
  fail "bounded provider download"
grep -Fq '[01/16] Node.js LTS          ready (24.18.0)' "$install_output" ||
  fail "numbered ready progress"
grep -Fq '[16/16] Docker + Compose     ready (29.6.2)' "$install_output" ||
  fail "complete numbered progress"
grep -Fq 'qvCORE Devel inventory: 16/16 ready' "$install_output" ||
  fail "verified final inventory"
grep -Fq 'qvCORE Devel is ready: 16/16.' "$install_output" ||
  fail "verified completion result"

declare -A expected_versions=(
  [supabase]="supabase 1.2.3"
  [infisical]="infisical 2.3.4"
  [cloudflared]="cloudflared 2026.1.2"
  [sentry-cli]="sentry-cli 3.4.5"
  [act]="act 0.2.99"
  [sops]="sops 3.12.3"
  [age]="age 1.3.2"
  [age-keygen]="age-keygen 1.3.2"
  [gitleaks]="gitleaks 8.30.1"
  [osv-scanner]="osv-scanner 2.4.0"
)

for command in "${!expected_versions[@]}"; do
  [[ $("$test_home/.local/bin/$command" --version) == "${expected_versions[$command]}" ]] ||
    fail "$command verified installation"
done
[[ $test_home/.local/bin/semgrep -ef $test_bin/semgrep ]] ||
  fail "Semgrep provider executable ownership"
[[ $test_home/.local/bin/semgrep -ef $test_home/.local/share/qvos/dev-tools/semgrep/bin/semgrep ]] ||
  fail "Semgrep isolated tool ownership"
[[ $("$test_home/.local/bin/semgrep" --version) == "semgrep 1.171.0" ]] ||
  fail "Semgrep verified installation"
pass "qvCORE installs only missing components with verified provider releases"

state_file="$test_home/.local/state/qvos/qvcore/dev"
[[ -f $state_file ]] || fail "Devel opt-in state"
grep -Fq 'bun add -d wrangler@latest' "$install_output" ||
  fail "project-local Wrangler guidance"
grep -Fq 'bun add convex' "$install_output" ||
  fail "project-local Convex guidance"
pass "qvCORE keeps Wrangler and Convex project-pinned"

run_dev --status
repair_output=$(run_dev --repair)
grep -Fq 'installed tools were preserved' <<<"$repair_output" ||
  fail "Devel repair preservation result"

disable_output=$(run_dev --disable)
[[ ! -e $state_file ]] ||
  fail "Devel lifecycle disable"
[[ -x $test_home/.local/bin/supabase ]] ||
  fail "Devel disable removed an installed tool"
grep -Fq 'installed tools remain available' <<<"$disable_output" ||
  fail "Devel disable preservation result"
run_dev --repair >/dev/null
adopt_output=$(run_dev --adopt)
[[ -f $state_file ]] || fail "Devel lifecycle adoption state"
grep -Fq 'adopted the installed development tools' <<<"$adopt_output" ||
  fail "Devel adoption result"
pass "qvCORE Devel lifecycle preserves installed tools"

: >"$action_log"
: >"$network_log"
: >"$timeout_log"
current_output=$(
  QVOS_TEST_GH_AUTH=0 run_dev --update
)
grep -Fq 'qvCORE Devel inventory: 14/16 ready' <<<"$current_output" ||
  fail "current update inventory"
grep -Fq 'All 14 tracked Devel component(s) are current; no changes are needed.' \
  <<<"$current_output" ||
  fail "current update no-op"
grep -Fq 'qvCORE Devel refresh is complete: 14 tracked component(s) current.' \
  <<<"$current_output" ||
  fail "current update completion"
[[ ! -s $action_log ]] || fail "current update performs mise actions"
[[ $(grep -c '^metadata-curl' "$network_log") == "9" ]] ||
  fail "anonymous metadata fallback"
grep -Fq $'20s\tcurl --connect-timeout 10 --max-time 20' "$timeout_log" ||
  fail "bounded anonymous metadata fallback"
if grep -q '^download' "$network_log"; then
  fail "current provider tools downloaded again"
fi
pass "post-update refresh inventories and preserves current components"

rm -f "$test_home/.local/bin/supabase"
: >"$action_log"
: >"$network_log"
: >"$timeout_log"
removed_output=$(QVOS_TEST_GH_AUTH=1 run_dev --update)
[[ ! -e $test_home/.local/bin/supabase ]] ||
  fail "Devel refresh reinstalls a removed component"
[[ $(grep -c '^metadata-gh' "$network_log") == "8" ]] ||
  fail "Devel refresh checks a removed provider component"
if grep -q '^download' "$network_log"; then
  fail "Devel refresh downloads a removed provider component"
fi
grep -Fq 'qvCORE Devel refresh is complete: 13 tracked component(s) current.' \
  <<<"$removed_output" ||
  fail "removed Devel component tracking result"
pass "post-update refresh respects intentionally removed Devel components"

create_fake_binary "$test_home/.local/bin/supabase" supabase 1.2.3
drop_mise_state node
set_mise_state bun 0.9.0
drop_mise_state cargo:hurlfmt
create_fake_binary "$test_home/.local/bin/supabase" supabase 0.0.0
cp "$release_root/supabase/cli/release.json" "$test_root/supabase-release.json"
jq '.assets[0].digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
  "$test_root/supabase-release.json" >"$release_root/supabase/cli/release.json"

: >"$action_log"
: >"$network_log"
: >"$timeout_log"
set +e
interrupted_output=$(QVOS_TEST_GH_AUTH=1 run_dev --update 2>&1)
interrupted_status=$?
set -e
((interrupted_status != 0)) || fail "tampered provider update succeeds"
grep -Fq 'qvCORE Devel inventory: 10/16 ready' <<<"$interrupted_output" ||
  fail "partial ready inventory"
grep -Fq 'Outdated: 2' <<<"$interrupted_output" ||
  fail "partial outdated inventory"
grep -Fq 'Missing:  4' <<<"$interrupted_output" ||
  fail "partial missing inventory"
grep -Fq 'qvCORE Devel stopped during [5/16] Supabase CLI.' \
  <<<"$interrupted_output" ||
  fail "interrupted step report"
grep -Fq 'Completed components were preserved.' <<<"$interrupted_output" ||
  fail "interrupted resume guidance"
if grep -Fq 'node ' "$mise_state"; then
  fail "interrupted refresh reinstalls removed Node.js"
fi
grep -Fq 'bun 1.3.14' "$mise_state" || fail "interrupted Bun update preserved"
grep -Fq 'cargo:hurlfmt 8.1.2' "$mise_state" ||
  fail "interrupted Hurl component update preserved"
[[ $("$test_home/.local/bin/supabase" --version) == "supabase 0.0.0" ]] ||
  fail "tampered provider asset replaced installed command"
pass "interrupted refresh preserves completed changes and keeps Node.js removed"

cp "$test_root/supabase-release.json" "$release_root/supabase/cli/release.json"
: >"$action_log"
: >"$network_log"
: >"$timeout_log"
resume_output=$(QVOS_TEST_GH_AUTH=1 run_dev --update)
grep -Fq 'qvCORE Devel inventory: 12/16 ready' <<<"$resume_output" ||
  fail "resumed inventory"
grep -Fq 'Outdated: 1' <<<"$resume_output" ||
  fail "resumed outdated count"
[[ ! -s $action_log ]] ||
  fail "resume repeats completed runtime component changes"
[[ $(grep -c '^download' "$network_log") == "1" ]] ||
  fail "resume downloads more than the remaining component"
[[ $("$test_home/.local/bin/supabase" --version) == "supabase 1.2.3" ]] ||
  fail "resumed Supabase update"
grep -Fq 'qvCORE Devel refresh is complete: 13 tracked component(s) current.' \
  <<<"$resume_output" ||
  fail "resumed completion"
pass "rerun verifies completed work and continues only remaining updates"

: >"$action_log"
: >"$network_log"
: >"$timeout_log"
set +e
missing_base_output=$(
  QVOS_TEST_GH_AUTH=1 QVOS_TEST_DOCKER_MISSING=1 run_dev 2>&1
)
missing_base_status=$?
set -e
((missing_base_status != 0)) || fail "missing Docker base succeeds"
grep -Fq 'qvCORE Devel inventory: 14/16 ready' <<<"$missing_base_output" ||
  fail "missing base inventory"
grep -Fq 'Docker + Compose     missing (qvOS base)' <<<"$missing_base_output" ||
  fail "missing base status"
grep -Fq 'Restore the missing qvOS base components before continuing:' \
  <<<"$missing_base_output" ||
  fail "missing base guidance"
[[ ! -s $action_log ]] || fail "missing base preflight performs tool actions"
if grep -q '^download' "$network_log"; then
  fail "missing base preflight downloads provider binaries"
fi
pass "qvCORE reports missing base ownership before making changes"

arm_home="$test_root/arm-home"
arm_mise_state="$test_root/arm-mise-state"
arm_action_log="$test_root/arm-actions"
arm_network_log="$test_root/arm-network"
arm_timeout_log="$test_root/arm-timeouts"
install -d "$arm_home"
printf '%s\n' \
  'node 24.18.0' \
  'bun 1.3.14' >"$arm_mise_state"
: >"$arm_action_log"
: >"$arm_network_log"
: >"$arm_timeout_log"

arm_output=$(
  printf '\n' |
    QVOS_TEST_ACTION_LOG="$arm_action_log" \
      QVOS_TEST_NETWORK_LOG="$arm_network_log" \
      QVOS_TEST_TIMEOUT_LOG="$arm_timeout_log" \
      QVOS_TEST_RELEASE_ROOT="$release_root" \
      QVOS_TEST_ARCH=aarch64 \
      QVOS_TEST_GH_AUTH=1 \
      QVOS_TEST_DOCKER_MISSING=0 \
      QVOS_TEST_MISE_STATE="$arm_mise_state" \
      QVOS_TEST_BIN="$test_bin" \
      HOME="$arm_home" \
      OMARCHY_PATH="$test_omarchy_path" \
      PATH="$arm_home/.local/bin:$test_bin:/usr/bin" \
      "$test_omarchy_path/qv/core/dev.sh"
)
grep -Fq 'qvCORE Devel is ready: 16/16.' <<<"$arm_output" ||
  fail "arm64 verified completion"
[[ $(grep -c '^download' "$arm_network_log") == "9" ]] ||
  fail "arm64 provider download count"

arm_assets=(
  supabase_1.2.3_linux_arm64.tar.gz
  cli_2.3.4_linux_arm64.tar.gz
  cloudflared-linux-arm64
  sentry-cli-Linux-aarch64
  act_Linux_arm64.tar.gz
  sops-v3.12.3.linux.arm64
  age-v1.3.2-linux-arm64.tar.gz
  gitleaks_8.30.1_linux_arm64.tar.gz
  osv-scanner_linux_arm64
)
for asset in "${arm_assets[@]}"; do
  grep -Fq "$asset" "$arm_network_log" ||
    fail "arm64 provider asset $asset"
done
if grep '^download' "$arm_network_log" |
  grep -Eq 'amd64|x86_64|linux_x64'; then
  fail "arm64 run downloads an x86 provider asset"
fi
pass "qvCORE selects verified provider assets for arm64"

grep -Fqx '    mise use --global node@lts' "$root/qv/core/dev.sh" ||
  fail "Node LTS compatibility runtime"
if grep -Eq 'bun (add|install).*(-g|--global).*(wrangler|convex)' "$root/qv/core/dev.sh"; then
  fail "project CLI installed globally"
fi
if grep -Eq 'gh auth token|Authorization:' "$root/qv/core/dev.sh"; then
  fail "Devel installer exposes GitHub credentials"
fi
grep -Fq 'provider_repository[gitleaks]="gitleaks/gitleaks"' \
  "$root/qv/core/dev.sh" ||
  fail "Gitleaks provider ownership"
grep -Fq 'provider_repository[osv-scanner]="google/osv-scanner"' \
  "$root/qv/core/dev.sh" ||
  fail "OSV-Scanner provider ownership"
grep -Fq 'mise x uv@latest --' "$root/qv/core/dev.sh" ||
  fail "Semgrep provider ownership"
pass "qvCORE Devel preserves runtime and credential boundaries"
