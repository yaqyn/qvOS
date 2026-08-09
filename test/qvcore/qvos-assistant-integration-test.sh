#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/config/assistant/install"
test_root=$(mktemp -d)
old_pi_source="$test_root/omarchy-system-theme.ts"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -m 0644 /dev/stdin "$old_pi_source" <<'EOF'
/**
 * Syncs pi's light/dark theme with the active Omarchy theme.
 *
 * Omarchy light themes include:
 *   ~/.config/omarchy/current/theme/light.mode
 */

import { existsSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const home = process.env.HOME ?? "";
const lightModePath = join(home, ".config/omarchy/current/theme/light.mode");

function omarchyPiTheme(): "light" | "dark" {
  return existsSync(lightModePath) ? "light" : "dark";
}

export default function (pi: ExtensionAPI) {
  let intervalId: ReturnType<typeof setInterval> | null = null;

  pi.on("session_start", (_event, ctx) => {
    let currentTheme = omarchyPiTheme();
    ctx.ui.setTheme(currentTheme);

    intervalId = setInterval(() => {
      const nextTheme = omarchyPiTheme();
      if (nextTheme !== currentTheme) {
        currentTheme = nextTheme;
        ctx.ui.setTheme(currentTheme);
      }
    }, 2000);
  });

  pi.on("session_shutdown", () => {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  });
}
EOF
sed -i \
  -e 's/^        /\t\t\t\t/' \
  -e 's/^      /\t\t\t/' \
  -e 's/^    /\t\t/' \
  -e 's/^  /\t/' \
  "$old_pi_source"
[[ $(sha256sum "$old_pi_source" | cut -d ' ' -f 1) == \
  "6dc29806fdef89914a70e24b02d9fb103614a978ffcef3ffbac7a9e22dc02f71" ]] ||
  fail "legacy Pi fixture hash"

fixture_home="$test_root/home"
for skill_root in .agents .claude .codex .pi/agent; do
  install -d -m 0755 "$fixture_home/$skill_root/skills"
  ln -s "$fixture_home/.local/share/omarchy/default/omarchy-skill" \
    "$fixture_home/$skill_root/skills/omarchy"
done
rm -f "$fixture_home/.agents/skills/omarchy"
ln -s "$root/qvcore/config/assistant/qvos" \
  "$fixture_home/.agents/skills/omarchy"
install -d -m 0755 "$fixture_home/.pi/agent/extensions"
install -m 0644 "$old_pi_source" \
  "$fixture_home/.pi/agent/extensions/omarchy-system-theme.ts"
install -m 0644 "$old_pi_source" \
  "$fixture_home/.pi/agent/extensions/qvos-system-theme.ts"
printf 'unrelated skill\n' >"$fixture_home/.codex/skills/custom"
printf 'unrelated extension\n' >"$fixture_home/.pi/agent/extensions/custom.ts"
custom_skill_before=$(sha256sum "$fixture_home/.codex/skills/custom")
custom_extension_before=$(sha256sum "$fixture_home/.pi/agent/extensions/custom.ts")

HOME="$fixture_home" QVOS_PATH="$root" "$owner"
for skill_root in .agents .claude .codex .pi/agent; do
  native_link="$fixture_home/$skill_root/skills/qvos"
  legacy_link="$fixture_home/$skill_root/skills/omarchy"
  [[ -L $native_link && $(readlink "$native_link") == \
    "$root/qvcore/config/assistant/qvos" ]] ||
    fail "native assistant skill link: $skill_root"
  [[ ! -e $legacy_link && ! -L $legacy_link ]] ||
    fail "legacy assistant skill link remains: $skill_root"
done
pi_target="$fixture_home/.pi/agent/extensions/qvos-system-theme.ts"
legacy_pi="$fixture_home/.pi/agent/extensions/omarchy-system-theme.ts"
cmp -s "$root/qvcore/config/assistant/pi-system-theme.ts" "$pi_target" ||
  fail "native Pi theme payload"
[[ $(stat -c '%a' "$pi_target") == "644" ]] ||
  fail "native Pi theme payload mode"
[[ ! -e $legacy_pi && ! -L $legacy_pi ]] ||
  fail "legacy Pi theme payload remains"
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
printf 'modified legacy extension\n' \
  >"$modified_home/.pi/agent/extensions/omarchy-system-theme.ts"
if HOME="$modified_home" QVOS_PATH="$root" "$owner" >/dev/null 2>&1; then
  fail "modified legacy Pi extension was accepted"
fi
[[ $(<"$modified_home/.pi/agent/extensions/omarchy-system-theme.ts") == \
  "modified legacy extension" && ! -e $modified_home/.agents ]] ||
  fail "modified Pi conflict mutated assistant state"

"$root/qvcore/config/assistant/check" >/dev/null
"$root/qvcore/config/check" >/dev/null
"$root/qvcore/install/check" >/dev/null
"$root/qvcore/migrations/check" >/dev/null

printf 'ok - qvOS assistant integration is native, atomic, and preservation-safe\n'
