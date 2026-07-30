#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
repo="$test_root/repo"
origin_bare="$test_root/origin.git"
upstream_bare="$test_root/upstream.git"
upstream_work="$test_root/upstream-work"

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

mkdir -p "$repo/qv/git" "$repo/qv/menu" "$repo/qv/tui"
cp \
  "$root/qv/git/qvsync" \
  "$root/qv/git/qvsync-audit" \
  "$root/qv/git/install-qvsync" \
  "$repo/qv/git/"
chmod 0755 \
  "$repo/qv/git/qvsync" \
  "$repo/qv/git/qvsync-audit" \
  "$repo/qv/git/install-qvsync"
printf '%s\n' '# qvOS menu owner' 'omarchy-menu' >"$repo/qv/menu/extension.sh"
printf '%s\n' \
  '# owner|uses|sources' \
  'omarchy-menu|task:menu|bin/omarchy-menu@fixture' \
  >"$repo/qv/tui/owner-contracts.psv"

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

git init --bare -q "$origin_bare"
git init --bare -q "$upstream_bare"
git -C "$repo" remote add origin "$origin_bare"
git -C "$repo" remote add upstream "$upstream_bare"
git -C "$repo" remote set-url --push upstream DISABLED
git -C "$repo" push -q origin master OS
git -C "$repo" push -q "$upstream_bare" master

git clone -q "$upstream_bare" "$upstream_work"
git -C "$upstream_work" config user.name "Upstream Test"
git -C "$upstream_work" config user.email "upstream@qvos.invalid"
mkdir -p "$upstream_work/bin"
printf '%s\n' '#!/bin/bash' 'printf "upstream menu\\n"' \
  >"$upstream_work/bin/omarchy-menu"
chmod 0755 "$upstream_work/bin/omarchy-menu"
git -C "$upstream_work" add bin/omarchy-menu
git -C "$upstream_work" commit -qm "Replace the menu architecture"
git -C "$upstream_work" push -q origin master

base_sha=$(git -C "$repo" rev-parse HEAD)
upstream_sha=$(git -C "$upstream_work" rev-parse HEAD)

output=$(git -C "$repo" qvsync --audit 2>&1) ||
  fail "read-only upstream capability audit"
grep -Fq 'qvOS upstream capability audit' <<<"$output" ||
  fail "capability audit heading"
grep -Fq "$upstream_sha Replace the menu architecture" <<<"$output" ||
  fail "capability audit commit inventory"
grep -Fq $'A\tbin/omarchy-menu' <<<"$output" ||
  fail "capability audit changed path"
grep -Fq 'qv/menu/extension.sh' <<<"$output" ||
  fail "capability audit qvOS overlap hint"
grep -Fq \
  'bin/omarchy-menu — contracted TUI owner changed upstream; review qv/tui/owner-contracts.psv before refreshing it' \
  <<<"$output" ||
  fail "capability audit TUI owner contract hint"
grep -Fq 'Upstream roadmap signals (advisory only; never merged by qvsync)' \
  <<<"$output" ||
  fail "capability audit roadmap boundary"
grep -Fq 'adopt, combine, retire-qvos, preserve, or no-impact' <<<"$output" ||
  fail "capability audit decision contract"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/master) == "$base_sha" ]] ||
  fail "audit mutated origin master"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/OS) == "$base_sha" ]] ||
  fail "audit mutated origin OS"
pass "audit exposes complete upstream changes and qvOS overlap without publishing"

if output=$(git -C "$repo" qvsync 2>&1); then
  fail "unreviewed upstream publish guard"
fi
grep -Fq 'upstream capability review is required' <<<"$output" ||
  fail "unreviewed upstream diagnostic"
grep -Fq "git qvsync --reviewed-upstream $upstream_sha" <<<"$output" ||
  fail "exact review retry"
[[ $(git -C "$repo" rev-parse HEAD) == "$base_sha" ]] ||
  fail "unreviewed qvsync changed local OS"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/master) == "$base_sha" ]] ||
  fail "unreviewed qvsync changed origin master"
pass "qvsync refuses merge and publish until Codex reviews the exact upstream target"

if output=$(git -C "$repo" qvsync --reviewed-upstream "$base_sha" 2>&1); then
  fail "stale upstream review guard"
fi
grep -Fq 'reviewed upstream SHA does not match the fetched target' <<<"$output" ||
  fail "stale upstream review diagnostic"
grep -Fq "Fetched:  $upstream_sha" <<<"$output" ||
  fail "refreshed upstream review target"
pass "stale review approval cannot authorize a newer upstream target"

git -C "$repo" qvsync --reviewed-upstream "$upstream_sha" >/dev/null
git -C "$repo" merge-base --is-ancestor "$upstream_sha" HEAD ||
  fail "reviewed upstream merge"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/master) == "$upstream_sha" ]] ||
  fail "reviewed origin master update"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/OS) == \
  "$(git -C "$repo" rev-parse HEAD)" ]] ||
  fail "reviewed origin OS publish"
pass "exact reviewed upstream target can merge and publish"

grep -Eq 'Start with .*git qvsync --audit' "$root/AGENTS.md" ||
  fail "Codex qvsync audit instruction"
grep -Fq 'retire-qvos' "$root/AGENTS.md" ||
  fail "Codex capability decision ledger"
grep -Fq 'maintainer roadmaps as advisory signals' "$root/AGENTS.md" ||
  fail "Codex upstream roadmap instruction"
grep -Fq 'remove superseded source' "$root/AGENTS.md" ||
  fail "Codex superseded implementation cleanup"
grep -Fq 'complete its software reconciliation' "$root/qv/git/AGENTS.md" ||
  fail "qvsync software reconciliation route"
grep -Fq 'qvOS as an overlay on Omarchy' "$root/AGENTS.md" ||
  fail "root overlay ownership contract"
grep -Fq 'qv/<feature>/' "$root/AGENTS.md" ||
  fail "root feature ownership contract"
grep -Fq 'Never move them out' "$root/AGENTS.md" ||
  fail "root workflow retention contract"
grep -Fq "automatically create or update the nearest owner-local \`AGENTS.md\`" \
  "$root/AGENTS.md" || fail "conditional workflow documentation contract"
grep -Fq 'conditional or multi-stage' "$root/AGENTS.md" ||
  fail "conditional workflow creation threshold"
grep -Fq 'safety invariant, or UX' "$root/AGENTS.md" ||
  fail "owner-local reusable learning contract"
workflow_count=0
while IFS= read -r -d '' workflow_agents; do
  workflow_agents=${workflow_agents#"$root/"}
  grep -Fq "$workflow_agents" "$root/AGENTS.md" ||
    fail "missing root workflow route: $workflow_agents"
  workflow_count=$((workflow_count + 1))
done < <(
  find "$root" -mindepth 2 -type f -name AGENTS.md \
    -not -path "$root/.git/*" -print0 | sort -z
)
((workflow_count >= 5)) || fail "owner-local workflow discovery"
qvos_policy_lines=$(
  sed -n '/^# qvOS Additions$/,$p' "$root/AGENTS.md" | wc -l
)
qvos_policy_bytes=$(
  sed -n '/^# qvOS Additions$/,$p' "$root/AGENTS.md" | wc -c
)
((qvos_policy_lines <= 110)) ||
  fail "root qvOS contract grew beyond 110 lines"
((qvos_policy_bytes <= 7000)) ||
  fail "root qvOS contract grew beyond 7000 bytes"
pass "root keeps qvsync and overlay policy while conditional workflows stay local"
