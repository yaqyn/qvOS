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

seam_manifest="$root/compat/omarchy/inherited-seams"
mapfile -t inherited_seams < <(
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$seam_manifest"
)
[[ $(printf '%s\n' "${inherited_seams[@]}" | sort -u) == \
  $(printf '%s\n' "${inherited_seams[@]}") ]] ||
  fail "inherited compatibility seams are not sorted and unique"

declare -A inherited_seam_set=()
for path in "${inherited_seams[@]}"; do
  inherited_seam_set[$path]=1
done

mapfile -t native_manifests < <(
  find "$root/qvcore" "$root/development" "$root/services" \
    -type f -name native-paths | sort
)
mapfile -t retired_manifests < <(
  find "$root/qvcore" "$root/development" "$root/services" \
    -type f -name retired-paths | sort
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

grep -Fq 'This entire file is qvOS-owned' "$root/AGENTS.md" ||
  fail "root qvOS instruction ownership"
if rg -q 'verbatim upstream Omarchy|must match the reviewed target byte-for-byte' \
  "$root/AGENTS.md" "$root/upstream/qvsync"; then
  fail "retired upstream instruction-copy contract remains"
fi
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
  rg -q 'qvcore/|omarchy-qvos-' "$root/$path" ||
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

if rg -n 'qvos_owner=' "$root/bin"; then
  fail "a public command still retains an inherited availability fallback"
fi
pass "promoted public commands retain no inherited availability fallbacks"

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

npx_output=$(QVOS_PATH="$root" OMARCHY_PATH="$root" "$root/qvcore/install/packaging/npx") ||
  fail "native npx owner failed"
webapps_output=$(QVOS_PATH="$root" OMARCHY_PATH="$root" "$root/qvcore/install/packaging/webapps") ||
  fail "native webapps owner failed"
base_output=$(
  QVOS_PATH="$root" OMARCHY_PATH="$root" \
    QVOS_INSTALL="$root/qvcore/install" OMARCHY_INSTALL="$root/qvcore/install" \
    bash -c 'source "$1"' _ "$root/qvcore/install/packaging/base"
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

[[ ! -e $root/install && ! -L $root/install ]] ||
  fail "inherited install tree remains"
# shellcheck disable=SC2016
grep -Fqx 'source "$QVOS_PATH/qvcore/install/config/run"' \
  "$root/install.sh" ||
  fail "fresh install does not use the native qvOS configuration stage"
# shellcheck disable=SC2016
grep -Fqx 'run_logged "$QVOS_PATH/qvcore/install/configure"' \
  "$root/qvcore/install/config/run" ||
  fail "native configuration stage omits qvOS configuration"
# shellcheck disable=SC2016
upstream_config_steps=$(
  git -C "$root" show "$upstream_ref:install/config/all.sh" |
    sed -n 's/^run_logged \(\$OMARCHY_INSTALL[^[:space:]]*\)$/\1/p' |
    while IFS= read -r step; do
      case $step in
      '$OMARCHY_INSTALL/config/mimetypes.sh')
        ;;
      '$OMARCHY_INSTALL/config/nautilus-python.sh')
        ;;
      '$OMARCHY_INSTALL/config/omarchy-toggles.sh')
        printf '%s\n' '$QVOS_PATH/qvcore/config/toggle-state'
        ;;
      '$OMARCHY_INSTALL/config/walker-elephant.sh')
        ;;
      '$OMARCHY_INSTALL/config/hardware/asus/fix-asus-ptl-b9406-touchpad.sh')
        printf '%s\n' '$QVOS_PATH/qvcore/install/hardware/asus/b9406-touchpad'
        ;;
      *)
        printf '$QVOS_INSTALL/%s\n' "${step#\$OMARCHY_INSTALL/}"
        ;;
      esac
    done
  printf '%s\n' '$QVOS_PATH/qvcore/install/configure'
)
# shellcheck disable=SC2016
native_config_steps=$(
  sed -n 's/^run_logged "\([^"]*\)"$/\1/p' \
    "$root/qvcore/install/config/run"
)
[[ $native_config_steps == "$upstream_config_steps" ]] ||
  fail "native configuration stage changed reviewed capability order or coverage"
for walker_source in \
  config/autostart/walker.desktop \
  config/systemd/user/app-walker@autostart.service.d/restart.conf; do
  [[ -f $root/$walker_source && ! -L $root/$walker_source ]] ||
    fail "native Walker startup source is missing: $walker_source"
done
# shellcheck disable=SC2016
grep -Fqx '"$QVOS_PATH/qvcore/menu/install" --install' \
  "$root/qvcore/install/first-run/run" ||
  fail "fresh install omits native Walker and Elephant reconciliation"
while IFS= read -r step; do
  # shellcheck disable=SC2016
  case $step in
  '$QVOS_INSTALL/'*)
    owner="$root/qvcore/install/${step#\$QVOS_INSTALL/}"
    ;;
  '$QVOS_PATH/'*)
    owner="$root/${step#\$QVOS_PATH/}"
    ;;
  *)
    fail "unknown native install owner root: $step"
    ;;
  esac
  [[ -f $owner && ! -L $owner ]] ||
    fail "native install capability owner is missing: $owner"
done <<<"$native_config_steps"
# shellcheck disable=SC2016
grep -Fqx 'run_logged "$QVOS_PATH/qvcore/install/hardware/asus/b9406-touchpad"' \
  "$root/qvcore/install/config/run" ||
  fail "native configuration stage omits the corrected ASUS B9406 touchpad owner"
pass "fresh installation owns every reviewed configuration capability natively"

public_adapters=(
  bin/omarchy-battery-protection
  bin/omarchy-launch-update
  bin/omarchy-share
  bin/omarchy-show-failed
  bin/omarchy-system-inhibit-sleep
  bin/omarchy-system-suspend-if-safe
  bin/qv-dev-share
  bin/qv-launch-task
  bin/qv-refresh-waybar
)

for path in "${public_adapters[@]}"; do
  [[ -x $root/$path ]] || fail "$path public adapter mode"
  (($(wc -l <"$root/$path") <= 15)) ||
    fail "$path contains implementation outside qvcore/"
  rg -q 'qvcore/|share/qvos/|lib/qvos/|compat/omarchy/' "$root/$path" ||
    fail "$path does not delegate to a qvOS source or runtime owner"
done
pass "qvOS public commands are thin source or checked-runtime adapters"

"$root/qvcore/migrations/check" >/dev/null ||
  fail "native migration ownership contract"
pass "qvOS migrations have one native source and no inherited replay tree"
