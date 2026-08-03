#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_migration() {
  HOME="$test_root/home" \
    XDG_STATE_HOME="$test_root/home/.local/state" \
    "$root/qvcore/install/migrate-structure" "$@"
}

state_root="$test_root/home/.local/state/qvos"
share_root="$test_root/home/.local/share/qvos"
install -d \
  "$state_root/qvcore" \
  "$share_root/qvdev-tools/bin"
install -m 0644 /dev/null "$state_root/qvcore/proton"
install -m 0644 /dev/null "$state_root/qvcore/qvdev"
printf 'managed tool\n' >"$share_root/qvdev-tools/bin/example"

run_migration --all

for marker in services/proton development/devel; do
  [[ -f $state_root/$marker && ! -L $state_root/$marker ]] ||
    fail "migrated enrollment marker: $marker"
  [[ $(stat -c '%a' "$state_root/$marker") == "600" ]] ||
    fail "private enrollment mode: $marker"
done
[[ ! -e $state_root/qvcore ]] || fail "legacy enrollment root cleanup"
[[ -f $share_root/devel-tools/bin/example ]] || fail "Devel tool-root migration"
[[ $(stat -c '%a' "$share_root/devel-tools") == "700" ]] ||
  fail "private Devel tool-root mode"
[[ ! -e $share_root/qvdev-tools ]] || fail "legacy Devel tool-root cleanup"

run_migration --all

chmod 0755 "$state_root/services" "$state_root/development"
chmod 0644 "$state_root/services/proton" "$state_root/development/devel"
run_migration --all
for marker in services/proton development/devel; do
  [[ $(stat -c '%a' "$state_root/$marker") == "600" ]] ||
    fail "existing enrollment mode convergence: $marker"
  [[ $(stat -c '%a' "$(dirname -- "$state_root/$marker")") == "700" ]] ||
    fail "existing enrollment parent convergence: $marker"
done

conflict_root="$test_root/conflict"
install -d \
  "$conflict_root/home/.local/state/qvos/qvcore" \
  "$conflict_root/home/.local/state/qvos/services"
install -m 0644 /dev/null "$conflict_root/home/.local/state/qvos/qvcore/proton"
install -m 0644 /dev/null "$conflict_root/home/.local/state/qvos/services/proton"
printf 'unsafe\n' >"$conflict_root/home/.local/state/qvos/services/proton"
if HOME="$conflict_root/home" \
  XDG_STATE_HOME="$conflict_root/home/.local/state" \
  "$root/qvcore/install/migrate-structure" --proton >/dev/null 2>&1; then
  fail "conflicting enrollment marker accepted"
fi
[[ -f $conflict_root/home/.local/state/qvos/qvcore/proton ]] ||
  fail "conflict handling removed legacy marker"

link_root="$test_root/link"
install -d "$link_root/home/.local/state/qvos/qvcore" "$link_root/target"
ln -s "$link_root/target" "$link_root/home/.local/state/qvos/qvcore/proton"
if HOME="$link_root/home" \
  XDG_STATE_HOME="$link_root/home/.local/state" \
  "$root/qvcore/install/migrate-structure" --proton >/dev/null 2>&1; then
  fail "linked enrollment marker accepted"
fi
[[ -L $link_root/home/.local/state/qvos/qvcore/proton ]] ||
  fail "symlink refusal changed legacy state"

target_link_root="$test_root/target-link"
target_state="$target_link_root/home/.local/state/qvos"
install -d "$target_state/qvcore" "$target_link_root/external"
install -m 0644 /dev/null "$target_state/qvcore/proton"
ln -s "$target_link_root/external" "$target_state/services"
if HOME="$target_link_root/home" \
  XDG_STATE_HOME="$target_link_root/home/.local/state" \
  "$root/qvcore/install/migrate-structure" --proton >/dev/null 2>&1; then
  fail "linked enrollment target parent accepted"
fi
[[ -f $target_state/qvcore/proton ]] ||
  fail "target-parent refusal removed legacy marker"
[[ -z $(find "$target_link_root/external" -mindepth 1 -print -quit) ]] ||
  fail "linked enrollment target escaped the state root"

existing_link_root="$test_root/existing-link"
existing_state="$existing_link_root/home/.local/state/qvos"
install -d "$existing_state/services" "$existing_link_root/external"
ln -s "$existing_link_root/external/marker" "$existing_state/services/proton"
if HOME="$existing_link_root/home" \
  XDG_STATE_HOME="$existing_link_root/home/.local/state" \
  "$root/qvcore/install/migrate-structure" --proton >/dev/null 2>&1; then
  fail "existing linked enrollment target accepted"
fi
[[ -L $existing_state/services/proton ]] ||
  fail "existing target refusal changed enrollment state"
[[ ! -e $existing_link_root/external/marker ]] ||
  fail "existing enrollment link escaped the state root"

printf 'ok - qvOS structure migration is private, atomic, idempotent, and link-safe\n'
