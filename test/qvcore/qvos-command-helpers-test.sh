#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_owner() {
  PATH="$test_bin:/usr/bin" "$root/qvcore/cli/command-$1" "${@:2}"
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/available-command" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

run_owner present available-command bash || fail "present command set"
run_owner missing unavailable-command || fail "missing command set"
if run_owner present available-command unavailable-command; then
  fail "mixed command set reported present"
fi
if run_owner missing available-command bash; then
  fail "all-present command set reported missing"
fi
run_owner present || fail "empty present set is not true"
if run_owner missing; then
  fail "empty missing set is true"
fi
if run_owner present -p; then
  fail "command option was interpreted as a command name"
fi
printf 'ok - native command checks are exact and preserve set semantics\n'

PATH="$test_bin:/usr/bin" QVOS_PATH="$root" \
  "$root/bin/omarchy-cmd-present" available-command ||
  fail "command compatibility adapter"
"$root/bin/qv" cmd present --help | grep -Fq 'qv-cmd-present' ||
  fail "native command catalog route"
[[ ! -e $root/bin/omarchy-cmd-terminal-cwd && ! -L $root/bin/omarchy-cmd-terminal-cwd ]] ||
  fail "unused terminal CWD helper remains"
[[ -x $root/qvcore/desktop/context/qvos-active-location ]] ||
  fail "desktop context replacement is unavailable"
printf 'ok - command compatibility and desktop context have singular owners\n'
