#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/omarchy"
TMPDIR=$(mktemp -d)

export PATH="$ROOT/bin:$PATH"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_output_contains() {
  local description="$1"
  local output="$2"
  local expected="$3"

  if [[ $output != *"$expected"* ]]; then
    printf 'Expected output to contain: %s\n' "$expected" >&2
    printf 'Actual output:\n%s\n' "$output" >&2
    fail "$description"
  fi

  pass "$description"
}

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

output=$("$CLI" --help)
assert_output_contains "main help renders" "$output" "qvOS command center"
assert_output_contains "main help includes hardware group" "$output" "hw"
assert_output_contains "main help includes package group" "$output" "pkg"
if grep -Eq '^  [a-z0-9-]+[[:space:]].*\([0-9]+\)$' <<<"$output"; then
  fail "main help does not show group counts"
fi
pass "main help does not show group counts"

output=$("$CLI" commands)
assert_output_contains "commands lists documented commands" "$output" "omarchy theme set <theme-name>"

"$CLI" commands --json | jq -e '.ok == true and (.commands | length >= 200)' >/dev/null
pass "commands --json is valid JSON with full bin coverage"

"$CLI" commands --json | jq -e 'all(.commands[]; .summary != "undocumented")' >/dev/null
pass "all included commands have summaries"

"$CLI" commands --json | jq -e 'all(.commands[]; has("binary") and has("filename_route") and has("routes") and (has("legacy") | not) and (has("usage") | not) and (has("visibility") | not) and (has("mutates") | not) and (has("interactive") | not))' >/dev/null
pass "JSON uses binary/routes and omits legacy/usage/extra metadata"

"$CLI" commands --check >/dev/null
pass "commands --check passes"

"$CLI" commands --all >/dev/null
pass "commands --all does not crash"

"$CLI" commands --all --json | jq -e '.commands[] | select(.route == "omarchy hyprland window gaps toggle" and .summary != "undocumented")' >/dev/null
pass "filename-derived commands are inferred and documented"

"$CLI" commands --all --json | jq -e '.commands[] | select(.route == "omarchy dev benchmark")' >/dev/null
pass "benchmark command is discoverable in all commands"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "qv-pkg-add" and .route == "omarchy pkg add" and .filename_route == "omarchy pkg add" and (.routes | index("omarchy pkg add")))' >/dev/null
pass "JSON exposes native pkg add route through compatibility"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "qv-refresh-pacman" and .requires_sudo == true)' >/dev/null
pass "sudo metadata marks sudo commands"

output=$("$CLI" theme --help)
assert_output_contains "group help renders" "$output" "Theme commands"

output=$("$CLI" install --help)
assert_output_contains "install group help renders" "$output" "Install commands"
assert_output_contains "install group includes browser route" "$output" "omarchy install browser"

output=$("$CLI" install)
assert_output_contains "bare group renders help instead of picker" "$output" "Install commands"
assert_output_contains "bare group includes browser route" "$output" "omarchy install browser"

output=$("$CLI" toggle)
assert_output_contains "bare root command with children renders help" "$output" "Toggle commands"
assert_output_contains "bare toggle help includes child route" "$output" "omarchy toggle waybar"

output=$("$CLI" pkg --help)
assert_output_contains "package group includes pkg add filename route" "$output" "omarchy pkg add <packages...>"

output=$("$CLI" restart --help)
assert_output_contains "restart group includes inferred commands" "$output" "omarchy restart btop"
assert_output_contains "restart group includes all restart commands" "$output" "omarchy restart wifi"

output=$("$CLI" hw --help)
assert_output_contains "hardware group help renders" "$output" "omarchy hw asus rog"
assert_output_contains "hardware group includes touchpad" "$output" "omarchy hw touchpad"

output=$("$CLI" hw asus)
assert_output_contains "partial hardware prefix renders matching commands" "$output" "omarchy hw asus rog"
assert_output_contains "partial hardware prefix includes nested match" "$output" "omarchy hw asus zenbook ux5406aa"

output=$("$CLI" menu --help)
assert_output_contains "menu group includes native input route" "$output" "omarchy menu input"

output=$("$CLI" share)
assert_output_contains "bare required-arg alias renders CLI help" "$output" "Usage:"
assert_output_contains "bare share help uses canonical route" "$output" "omarchy share <clipboard|file|folder> [path...]"

set +e
output=$("$CLI" branch set 2>&1)
retired_branch_status=$?
set -e
((retired_branch_status == 127)) || fail "retired branch switch status"
assert_output_contains \
  "retired branch switch is absent from the qvOS CLI" \
  "$output" \
  "Unknown qvOS command: omarchy branch set"

CLI="$CLI" python3 <<'PY'
import json
import os
import subprocess
import sys

cli = os.environ['CLI']
commands = json.loads(subprocess.check_output([cli, 'commands', '--json'], text=True))['commands']
by_group = {}
for command in commands:
  binary = command['binary']
  if not binary.startswith('qv-'):
    raise AssertionError(f'non-native binary discovered: {binary}')
  stem = binary.removeprefix('qv-')
  group = stem.split('-', 1)[0]
  filename_route = 'omarchy ' + stem.replace('-', ' ')
  by_group.setdefault(group, []).append((binary, filename_route, command['route']))

missing = []
for group, rows in sorted(by_group.items()):
  proc = subprocess.run([cli, group, '--help'], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  output = proc.stdout + proc.stderr
  if proc.returncode != 0:
    missing.append((group, '<group-help-failed>', f'exit {proc.returncode}'))
    continue
  for binary, filename_route, canonical_route in rows:
    if filename_route not in output and canonical_route not in output and binary not in output:
      missing.append((group, binary, filename_route))

if missing:
  for row in missing:
    print('\t'.join(row), file=sys.stderr)
  sys.exit(1)
PY
pass "every filename-derived group help represents its bins"

output=$(timeout 5 "$CLI" theme set --help)
assert_output_contains "command help renders without executing" "$output" "Binary:"
assert_output_contains "theme set help names binary" "$output" "qv-theme-set"

output=$(timeout 5 "$CLI" update --help)
assert_output_contains "mutating command help does not execute target" "$output" "qv-update"
assert_output_contains "root command help shows related child commands" "$output" "omarchy update firmware"

output=$("$CLI" screenshot --help)
assert_output_contains "root alias resolves to command help" "$output" "qv-capture-screenshot"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "qv-capture-screenshot") | .aliases | index("omarchy screenshot")' >/dev/null
pass "aliases are included in JSON metadata"

output=$("$CLI" pkg add --help)
assert_output_contains "pkg add help resolves" "$output" "qv-pkg-add"
assert_output_contains "pkg add help shows direct route" "$output" "omarchy pkg add <packages...>"

output=$("$CLI" system reboot --help)
assert_output_contains "system command help is safe" "$output" "qv-system-reboot"

output=$("$CLI" dev benchmark --repeat=1)
assert_output_contains "benchmark command runs" "$output" "qvOS CLI benchmark"

"$CLI" theme list >/dev/null
pass "safe dispatch works for theme list"

"$CLI" theme current >/dev/null
pass "safe dispatch works for theme current"

"$CLI" font list >/dev/null
pass "safe dispatch works for font list"

install -d "$TMPDIR/font-config/waybar"
install -m 0644 "$ROOT/qvcore/config/files/waybar/style.css" \
  "$TMPDIR/font-config/waybar/style.css"
QVOS_FONT_CONFIG_ROOT="$TMPDIR/font-config" "$CLI" font current >/dev/null
pass "safe dispatch works for font current"

for binary in \
  omarchy-update \
  qv-update \
  qv-theme-set \
  omarchy-capture-screenshot \
  qv-capture-screenshot \
  omarchy-system-reboot \
  qv-system-reboot \
  qv-system-shutdown \
  omarchy-pkg-add \
  qv-pkg-add; do
  [[ -x $ROOT/bin/$binary ]] || fail "binary is executable: $binary"
  pass "binary is executable: $binary"
done

while IFS= read -r binary_path; do
  stem=${binary_path##*/omarchy-}
  native_path="$ROOT/bin/qv-$stem"
  header=$(awk '
    NR == 1 && /^#!/ { next }
    /^[[:space:]]*$/ { if (seen) print; next }
    /^[[:space:]]*#/ { seen=1; print; next }
    { exit }
  ' "$binary_path")

  [[ -x $native_path ]] || fail "native owner exists for compatibility adapter: $binary_path"
  [[ -z $header ]] || fail "compatibility adapter has no metadata: $binary_path"
  grep -q '^# qv:summary=' "$native_path" ||
    fail "native metadata summary is present: $native_path"
done < <(find "$ROOT/bin" -maxdepth 1 -type f -executable -name 'omarchy-*' | sort)
pass "every command has one slim metadata owner"

ln -s "$CLI" "$TMPDIR/omarchy"

{
  printf '#!/bin/bash\n\n'
  printf '# ordinary comments are fine\n'
  printf '# qv:this malformed line should be ignored\n'
  printf '# qv:group=weird\n'
  printf '# qv:name=test\n'
  printf '# qv:summary=Survives malformed metadata comments\n'
  printf '# omarchy:summary=This legacy metadata must be ignored\n'
  printf '# qv:made-up=value\n'
  printf 'echo weird-ok\n'
} >"$TMPDIR/qv-weird-test"
chmod +x "$TMPDIR/qv-weird-test"

{
  printf '#!/bin/bash\n\n'
  printf '# a partial metadata header should not destroy filename routing\n'
  printf '# qv:summary=Partial metadata keeps inferred route\n'
  printf '# qv:made-up=value\n'
  printf 'echo partial-ok\n'
} >"$TMPDIR/qv-partial-meta-test"
chmod +x "$TMPDIR/qv-partial-meta-test"

{
  printf '#!/bin/bash\n\n'
  printf 'echo body-metadata-ok\n'
  printf '# qv:group=wrong\n'
  printf '# qv:name=wrong\n'
} >"$TMPDIR/qv-body-metadata-test"
chmod +x "$TMPDIR/qv-body-metadata-test"

{
  printf '#!/bin/bash\n\n'
  printf '# omarchy:summary=Legacy-only commands are not native qvOS routes\n'
  printf 'echo inherited-probe-must-not-run\n'
} >"$TMPDIR/omarchy-legacy-only"
chmod +x "$TMPDIR/omarchy-legacy-only"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy weird test" and .summary == "Survives malformed metadata comments")' >/dev/null
pass "unknown metadata values are non-fatal"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy partial meta test" and .summary == "Partial metadata keeps inferred route")' >/dev/null
pass "partial metadata keeps inferred filename route"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy body metadata test" and .summary == "Run the body metadata test command")' >/dev/null
pass "metadata-looking comments after script body are ignored"

if "$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.binary == "omarchy-legacy-only")' >/dev/null; then
  fail "Omarchy-only command is absent from native discovery"
fi
pass "Omarchy-only commands are absent from native discovery"

output=$("$TMPDIR/omarchy" weird test)
assert_output_contains "temporary metadata command dispatches" "$output" "weird-ok"

output=$("$TMPDIR/omarchy" partial meta test)
assert_output_contains "partial metadata command dispatches" "$output" "partial-ok"

output=$("$TMPDIR/omarchy" body metadata test)
assert_output_contains "body metadata command dispatches by filename" "$output" "body-metadata-ok"

set +e
output=$("$TMPDIR/omarchy" legacy only 2>&1)
legacy_only_status=$?
set -e
((legacy_only_status == 127)) || fail "Omarchy-only command dispatch status"
assert_output_contains "Omarchy-only command cannot dispatch" "$output" "Unknown qvOS command: omarchy legacy only"
[[ $output != *"inherited-probe-must-not-run"* ]] || fail "Omarchy-only owner did not execute"
pass "Omarchy-only owner did not execute"
