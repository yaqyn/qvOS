#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

if git -C "$root" show-ref --verify --quiet refs/remotes/upstream/master; then
  upstream_ref=upstream/master
elif git -C "$root" show-ref --verify --quiet refs/remotes/origin/master; then
  upstream_ref=origin/master
else
  fail "no tracked upstream master ref is available for overlay verification"
fi

inherited_seams=(
  bin/omarchy-branding-about
  bin/omarchy-branding-screensaver
  bin/omarchy-config-direct-boot
  bin/omarchy-first-run
  bin/omarchy-install-browser
  bin/omarchy-install-gaming-xbox-controllers
  bin/omarchy-install-gaming-retroarch
  bin/omarchy-install-nordvpn
  bin/omarchy-install-vscode
  bin/omarchy-launch-floating-terminal-with-presentation
  bin/omarchy-plymouth-reset
  bin/omarchy-plymouth-set
  bin/omarchy-refresh-hyprland
  bin/omarchy-refresh-limine
  bin/omarchy-refresh-plymouth
  bin/omarchy-refresh-sddm
  bin/omarchy-show-logo
  bin/omarchy-theme-bg-install
  bin/omarchy-tz-select
  bin/omarchy-update-restart
  bin/omarchy-voxtype-install
  bin/omarchy-windows-vm
  install/config/all.sh
  install/helpers/all.sh
  install/login/limine-snapper.sh
  install/login/plymouth.sh
  install/login/sddm.sh
  install/packaging/base.sh
  install/packaging/npx.sh
  install/packaging/webapps.sh
  install/post-install/all.sh
  install/post-install/finished.sh
)

declare -A inherited_seam_set=()
for path in "${inherited_seams[@]}"; do
  inherited_seam_set[$path]=1
done

upstream_file_matches() {
  local mode=$1
  local object=$2
  local path=$3
  local expected_link

  case $mode in
  120000)
    expected_link=$(git -C "$root" cat-file -p "$object")
    [[ -L $root/$path ]] &&
      [[ $(readlink -- "$root/$path") == "$expected_link" ]]
    ;;
  100755)
    [[ -f $root/$path && -x $root/$path ]] &&
      cmp -s <(git -C "$root" cat-file -p "$object") "$root/$path"
    ;;
  *)
    [[ -f $root/$path && ! -x $root/$path ]] &&
      cmp -s <(git -C "$root" cat-file -p "$object") "$root/$path"
    ;;
  esac
}

upstream_file_count=0
while IFS= read -r entry; do
  metadata=${entry%%$'\t'*}
  path=${entry#*$'\t'}
  read -r mode _ object <<<"$metadata"
  ((upstream_file_count += 1))

  case $path in
  AGENTS.md | README.md) continue ;;
  esac
  [[ -n ${inherited_seam_set[$path]:-} ]] && continue

  upstream_file_matches "$mode" "$object" "$path" ||
    fail "$path differs from upstream outside the audited seam list"
done < <(git -C "$root" ls-tree -r "$upstream_ref")
((upstream_file_count > 1000)) ||
  fail "upstream parity scan covered an implausibly small tree"

upstream_agents_lines=$(
  git -C "$root" show "$upstream_ref:AGENTS.md" | wc -l
)
cmp -s \
  <(git -C "$root" show "$upstream_ref:AGENTS.md") \
  <(head -n "$upstream_agents_lines" "$root/AGENTS.md") ||
  fail "AGENTS.md upstream policy block drift"
grep -Fqx '<!-- qvOS ADDITIONS START -->' "$root/AGENTS.md" ||
  fail "AGENTS.md qvOS policy separator"
pass "the complete inherited tree matches upstream outside audited seams"

for path in "${inherited_seams[@]}"; do
  git -C "$root" cat-file -e "$upstream_ref:$path" ||
    fail "$path no longer exists upstream"
  if upstream_file_matches \
    "$(git -C "$root" ls-tree "$upstream_ref" -- "$path" | awk '{print $1}')" \
    "$(git -C "$root" rev-parse "$upstream_ref:$path")" \
    "$path"; then
    fail "$path is listed as a seam but no longer differs from upstream"
  fi

  read -r added removed _ < <(
    git -C "$root" diff --numstat "$upstream_ref" -- "$path"
  )
  [[ $added =~ ^[0-9]+$ && $removed =~ ^[0-9]+$ ]] ||
    fail "$path inherited seam is not text-reviewable"
  ((added <= 10 && removed <= 10)) ||
    fail "$path inherited seam contains implementation-sized drift"
  rg -q 'qv/|omarchy-qvos-' "$root/$path" ||
    fail "$path does not delegate to an explicit qvOS owner"
done
pass "every inherited exception is a small qvOS integration seam"

fallback_seams=(
  bin/omarchy-config-direct-boot
  bin/omarchy-launch-floating-terminal-with-presentation
  bin/omarchy-plymouth-reset
  bin/omarchy-plymouth-set
  bin/omarchy-refresh-limine
  bin/omarchy-refresh-plymouth
  bin/omarchy-refresh-sddm
  bin/omarchy-windows-vm
  install/packaging/base.sh
  install/packaging/npx.sh
  install/packaging/webapps.sh
)

for path in "${fallback_seams[@]}"; do
  read -r _ removed _ < <(
    git -C "$root" diff --numstat "$upstream_ref" -- "$path"
  )
  ((removed == 0)) ||
    fail "$path removes inherited Omarchy fallback behavior"
  # shellcheck disable=SC2016
  grep -Fq 'qvos_owner="$OMARCHY_PATH/qv/' "$root/$path" ||
    fail "$path does not name its qvOS owner"
  rg -q '^[[:space:]]*if \[\[ -(x|f) \$qvos_owner \]\]; then$' "$root/$path" ||
    fail "$path qvOS owner is not availability-guarded"
  if rg -q '^exec "\$OMARCHY_PATH/qv/' "$root/$path" ||
    rg -U -q '^source .*qv/.*\nreturn$' "$root/$path"; then
    fail "$path makes inherited Omarchy fallback unreachable"
  fi
done
pass "inherited qvOS delegations preserve Omarchy fallbacks"

packaging_seams=(
  install/packaging/base.sh
  install/packaging/npx.sh
  install/packaging/webapps.sh
)
# shellcheck disable=SC2016
for path in "${packaging_seams[@]}"; do
  grep -Fq 'if [[ ${BASH_SOURCE[0]} -ef $0 ]]; then' "$root/$path" ||
    fail "$path does not distinguish execution from sourcing"
  grep -Fq 'exit "$qvos_owner_status"' "$root/$path" ||
    fail "$path does not stop executable fallthrough"
  grep -Fq 'return "$qvos_owner_status"' "$root/$path" ||
    fail "$path does not stop sourced fallthrough"
done

omarchy-npx-install() {
  printf 'npx:%s|%s\n' "$1" "$2"
}
omarchy-webapp-install() {
  printf 'webapp:%s\n' "$1"
}
omarchy-pkg-add() {
  printf 'pkg:%s\n' "$@"
}
export -f omarchy-npx-install omarchy-webapp-install omarchy-pkg-add

run_packaging_adapter() {
  local mode=$1
  local path=$2

  case $mode in
  execute)
    OMARCHY_PATH="$root" OMARCHY_INSTALL="$root/install" bash "$root/$path"
    ;;
  source)
    OMARCHY_PATH="$root" OMARCHY_INSTALL="$root/install" \
      bash -c 'source "$1"' _ "$root/$path"
    ;;
  esac
}

for adapter_mode in execute source; do
  npx_output=$(run_packaging_adapter "$adapter_mode" install/packaging/npx.sh) ||
    fail "npx qvOS adapter failed in $adapter_mode mode"
  webapps_output=$(run_packaging_adapter "$adapter_mode" install/packaging/webapps.sh) ||
    fail "webapps qvOS adapter failed in $adapter_mode mode"
  base_output=$(run_packaging_adapter "$adapter_mode" install/packaging/base.sh) ||
    fail "base qvOS adapter failed in $adapter_mode mode"

  [[ $npx_output == $'npx:@earendil-works/pi-coding-agent|pi\nnpx:@kitlangton/ghui|ghui' ]] ||
    fail "npx qvOS adapter falls through in $adapter_mode mode"
  [[ -z $webapps_output ]] ||
    fail "webapps qvOS adapter falls through in $adapter_mode mode"
  grep -Fqx 'pkg:xdg-user-dirs' <<<"$base_output" ||
    fail "base qvOS adapter omits additions in $adapter_mode mode"
  if grep -Fqx 'pkg:1password-beta' <<<"$base_output"; then
    fail "base qvOS adapter falls through in $adapter_mode mode"
  fi
done
pass "packaging adapters delegate without sourced or executable fallthrough"

[[ ! -e $root/install/config/qvos-scripts.sh ]] ||
  fail "qvOS desktop implementation remains under inherited install config"
# shellcheck disable=SC2016
grep -Fqx 'run_logged "$OMARCHY_PATH/qv/install/configure"' \
  "$root/install/config/all.sh" ||
  fail "fresh install qvOS overlay seam"
pass "Omarchy installation runs one separate qvOS stage afterward"

public_adapters=(
  bin/omarchy-install-qvcore
  bin/omarchy-launch-qvos-task
  bin/omarchy-launch-qvos-update
  bin/omarchy-qvcore-remove
  bin/omarchy-qvos-refresh-waybar
  bin/omarchy-qvos-setup-dns
  bin/omarchy-qvos-share
  bin/omarchy-qvos-update
  bin/omarchy-qvos-update-available
  bin/omarchy-show-failed
  bin/omarchy-system-inhibit-sleep
  bin/omarchy-system-suspend-if-safe
)

for path in "${public_adapters[@]}"; do
  [[ -x $root/$path ]] || fail "$path public adapter mode"
  (($(wc -l <"$root/$path") <= 15)) ||
    fail "$path contains implementation outside qv/"
  rg -q 'qv/|share/qvos/' "$root/$path" ||
    fail "$path does not delegate to a qvOS source or runtime owner"
done
pass "qvOS public commands are thin source or checked-runtime adapters"

shopt -s nullglob
migration_owners=("$root"/qv/migrations/*.sh)
shopt -u nullglob
for owner in "${migration_owners[@]}"; do
  migration=$(basename -- "$owner")
  stub="$root/migrations/$migration"

  [[ -f $stub && ! -x $stub ]] ||
    fail "$migration inherited migration seam mode"
  (($(wc -l <"$stub") == 2)) ||
    fail "$migration contains implementation outside qv/migrations"
  head -n 1 "$stub" | grep -Eq '^echo ".+"$' ||
    fail "$migration migration description"
  grep -Fqx "source \"\$OMARCHY_PATH/qv/migrations/$migration\"" "$stub" ||
    fail "$migration qvOS migration delegation"
done
pass "qvOS migration seams keep implementation under qv/migrations"
