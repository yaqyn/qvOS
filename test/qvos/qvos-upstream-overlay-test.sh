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
  bin/omarchy-install-browser
  bin/omarchy-install-gaming-xbox-controllers
  bin/omarchy-install-gaming-retroarch
  bin/omarchy-install-nordvpn
  bin/omarchy-install-vscode
  bin/omarchy-update-restart
  bin/omarchy-voxtype-install
  install/helpers/errors.sh
  install/login/limine-snapper.sh
  install/login/plymouth.sh
  install/login/sddm.sh
)

declare -A inherited_seam_set=()
for path in "${inherited_seams[@]}"; do
  inherited_seam_set[$path]=1
done

mapfile -t native_manifests < <(
  find "$root/qv" -mindepth 2 -maxdepth 2 -type f -name native-paths | sort
)
mapfile -t retired_manifests < <(
  find "$root/qv" -mindepth 2 -maxdepth 2 -type f -name retired-paths | sort
)

native_paths=()
retired_paths=()
retired_prefixes=()
declare -A native_path_set=()
declare -A retired_path_set=()

for manifest in "${native_manifests[@]}"; do
  mapfile -t manifest_paths < <(
    sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$manifest"
  )
  for path in "${manifest_paths[@]}"; do
    [[ -z ${native_path_set[$path]:-} ]] ||
      fail "$path is claimed by multiple native-path manifests"
    [[ -z ${inherited_seam_set[$path]:-} ]] ||
      fail "$path is classified as both a native path and an inherited seam"
    native_paths+=("$path")
    native_path_set[$path]=1
  done
done

for manifest in "${retired_manifests[@]}"; do
  mapfile -t manifest_paths < <(
    sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$manifest"
  )
  for path in "${manifest_paths[@]}"; do
    [[ -z ${retired_path_set[$path]:-} ]] ||
      fail "$path is claimed by multiple retired-path manifests"
    retired_paths+=("$path")
    retired_path_set[$path]=1
    [[ $path != */ ]] || retired_prefixes+=("$path")
  done
done

is_retired_path() {
  local candidate=$1
  local prefix

  [[ -n ${retired_path_set[$candidate]:-} ]] && return 0
  for prefix in "${retired_prefixes[@]}"; do
    [[ $candidate == "$prefix"* ]] && return 0
  done
  return 1
}

for path in "${inherited_seams[@]}" "${native_paths[@]}"; do
  ! is_retired_path "$path" ||
    fail "$path is classified as both active and retired"
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
  [[ -n ${native_path_set[$path]:-} ]] && continue
  is_retired_path "$path" && continue

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

for path in "${native_paths[@]}"; do
  git -C "$root" cat-file -e "$upstream_ref:$path" ||
    fail "$path native qvOS path no longer exists in the current upstream target"
  [[ -f $root/$path && ! -L $root/$path ]] ||
    fail "$path native qvOS path is missing or unsafe"
  upstream_file_matches \
    "$(git -C "$root" ls-tree "$upstream_ref" -- "$path" | awk '{print $1}')" \
    "$(git -C "$root" rev-parse "$upstream_ref:$path")" \
    "$path" && fail "$path native qvOS path no longer differs from upstream"
done
pass "native qvOS paths are explicit reviewed upstream departures"

for path in "${retired_paths[@]}"; do
  if [[ $path == */ ]]; then
    retired_upstream_count=$(
      git -C "$root" ls-tree -r --name-only "$upstream_ref" -- "$path" |
        awk 'END { print NR }'
    )
    ((retired_upstream_count > 0)) ||
      fail "$path retired qvOS prefix no longer exists upstream"
    [[ ! -e $root/${path%/} && ! -L $root/${path%/} ]] ||
      fail "$path retired qvOS prefix remains in the working tree"
    [[ -z $(git -C "$root" ls-files -- "$path") ]] ||
      fail "$path retired qvOS prefix remains tracked"
  else
    git -C "$root" cat-file -e "$upstream_ref:$path" ||
      fail "$path retired qvOS path no longer exists upstream"
    [[ ! -e $root/$path && ! -L $root/$path ]] ||
      fail "$path retired qvOS path remains in the working tree"
    [[ -z $(git -C "$root" ls-files -- "$path") ]] ||
      fail "$path retired qvOS path remains tracked"
  fi
done
pass "retired upstream paths are explicit and absent"

fallback_seams=(
  bin/omarchy-launch-floating-terminal-with-presentation
  bin/omarchy-windows-vm
)

for path in "${fallback_seams[@]}"; do
  fallback_diff=$(
    git -C "$root" diff --unified=0 "$upstream_ref" -- "$path"
  )
  while IFS= read -r removed_line; do
    [[ $removed_line != ---* ]] || continue
    removed_line=${removed_line#-}
    branded_line=${removed_line//Omarchy/qvOS}
    legacy_branded_line=${removed_line//Omarchy/(qvOS|Omarchy)}
    if [[ $removed_line == "$branded_line" ]]; then
      fail "$path removes inherited fallback behavior"
    fi
    if ! grep -Fqx "+$branded_line" <<<"$fallback_diff" &&
      ! grep -Fqx "+$legacy_branded_line" <<<"$fallback_diff"; then
      fail "$path removes inherited fallback behavior"
    fi
  done < <(grep '^-' <<<"$fallback_diff" || true)
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

grep -Fq '"qvOS installation stopped!"' "$root/install/helpers/errors.sh" ||
  fail "installer error branding does not expose qvOS"
pass "installer error fallback exposes qvOS identity"

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

npx_output=$(OMARCHY_PATH="$root" "$root/qv/install/packaging/npx") ||
  fail "native npx owner failed"
webapps_output=$(OMARCHY_PATH="$root" "$root/qv/install/packaging/webapps") ||
  fail "native webapps owner failed"
base_output=$(
  OMARCHY_PATH="$root" OMARCHY_INSTALL="$root/install" \
    bash -c 'source "$1"' _ "$root/install/packaging/base.sh"
) || fail "base qvOS owner failed"

[[ $npx_output == $'npx:@openai/codex|codex\nnpx:@earendil-works/pi-coding-agent|pi\nnpx:@kitlangton/ghui|ghui' ]] ||
  fail "native npx owner inventory"
[[ -z $webapps_output ]] || fail "native webapps owner is not empty"
grep -Fqx 'pkg:xdg-user-dirs' <<<"$base_output" ||
  fail "base qvOS owner omits additions"
if grep -Fqx 'pkg:1password-beta' <<<"$base_output"; then
  fail "base qvOS owner falls through to an inherited manifest"
fi
pass "package entrypoints use singular native owners"

[[ ! -e $root/install/config/qvos-scripts.sh ]] ||
  fail "qvOS desktop implementation remains under inherited install config"
[[ ! -e $root/install/config/all.sh ]] ||
  fail "inherited install configuration orchestration remains"
# shellcheck disable=SC2016
grep -Fqx 'source "$OMARCHY_PATH/qv/install/config/run"' \
  "$root/install.sh" ||
  fail "fresh install does not use the native qvOS configuration stage"
# shellcheck disable=SC2016
grep -Fqx 'run_logged "$OMARCHY_PATH/qv/install/configure"' \
  "$root/qv/install/config/run" ||
  fail "native configuration stage omits qvOS configuration"
# shellcheck disable=SC2016
upstream_config_steps=$(
  git -C "$root" show "$upstream_ref:install/config/all.sh" |
    sed -n 's/^run_logged \(\$OMARCHY_INSTALL[^[:space:]]*\)$/\1/p' |
    grep -Fvx '$OMARCHY_INSTALL/config/nautilus-python.sh'
)
# shellcheck disable=SC2016
native_config_steps=$(
  sed -n 's/^run_logged "\(\$OMARCHY_INSTALL[^"]*\)"$/\1/p' \
    "$root/qv/install/config/run"
)
[[ $native_config_steps == "$upstream_config_steps" ]] ||
  fail "native configuration stage changed inherited leaf order or coverage"
# shellcheck disable=SC2016
[[ $(grep -Fc 'run_logged "$OMARCHY_PATH/qv/' \
  "$root/qv/install/config/run") == 2 ]] ||
  fail "native configuration stage qvOS leaf inventory"
pass "fresh installation uses one native qvOS configuration stage"

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
