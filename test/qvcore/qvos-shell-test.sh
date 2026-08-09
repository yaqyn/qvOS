#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/shell/install"
test_root=$(mktemp -d)

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_owner() {
  HOME=$1 QVOS_PATH="$root" "$owner"
}

"$root/qvcore/shell/check"

fresh_home="$test_root/fresh-home"
install -d "$fresh_home/.local/share"
ln -s "$root" "$fresh_home/.local/share/qvos"
cp "$root/qvcore/shell/files/bashrc" "$fresh_home/.bashrc"
run_owner "$fresh_home"
# shellcheck disable=SC2016
grep -Fqx 'source "$HOME/.local/share/qvos/qvcore/shell/files/rc"' \
  "$fresh_home/.bashrc" || fail "fresh native Bash source"
# shellcheck disable=SC2016
if grep -Fqx 'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$fresh_home/.bashrc"; then
  fail "fresh Bash configuration duplicates runtime aliases"
fi
HOME="$fresh_home" QVOS_PATH="$root" TERM=dumb \
  bash --noprofile --norc -c \
  'source "$HOME/.local/share/qvos/qvcore/shell/files/rc"; alias cy >/dev/null; alias hx >/dev/null; complete -p qv >/dev/null' ||
  fail "fresh shell startup"

legacy_home="$test_root/legacy-home"
install -d "$legacy_home"
install -m 0644 /dev/stdin "$legacy_home/.bashrc" <<'BASHRC'
source ~/.local/share/qvos/default/bash/rc
source "$HOME/.local/share/qvos/shell/aliases"
alias hx="helix"
export PERSONAL_SHELL_VALUE=preserve
BASHRC
run_owner "$legacy_home"
runtime_aliases="$legacy_home/.local/lib/qvos/shell/aliases"
cmp -s "$root/qvcore/shell/aliases" "$runtime_aliases" ||
  fail "runtime alias publication"
[[ $(stat -c '%a' -- "$runtime_aliases") == "644" ]] ||
  fail "runtime alias mode"
# shellcheck disable=SC2016
[[ $(grep -Fxc 'source "$HOME/.local/share/qvos/qvcore/shell/files/rc"' \
  "$legacy_home/.bashrc") == 1 ]] || fail "legacy Bash source migration"
if rg -n 'default/bash|\.local/share/qvos/shell/aliases|alias hx="helix"' \
  "$legacy_home/.bashrc"; then
  fail "legacy Bash source residue"
fi
grep -Fqx 'export PERSONAL_SHELL_VALUE=preserve' "$legacy_home/.bashrc" ||
  fail "personal Bash content preservation"
compgen -G "$legacy_home/.bashrc.bak.*" >/dev/null ||
  fail "legacy Bash backup"

first_hashes=$(find "$legacy_home" -type f -exec sha256sum {} + | sort)
first_inodes=$(find "$legacy_home" -type f -exec stat -c '%i %n' {} + | sort)
run_owner "$legacy_home"
[[ $(find "$legacy_home" -type f -exec sha256sum {} + | sort) == \
  "$first_hashes" ]] || fail "idempotent shell content"
[[ $(find "$legacy_home" -type f -exec stat -c '%i %n' {} + | sort) == \
  "$first_inodes" ]] || fail "idempotent shell publication"

custom_home="$test_root/custom-home"
install -d "$custom_home"
printf 'export CUSTOM_ONLY=yes\n' >"$custom_home/.bashrc"
run_owner "$custom_home"
# shellcheck disable=SC2016
[[ $(grep -Fxc 'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$custom_home/.bashrc") == 1 ]] || fail "custom Bash runtime source"
grep -Fqx 'export CUSTOM_ONLY=yes' "$custom_home/.bashrc" ||
  fail "custom Bash content preservation"

unsafe_home="$test_root/unsafe-home"
outside="$test_root/outside-bashrc"
install -d "$unsafe_home"
printf 'outside\n' >"$outside"
ln -s "$outside" "$unsafe_home/.bashrc"
if run_owner "$unsafe_home" >/dev/null 2>&1; then
  fail "linked Bash configuration accepted"
fi
[[ $(<"$outside") == "outside" ]] || fail "linked Bash target changed"

completion_output=$(HOME="$custom_home" QVOS_PATH="$root" \
  PATH="$root/bin:/usr/bin" bash --noprofile --norc -c \
  'source "$QVOS_PATH/qvcore/shell/files/completions"; complete -p qv; complete -p omarchy')
grep -Fq 'complete -o default -F _qvos_complete qv' <<<"$completion_output" ||
  fail "native qv completion"
grep -Fq 'complete -o default -F _qvos_complete omarchy' <<<"$completion_output" ||
  fail "compatibility completion"

printf 'ok - qvOS Bash ownership is minimal, atomic, and preservation-safe\n'
