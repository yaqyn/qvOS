#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
component="$root/qv/core/codex.sh"
test_root="$(mktemp -d)"
thunar_config="$test_root/.config/Thunar/uca.xml"
helper="$test_root/.local/share/qvos/thunar/codex"
state="$test_root/.local/state/qvos/qvcore/codex"
codex_binary="$test_root/.local/bin/codex"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$(dirname -- "$codex_binary")" "$(dirname -- "$thunar_config")"
install -m 0755 /dev/stdin "$codex_binary" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--version" ]] || exit 1
printf 'codex-cli test\n'
SCRIPT
install -m 0600 /dev/stdin "$thunar_config" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<actions>
  <action>
    <icon>user</icon>
    <name>User Action</name>
    <unique-id>user-action</unique-id>
    <command>user-command %f</command>
    <description>Preserve this.</description>
    <patterns>*</patterns>
    <directories/>
  </action>
</actions>
XML

run_component() {
  HOME="$test_root" PATH="/usr/bin" "$component" "$@"
}

adopt_output=$(run_component --adopt)
grep -Fq 'qvCORE Codex is ready: 4/4.' <<<"$adopt_output" ||
  fail "Codex adoption result"
cmp -s "$root/qv/thunar/codex" "$helper" ||
  fail "Codex Thunar helper"
[[ -f $state ]] || fail "Codex enabled state"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-codex-here'])" "$thunar_config") == "1" ]] ||
  fail "Codex Thunar action"
[[ $(xmlstarlet sel -t -v "/actions/action[unique-id='qvos-codex-here']/command" "$thunar_config") != *yolo* ]] ||
  fail "Codex Thunar action uses unsafe mode"
run_component --status >/dev/null ||
  fail "Codex lifecycle status"
pass "Codex adopts an existing CLI with a safe, update-repairable Thunar action"

xmlstarlet ed -L \
  -s "/actions/action[unique-id='qvos-codex-here']" \
  -t elem \
  -n text-files \
  -v "" \
  "$thunar_config"
if run_component --status >/dev/null 2>&1; then
  fail "Codex action with extra file scope reports ready"
fi
run_component --repair >/dev/null
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-codex-here']/text-files)" "$thunar_config") == "0" ]] ||
  fail "Codex repair preserves unsafe extra file scope"
pass "Codex lifecycle removes stale selection types outside its directory scope"

printf 'stale\n' >"$helper"
repair_output=$(run_component --repair)
grep -Fq 'qvCORE Codex inventory: 3/4 ready' <<<"$repair_output" ||
  fail "Codex stale inventory"
cmp -s "$root/qv/thunar/codex" "$helper" ||
  fail "Codex stale helper repair"
pass "Codex repairs only its stale desktop integration"

disable_output=$(run_component --disable)
[[ ! -e $helper && ! -e $state ]] ||
  fail "Codex disable owned-file removal"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='qvos-codex-here'])" "$thunar_config") == "0" ]] ||
  fail "Codex disable action removal"
[[ $(xmlstarlet sel -t -v "count(/actions/action[unique-id='user-action'])" "$thunar_config") == "1" ]] ||
  fail "Codex disable user action preservation"
[[ -x $codex_binary ]] || fail "Codex disable CLI preservation"
grep -Fq 'Codex and personal data were not changed.' <<<"$disable_output" ||
  fail "Codex disable boundary"
pass "Codex disables only its owned integration and preserves the CLI"

run_component --adopt >/dev/null
prepare_output=$(run_component --prepare-remove)
[[ ! -e $helper && ! -e $state ]] ||
  fail "Codex pre-removal integration cleanup"
[[ -x $codex_binary ]] || fail "Codex pre-removal CLI preservation"
grep -Fq 'ready for software removal' <<<"$prepare_output" ||
  fail "Codex pre-removal result"
pass "Codex app removal cleans only its optional desktop integration first"

printf 'malformed\n' >"$thunar_config"
if run_component --adopt >/dev/null 2>&1; then
  fail "Codex adoption with malformed Thunar XML succeeds"
fi
[[ $(<"$thunar_config") == "malformed" ]] ||
  fail "Codex adoption overwrites malformed Thunar XML"
pass "Codex preserves malformed Thunar configuration for recovery"
