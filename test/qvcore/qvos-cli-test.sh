#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
qv_cli="$root/bin/qv"
compat_cli="$root/bin/omarchy"
test_root=""

fail() {
  echo "not ok - $1" >&2
  exit 1
}

cleanup() {
  [[ -n $test_root && -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

qv_help=$("$qv_cli" --help)
[[ $qv_help == *"qvOS command center"* ]] || fail "native help heading"
[[ $qv_help == *"qv update"* ]] || fail "native update route"
[[ $qv_help != *"omarchy update"* ]] || fail "native help product identity"

compat_help=$("$compat_cli" --help)
[[ $compat_help == *"omarchy update"* ]] || fail "compatibility update route"

"$qv_cli" commands --json | jq -e '
  .ok == true and
  (all(.commands[]; .route | startswith("qv "))) and
  ([.commands[].binary | select(. == "omarchy-update" or startswith("omarchy-update-"))] | length == 0) and
  ([.commands[] | select(.route == "qv update" and .binary == "qv-update")] | length == 1) and
  ([.commands[] | select(.route == "qv pkg add" and .binary == "qv-pkg-add")] | length == 1) and
  ([.commands[] | select(.route == "qv dev benchmark" and .binary == "qv-dev-benchmark")] | length == 1) and
  ([.commands[] | select(.route == "qv dev bin metadata" and .binary == "qv-dev-bin-metadata")] | length == 1)
' >/dev/null || fail "native command catalog"

metadata=$("$qv_cli" dev bin metadata --json)
jq -e '
  .ok == true and
  .defaults.group == "first filename segment after qv-" and
  .defaults.route == "qv <group> <name>" and
  ([.fields[].name] | index("summary")) and
  ([.fields[].name] | index("aliases"))
' <<<"$metadata" >/dev/null || fail "native metadata documentation"
benchmark=$("$qv_cli" dev benchmark --repeat=1)
[[ $benchmark == *"qvOS CLI benchmark (1 runs each)"* ]] ||
  fail "native CLI benchmark"
for invalid_repeat in 0 101 999999999999999999999; do
  if "$qv_cli" dev benchmark --repeat="$invalid_repeat" >/dev/null 2>&1; then
    fail "bounded CLI benchmark repeat: $invalid_repeat"
  fi
done

update_help=$("$qv_cli" update --help)
[[ $update_help == *"Usage:"* ]] || fail "native update help"
[[ $update_help == *"qv update"* ]] || fail "native update usage"
[[ $update_help == *"qv-update"* ]] || fail "guarded update binary"
[[ $update_help != *"omarchy-update-perform"* ]] || fail "raw updater isolation"

set +e
update_perform_output=$("$qv_cli" update perform 2>&1)
update_perform_status=$?
set -e
(( update_perform_status == 2 )) || fail "raw updater route rejection status"
[[ $update_perform_output == *"Usage: qv update"* ]] ||
  fail "raw updater route rejection owner"

test_root=$(mktemp -d)
ln -s "$qv_cli" "$test_root/qv"
ln -s "$compat_cli" "$test_root/omarchy"
cat >"$test_root/qv-probe-safe" <<'SCRIPT'
#!/bin/bash
# qv:summary=Run the native discovery probe
echo qv-native-probe-ok
SCRIPT
cat >"$test_root/omarchy-probe-safe" <<'SCRIPT'
#!/bin/bash
echo inherited-probe-must-not-run
SCRIPT
chmod 0755 "$test_root/qv-probe-safe" "$test_root/omarchy-probe-safe"

[[ $("$test_root/qv" probe safe) == "qv-native-probe-ok" ]] ||
  fail "native adapter dispatch preference"
[[ $("$test_root/omarchy" probe safe) == "qv-native-probe-ok" ]] ||
  fail "compatibility frontend shares the native owner"
"$test_root/qv" commands --json | jq -e '
  [.commands[] | select(.route == "qv probe safe" and .binary == "qv-probe-safe")] |
  length == 1
' >/dev/null || fail "native discovery is singular"

echo "qvOS native CLI tests passed."
