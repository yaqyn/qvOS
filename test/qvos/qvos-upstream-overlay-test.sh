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
  bin/omarchy-branch-set
  bin/omarchy-branding-about
  bin/omarchy-branding-screensaver
  bin/omarchy-capture-screenrecording
  bin/omarchy-capture-screenshot
  bin/omarchy-channel-set
  bin/omarchy-config-direct-boot
  bin/omarchy-debug
  bin/omarchy-first-run
  bin/omarchy-install-browser
  bin/omarchy-install-gaming-retroarch
  bin/omarchy-install-vscode
  bin/omarchy-launch-floating-terminal-with-presentation
  bin/omarchy-plymouth-reset
  bin/omarchy-plymouth-set
  bin/omarchy-refresh-hyprland
  bin/omarchy-refresh-limine
  bin/omarchy-refresh-plymouth
  bin/omarchy-refresh-sddm
  bin/omarchy-reinstall
  bin/omarchy-reinstall-configs
  bin/omarchy-reinstall-git
  bin/omarchy-reinstall-pkgs
  bin/omarchy-remove-preinstalls
  bin/omarchy-show-logo
  bin/omarchy-theme-bg-install
  bin/omarchy-transcode
  bin/omarchy-update-branch
  install/config/all.sh
  install/helpers/all.sh
  install/login/limine-snapper.sh
  install/login/plymouth.sh
  install/login/sddm.sh
  install/packaging/base.sh
  install/packaging/npx.sh
  install/packaging/webapps.sh
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
  bin/omarchy-debug
  bin/omarchy-launch-floating-terminal-with-presentation
  bin/omarchy-plymouth-reset
  bin/omarchy-plymouth-set
  bin/omarchy-refresh-limine
  bin/omarchy-refresh-plymouth
  bin/omarchy-refresh-sddm
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
  rg -q '^if \[\[ -(x|f) \$qvos_owner \]\]; then$' "$root/$path" ||
    fail "$path qvOS owner is not availability-guarded"
  if rg -q '^exec "\$OMARCHY_PATH/qv/' "$root/$path" ||
    rg -U -q '^source .*qv/.*\nreturn$' "$root/$path"; then
    fail "$path makes inherited Omarchy fallback unreachable"
  fi
done
pass "inherited qvOS delegations preserve Omarchy fallbacks"

guarded_routes=(
  "bin/omarchy-branch-set|omarchy branch set"
  "bin/omarchy-channel-set|omarchy channel set"
  "bin/omarchy-reinstall|omarchy reinstall"
  "bin/omarchy-reinstall-configs|omarchy reinstall configs"
  "bin/omarchy-reinstall-git|omarchy reinstall git"
  "bin/omarchy-reinstall-pkgs|omarchy reinstall pkgs"
  "bin/omarchy-remove-preinstalls|omarchy remove preinstalls"
  "bin/omarchy-update-branch|omarchy update branch"
)

for route_spec in "${guarded_routes[@]}"; do
  IFS='|' read -r path route <<<"$route_spec"
  # shellcheck disable=SC2016
  delegation='exec "$(dirname -- "${BASH_SOURCE[0]}")/omarchy-qvos-block-upstream-maintenance"'

  [[ $(grep -Fc "$delegation" "$root/$path") == "1" ]] ||
    fail "$path does not contain one stable qvOS guard delegation"
  grep -Fq "\"$route\"" "$root/$path" ||
    fail "$path guard route identity"
  if grep -Eq 'qvos_(root|guard)=|Blocked on qvOS:' "$root/$path"; then
    fail "$path contains qvOS guard implementation"
  fi
done
pass "unavoidable inherited safety edits remain thin delegations"

[[ ! -e $root/install/config/qvos-scripts.sh ]] ||
  fail "qvOS desktop implementation remains under inherited install config"
# shellcheck disable=SC2016
grep -Fqx 'run_logged "$OMARCHY_PATH/qv/install/configure"' \
  "$root/install/config/all.sh" ||
  fail "fresh install qvOS overlay seam"
pass "Omarchy installation runs one separate qvOS stage afterward"

public_adapters=(
  bin/omarchy-install-qvcore
  bin/omarchy-launch-qvos-update
  bin/omarchy-qvcore-remove
  bin/omarchy-qvos-block-upstream-maintenance
  bin/omarchy-qvos-health
  bin/omarchy-qvos-personal-software
  bin/omarchy-qvos-refresh-waybar
  bin/omarchy-qvos-repair
  bin/omarchy-qvos-setup-dns
  bin/omarchy-qvos-share
  bin/omarchy-qvos-system
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
  rg -q 'qv/' "$root/$path" ||
    fail "$path does not delegate to qv/"
done
pass "qvOS public commands are thin adapters"

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
