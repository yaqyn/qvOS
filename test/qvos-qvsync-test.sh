#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
repo="$test_root/repo"

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

mkdir -p "$repo/qv/git"
cp "$root/qv/git/qvsync" "$root/qv/git/install-qvsync" "$repo/qv/git/"
chmod 0755 "$repo/qv/git/qvsync" "$repo/qv/git/install-qvsync"

git -C "$repo" init -q
git -C "$repo" config user.name "qvOS Test"
git -C "$repo" config user.email "test@qvos.invalid"
git -C "$repo" add qv
git -C "$repo" commit -qm "Add qvsync fixture"
git -C "$repo" switch -qc OS

(
  cd "$repo"
  qv/git/install-qvsync
)

# shellcheck disable=SC2016
[[ $(git -C "$repo" config --local --get alias.qvsync) == \
  '!bash "$(git rev-parse --git-path qvsync)"' ]] ||
  fail "git qvsync alias"
# shellcheck disable=SC2016
grep -Fq 'exec "$repo_root/qv/git/qvsync" "$@"' "$repo/.git/qvsync" ||
  fail "tracked qvsync dispatch"
pass "installer keeps the executable implementation in tracked source"

mkdir "$repo/.git/qvsync.lock"
printf '%s\n' "$$" >"$repo/.git/qvsync.lock/pid"
if output=$(git -C "$repo" qvsync 2>&1); then
  fail "active qvsync lock refusal"
fi
grep -Fq 'another qvsync appears to be running' <<<"$output" ||
  fail "active qvsync lock diagnostic"
rm -rf "$repo/.git/qvsync.lock"
pass "active qvsync lock is preserved and reported"

touch "$repo/dirty"
mkdir "$repo/.git/qvsync.lock"
printf '%s\n' 99999999 >"$repo/.git/qvsync.lock/pid"
if output=$(git -C "$repo" qvsync 2>&1); then
  fail "dirty qvsync refusal after stale lock recovery"
fi
grep -Fq 'Removing stale qvsync lock' <<<"$output" ||
  fail "stale qvsync lock recovery"
grep -Fq 'uncommitted changes on OS' <<<"$output" ||
  fail "dirty worktree diagnostic"
[[ ! -e $repo/.git/qvsync.lock ]] || fail "recovered qvsync lock cleanup"
rm "$repo/dirty"
pass "stale lock recovery retains the clean-tree guard"

if output=$(git -C "$repo" qvsync 2>&1); then
  fail "missing upstream push guard"
fi
grep -Fq 'upstream push URL is not disabled' <<<"$output" ||
  fail "upstream push guard diagnostic"
grep -Fq 'Expected upstream push URL: DISABLED' <<<"$output" ||
  fail "upstream push remediation"
pass "qvsync refuses before network access when upstream push is not disabled"
