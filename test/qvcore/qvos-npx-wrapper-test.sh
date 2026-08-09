#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
runtime="$test_root/runtime"
test_home="$test_root/home"
test_bin="$test_root/bin"
node_root="$test_root/node"
node_log="$test_root/node.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$runtime" "$test_home" "$test_bin" "$node_root/bin"
install -m 0755 "$root/qvcore/install/packaging/npx" "$runtime/npx"
install -m 0644 "$root/qvcore/install/packaging/npx-wrappers.psv" \
  "$runtime/npx-wrappers.psv"

run_owner() {
  HOME="$test_home" PATH="$test_bin:/usr/bin" "$runtime/npx"
}

run_owner 2>/dev/null
for command_name in pi ghui; do
  [[ -f $test_home/.local/bin/$command_name &&
    ! -L $test_home/.local/bin/$command_name &&
    -x $test_home/.local/bin/$command_name ]] ||
    fail "fixed NPX wrapper installation: $command_name"
  bash -n "$test_home/.local/bin/$command_name" ||
    fail "fixed NPX wrapper syntax: $command_name"
done
[[ ! -e $test_home/.local/bin/codex && ! -L $test_home/.local/bin/codex ]] ||
  fail "fixed NPX owner created a Codex wrapper"
if rg -q 'omarchy|pacman|curl|prefer-online|node@latest' \
  "$test_home/.local/bin/pi" "$test_home/.local/bin/ghui"; then
  fail "fixed NPX wrapper retains inherited mutation logic"
fi
grep -Fq 'mise where node@lts' "$test_home/.local/bin/pi" ||
  fail "fixed NPX wrapper does not share Node.js LTS"

pi_hash=$(sha256sum "$test_home/.local/bin/pi" | awk '{print $1}')
ghui_hash=$(sha256sum "$test_home/.local/bin/ghui" | awk '{print $1}')
run_owner 2>/dev/null
[[ $(sha256sum "$test_home/.local/bin/pi" | awk '{print $1}') == "$pi_hash" &&
  $(sha256sum "$test_home/.local/bin/ghui" | awk '{print $1}') == "$ghui_hash" ]] ||
  fail "fixed NPX wrapper rerun is not idempotent"

printf '\nuser modification\n' >>"$test_home/.local/bin/pi"
modified_hash=$(sha256sum "$test_home/.local/bin/pi" | awk '{print $1}')
run_owner 2>"$test_root/modified.err"
[[ $(sha256sum "$test_home/.local/bin/pi" | awk '{print $1}') == "$modified_hash" ]] ||
  fail "fixed NPX owner overwrote a modified command"
grep -Fq 'preserved the modified or external pi command' \
  "$test_root/modified.err" ||
  fail "fixed NPX owner omitted its modified-command warning"

external="$test_root/external-ghui"
printf 'external owner\n' >"$external"
rm -f -- "$test_home/.local/bin/ghui"
ln -s "$external" "$test_home/.local/bin/ghui"
run_owner 2>"$test_root/link.err"
[[ -L $test_home/.local/bin/ghui && $(<"$external") == "external owner" ]] ||
  fail "fixed NPX owner followed an external command link"
grep -Fq 'preserved the externally managed ghui command' "$test_root/link.err" ||
  fail "fixed NPX owner omitted its linked-command warning"

printf '#!/bin/bash\necho legacy\n' >"$test_home/.local/bin/pi"
chmod 0755 "$test_home/.local/bin/pi"
legacy_hash=$(sha256sum "$test_home/.local/bin/pi" | awk '{print $1}')
awk -F '|' -v OFS='|' -v hash="$legacy_hash" '
  $2 == "pi" { $3 = hash }
  { print }
' "$runtime/npx-wrappers.psv" >"$runtime/npx-wrappers.psv.next"
mv -f -- "$runtime/npx-wrappers.psv.next" "$runtime/npx-wrappers.psv"
run_owner 2>/dev/null
grep -Fq 'package=@earendil-works/pi-coding-agent' \
  "$test_home/.local/bin/pi" ||
  fail "fixed NPX owner did not replace a proven retired wrapper"

install -m 0755 /dev/stdin "$test_bin/mise" <<'SCRIPT'
#!/bin/bash
[[ $1 == "where" && $2 == "node@lts" ]] || exit 1
printf '%s\n' "$QVOS_TEST_NODE_ROOT"
SCRIPT
install -m 0755 /dev/stdin "$node_root/bin/node" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_NODE_LOG"
SCRIPT
install -m 0755 /dev/null "$node_root/bin/npx"
HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_NODE_LOG="$node_log" \
  QVOS_TEST_NODE_ROOT="$node_root" \
  "$test_home/.local/bin/pi" --version
expected_args=$(printf '%s\n' \
  "$node_root/bin/npx" \
  --yes \
  --package \
  @earendil-works/pi-coding-agent \
  -- \
  pi \
  --version)
[[ $(<"$node_log") == "$expected_args" ]] ||
  fail "fixed NPX wrapper did not preserve the declared package, command, and arguments"

unsafe_home="$test_root/unsafe-home"
install -d "$unsafe_home/.local" "$test_root/external-bin"
ln -s "$test_root/external-bin" "$unsafe_home/.local/bin"
if HOME="$unsafe_home" PATH="$test_bin:/usr/bin" "$runtime/npx" \
  >"$test_root/unsafe.out" 2>"$test_root/unsafe.err"; then
  fail "fixed NPX owner accepted a linked command directory"
fi
grep -Fq 'Refusing unsafe local command directory' "$test_root/unsafe.err" ||
  fail "fixed NPX owner omitted its unsafe-directory error"

printf 'ok - fixed NPX wrappers preserve external owners and replace only proven output\n'
