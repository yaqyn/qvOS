#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/config/assistant/install"
test_root=$(mktemp -d)

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

fixture_home="$test_root/home"
for skill_root in .agents .claude .codex .pi/agent; do
  install -d -m 0755 "$fixture_home/$skill_root/skills"
done
install -d -m 0755 "$fixture_home/.pi/agent/extensions"
printf 'unrelated skill\n' >"$fixture_home/.codex/skills/custom"
printf 'unrelated extension\n' >"$fixture_home/.pi/agent/extensions/custom.ts"
custom_skill_before=$(sha256sum "$fixture_home/.codex/skills/custom")
custom_extension_before=$(sha256sum "$fixture_home/.pi/agent/extensions/custom.ts")

HOME="$fixture_home" QVOS_PATH="$root" "$owner"
for skill_root in .agents .claude .codex .pi/agent; do
  native_link="$fixture_home/$skill_root/skills/qvos"
  [[ -L $native_link && $(readlink "$native_link") == \
    "$root/qvcore/config/assistant/qvos" ]] ||
    fail "native assistant skill link: $skill_root"
done
pi_target="$fixture_home/.pi/agent/extensions/qvos-system-theme.ts"
cmp -s "$root/qvcore/config/assistant/pi-system-theme.ts" "$pi_target" ||
  fail "native Pi theme payload"
[[ $(stat -c '%a' "$pi_target") == "644" ]] ||
  fail "native Pi theme payload mode"
[[ $(sha256sum "$fixture_home/.codex/skills/custom") == "$custom_skill_before" &&
  $(sha256sum "$fixture_home/.pi/agent/extensions/custom.ts") == \
    "$custom_extension_before" ]] || fail "unrelated assistant state changed"

state_before=$(find "$fixture_home" -printf '%P|%y|%l|%m|%i|%T@\n' | sort)
HOME="$fixture_home" QVOS_PATH="$root" "$owner"
[[ $(find "$fixture_home" -printf '%P|%y|%l|%m|%i|%T@\n' | sort) == \
  "$state_before" ]] || fail "idempotent assistant reconciliation"

conflict_home="$test_root/conflict-home"
install -d -m 0755 "$conflict_home/.codex/skills"
printf 'personal skill\n' >"$conflict_home/.codex/skills/qvos"
if HOME="$conflict_home" QVOS_PATH="$root" "$owner" >/dev/null 2>&1; then
  fail "foreign qvOS skill was overwritten"
fi
[[ $(<"$conflict_home/.codex/skills/qvos") == "personal skill" &&
  ! -e $conflict_home/.agents ]] ||
  fail "skill conflict mutated assistant state"

modified_home="$test_root/modified-home"
install -d -m 0755 "$modified_home/.pi/agent/extensions"
printf 'modified native extension\n' \
  >"$modified_home/.pi/agent/extensions/qvos-system-theme.ts"
if HOME="$modified_home" QVOS_PATH="$root" "$owner" >/dev/null 2>&1; then
  fail "modified native Pi extension was accepted"
fi
[[ $(<"$modified_home/.pi/agent/extensions/qvos-system-theme.ts") == \
  "modified native extension" && ! -e $modified_home/.agents ]] ||
  fail "modified Pi conflict mutated assistant state"

"$root/qvcore/config/assistant/check" >/dev/null
"$root/qvcore/config/check" >/dev/null
"$root/qvcore/install/check" >/dev/null
"$root/qvcore/migrations/check" >/dev/null

printf 'ok - qvOS assistant integration is native, atomic, and preservation-safe\n'
