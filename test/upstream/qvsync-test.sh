#!/bin/bash
set -euo pipefail
export LC_ALL=C

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
repo="$test_root/repo"
origin_bare="$test_root/origin.git"
upstream_bare="$test_root/upstream.git"
upstream_work="$test_root/upstream-work"
iso_upstream_bare="$test_root/iso-upstream.git"
iso_upstream_work="$test_root/iso-upstream-work"

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

mkdir -p "$repo/upstream/qvsync" "$repo/qvcore/menu" "$repo/qvcore/tui"
cp \
  "$root/upstream/qvsync/qvsync" \
  "$root/upstream/qvsync/qvsync-audit" \
  "$root/upstream/qvsync/install-qvsync" \
  "$root/upstream/qvsync/package-provider-paths" \
  "$root/upstream/qvsync/reviewed-iso-upstream" \
  "$repo/upstream/qvsync/"
chmod 0755 \
  "$repo/upstream/qvsync/qvsync" \
  "$repo/upstream/qvsync/qvsync-audit" \
  "$repo/upstream/qvsync/install-qvsync"
printf '%s\n' '# qvOS menu routes' 'qv-menu' >"$repo/qvcore/menu/routes"
printf '%s\n' \
  '# owner|uses|sources' \
  'omarchy-menu|task:menu|bin/omarchy-menu@fixture' \
  >"$repo/qvcore/tui/owner-contracts.psv"

git -C "$repo" init -q
git -C "$repo" config user.name "qvOS Test"
git -C "$repo" config user.email "test@qvos.invalid"
git -C "$repo" add qvcore upstream
git -C "$repo" commit -qm "Add qvsync fixture"
base_sha=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' "$base_sha" >"$repo/upstream/qvsync/reviewed-upstream"
printf '%s\n' "$base_sha" >"$repo/upstream/qvsync/reviewed-iso-upstream"
git -C "$repo" add \
  upstream/qvsync/reviewed-upstream \
  upstream/qvsync/reviewed-iso-upstream
git -C "$repo" commit -qm "Record upstream baseline"
git -C "$repo" switch -qc OS
os_head=$(git -C "$repo" rev-parse HEAD)

# Invoke by absolute path from outside the repository. The installer must own
# the checkout containing its source, never whichever repository is the shell's
# current directory.
(
  cd "$test_root"
  "$repo/upstream/qvsync/install-qvsync"
)

# shellcheck disable=SC2016
[[ $(git -C "$repo" config --local --get alias.qvsync) == '!bash "$(git rev-parse --git-path qvsync)"' ]] ||
  fail "git qvsync alias"
# shellcheck disable=SC2016
grep -Fq 'exec "$repo_root/upstream/qvsync/qvsync" "$@"' "$repo/.git/qvsync" ||
  fail "tracked qvsync dispatch"
[[ $(git -C "$repo" remote get-url upstream) == \
  "https://github.com/basecamp/omarchy.git" ]] ||
  fail "official Omarchy review remote"
[[ $(git -C "$repo" remote get-url --push upstream) == "DISABLED" ]] ||
  fail "Omarchy review push guard"
[[ $(git -C "$repo" remote get-url upstream-iso) == \
  "https://github.com/omacom-io/omarchy-iso.git" ]] ||
  fail "official Omarchy ISO review remote"
[[ $(git -C "$repo" remote get-url --push upstream-iso) == "DISABLED" ]] ||
  fail "Omarchy ISO review push guard"
pass "installer keeps the executable implementation in tracked source"

if rg -q 'git merge( |$)|git push( |$)|git_push|push_origin_ref|push_os' \
  "$root/upstream/qvsync/qvsync"; then
  fail "qvsync retains merge or publication machinery"
fi
if rg -q 'require_upstream_policy_parity|inherited AGENTS.md policy block' \
  "$root/upstream/qvsync/qvsync"; then
  fail "qvsync still treats upstream instructions as qvOS authority"
fi
grep -Fq 'qvsync never publishes' "$root/upstream/qvsync/AGENTS.md" ||
  fail "read-only upstream publication instruction"
pass "qvsync contains no merge or publication path"

mkdir "$repo/.git/qvsync.lock"
printf '%s\n' "$$" >"$repo/.git/qvsync.lock/pid"
if output=$(git -C "$repo" qvsync 2>&1); then
  fail "active qvsync lock refusal"
fi
grep -Fq 'another qvsync appears to be running' <<<"$output" ||
  fail "active qvsync lock diagnostic"
[[ -d $repo/.git/qvsync.lock ]] || fail "active qvsync lock was removed"
rm -rf "$repo/.git/qvsync.lock"
pass "active qvsync lock is preserved and reported"

git -C "$repo" remote set-url upstream "$test_root/pending-upstream.git"
git -C "$repo" remote set-url --push upstream "$test_root/pending-upstream.git"
mkdir "$repo/.git/qvsync.lock"
printf '%s\n' 99999999 >"$repo/.git/qvsync.lock/pid"
if output=$(git -C "$repo" qvsync 2>&1); then
  fail "missing upstream push guard"
fi
grep -Fq 'Removing stale qvsync lock' <<<"$output" ||
  fail "stale qvsync lock recovery"
grep -Fq 'upstream push URL is not disabled' <<<"$output" ||
  fail "upstream push guard diagnostic"
grep -Fq 'Expected upstream push URL: DISABLED' <<<"$output" ||
  fail "upstream push remediation"
[[ ! -e $repo/.git/qvsync.lock ]] || fail "recovered qvsync lock cleanup"
pass "stale lock recovery retains the upstream write guard"

git init --bare -q "$origin_bare"
git init --bare -q "$upstream_bare"
git init --bare -q "$iso_upstream_bare"
git -C "$repo" remote add origin "$origin_bare"
git -C "$repo" remote set-url upstream "$upstream_bare"
git -C "$repo" remote set-url --push upstream DISABLED
git -C "$repo" remote set-url upstream-iso "$iso_upstream_bare"
git -C "$repo" push -q origin "$base_sha:refs/heads/master" "OS:refs/heads/OS"
git -C "$repo" push -q "$upstream_bare" "$base_sha:refs/heads/master"
git -C "$repo" push -q "$iso_upstream_bare" "$base_sha:refs/heads/quattro"

git clone -q "$upstream_bare" "$upstream_work"
git -C "$upstream_work" config user.name "Upstream Test"
git -C "$upstream_work" config user.email "upstream@qvos.invalid"
mkdir -p "$upstream_work/bin" "$upstream_work/default/pacman"
printf '%s\n' '#!/bin/bash' 'printf "upstream menu\n"' \
  >"$upstream_work/bin/omarchy-menu"
chmod 0755 "$upstream_work/bin/omarchy-menu"
# shellcheck disable=SC2016
printf '%s\n' 'Server = https://stable-mirror.omarchy.org/$repo/os/$arch' \
  >"$upstream_work/default/pacman/mirrorlist-stable"
git -C "$upstream_work" add bin/omarchy-menu default/pacman/mirrorlist-stable
git -C "$upstream_work" commit -qm "Replace the menu architecture"
git -C "$upstream_work" push -q origin master
upstream_sha=$(git -C "$upstream_work" rev-parse HEAD)

git clone -q -b quattro "$iso_upstream_bare" "$iso_upstream_work"
git -C "$iso_upstream_work" config user.name "ISO Upstream Test"
git -C "$iso_upstream_work" config user.email "iso-upstream@qvos.invalid"
mkdir -p "$iso_upstream_work/builder" "$iso_upstream_work/configs/airootfs/root"
printf '%s\n' '#!/bin/bash' 'printf "iso builder fix\n"' \
  >"$iso_upstream_work/builder/build-iso.sh"
printf '%s\n' '#!/bin/bash' 'printf "install fix\n"' \
  >"$iso_upstream_work/configs/airootfs/root/.automated_script.sh"
chmod 0755 \
  "$iso_upstream_work/builder/build-iso.sh" \
  "$iso_upstream_work/configs/airootfs/root/.automated_script.sh"
git -C "$iso_upstream_work" add builder configs
git -C "$iso_upstream_work" commit -qm "Fix ISO package installation"
git -C "$iso_upstream_work" push -q origin quattro
iso_upstream_sha=$(git -C "$iso_upstream_work" rev-parse HEAD)

output=$(git -C "$repo" qvsync 2>&1) ||
  fail "default read-only upstream audit"
grep -Fq 'qvOS upstream capability audit' <<<"$output" ||
  fail "capability audit heading"
grep -Fq "$upstream_sha Replace the menu architecture" <<<"$output" ||
  fail "capability audit commit inventory"
grep -Fq $'A\tbin/omarchy-menu' <<<"$output" ||
  fail "capability audit changed path"
grep -Fq 'qvcore/menu/routes' <<<"$output" ||
  fail "capability audit qvOS overlap hint"
grep -Fq \
  'bin/omarchy-menu — contracted TUI owner changed upstream; review qvcore/tui/owner-contracts.psv before refreshing it' \
  <<<"$output" ||
  fail "capability audit TUI owner contract hint"
grep -Fq 'Omarchy package-provider signals' <<<"$output" ||
  fail "capability audit provider heading"
grep -Fq \
  'default/pacman/mirrorlist-stable — verify Omarchy provider compatibility and qvOS package selection' \
  <<<"$output" || fail "capability audit provider compatibility signal"
grep -Fq 'Upstream roadmap signals (advisory only; never merged by qvsync)' \
  <<<"$output" ||
  fail "capability audit roadmap boundary"
grep -Fq 'adopt, combine, retire-qvos, preserve, or no-impact' <<<"$output" ||
  fail "capability audit decision contract"
grep -Fq 'Never merge or cherry-pick the upstream commit into qvOS' <<<"$output" ||
  fail "capability audit native import boundary"
grep -Fq 'qvOS Omarchy ISO capability audit' <<<"$output" ||
  fail "ISO capability audit heading"
grep -Fq "$iso_upstream_sha Fix ISO package installation" <<<"$output" ||
  fail "ISO capability audit commit inventory"
grep -Fq $'A\tbuilder/build-iso.sh' <<<"$output" ||
  fail "ISO capability audit changed path"
grep -Fq \
  'Omarchy ISO is review input only; port selected changes into release/iso/.' \
  <<<"$output" || fail "ISO native ownership boundary"
grep -Fq 'upstream/qvsync/iso-upstream-reviews/<target-sha>.psv' \
  <<<"$output" || fail "ISO review ledger route"
[[ $(git -C "$repo" rev-parse HEAD) == "$os_head" ]] ||
  fail "audit changed local OS"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/master) == "$base_sha" ]] ||
  fail "audit mutated origin master"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/OS) == "$os_head" ]] ||
  fail "audit mutated origin OS"
[[ $(git --git-dir="$iso_upstream_bare" rev-parse refs/heads/quattro) == \
  "$iso_upstream_sha" ]] || fail "audit mutated ISO upstream"
pass "default qvsync audits both upstreams without integrating or publishing"

if output=$(git -C "$repo" qvsync --reviewed-upstream "$upstream_sha" 2>&1); then
  fail "retired merge mode refusal"
fi
grep -Fq -- '--reviewed-upstream merge mode has been retired' <<<"$output" ||
  fail "retired merge mode diagnostic"
grep -Fq "git qvsync --record-reviewed-upstream $upstream_sha" <<<"$output" ||
  fail "reviewed import migration guidance"
pass "legacy merge authorization cannot integrate upstream"

if output=$(git -C "$repo" qvsync --record-reviewed-upstream "$base_sha" 2>&1); then
  fail "stale upstream review guard"
fi
grep -Fq 'reviewed upstream SHA does not match the fetched target' <<<"$output" ||
  fail "stale upstream review diagnostic"
grep -Fq "Fetched:  $upstream_sha" <<<"$output" ||
  fail "refreshed upstream review target"
[[ $(<"$repo/upstream/qvsync/reviewed-upstream") == "$base_sha" ]] ||
  fail "stale review changed tracked baseline"
pass "stale review cannot advance the upstream baseline"

if output=$(
  git -C "$repo" qvsync --record-reviewed-upstream "$upstream_sha" 2>&1
); then
  fail "missing upstream ledger guard"
fi
grep -Fq 'missing upstream review ledger' <<<"$output" ||
  fail "missing upstream ledger diagnostic"

mkdir -p "$repo/upstream/qvsync/upstream-reviews"
ledger="$repo/upstream/qvsync/upstream-reviews/$upstream_sha.psv"
printf '%s\n' \
  "# base=$base_sha" \
  "# target=$upstream_sha" \
  '# commit|decision|owner|summary|verification' \
  >"$ledger"
if output=$(
  git -C "$repo" qvsync --record-reviewed-upstream "$upstream_sha" 2>&1
); then
  fail "incomplete upstream ledger guard"
fi
grep -Fq 'upstream commit is missing from the review ledger' <<<"$output" ||
  fail "incomplete upstream ledger diagnostic"
pass "review state requires a complete per-commit ledger"

printf '%s\n' \
  "$upstream_sha|combine|qvcore/menu|Port the reviewed menu capability|fixture audit and owner checks" \
  >>"$ledger"
output=$(
  git -C "$repo" qvsync --record-reviewed-upstream "$upstream_sha" 2>&1
) || fail "record exact reviewed upstream target"
grep -Fq "Recorded reviewed upstream target $upstream_sha" <<<"$output" ||
  fail "reviewed upstream record result"
grep -Fq 'No upstream commit was merged or cherry-picked, and no ref was published' \
  <<<"$output" || fail "reviewed upstream non-integration result"
[[ $(<"$repo/upstream/qvsync/reviewed-upstream") == "$upstream_sha" ]] ||
  fail "tracked reviewed baseline"
[[ $(git -C "$repo" rev-parse HEAD) == "$os_head" ]] ||
  fail "recording review changed local OS history"
if git -C "$repo" merge-base --is-ancestor "$upstream_sha" HEAD; then
  fail "recording review merged upstream"
fi
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/master) == "$base_sha" ]] ||
  fail "recording review mutated origin master"
[[ $(git --git-dir="$origin_bare" rev-parse refs/heads/OS) == "$os_head" ]] ||
  fail "recording review mutated origin OS"
pass "validated review advances only tracked intake state"

if output=$(
  git -C "$repo" qvsync --record-reviewed-iso-upstream "$base_sha" 2>&1
); then
  fail "stale ISO upstream review guard"
fi
grep -Fq 'reviewed ISO upstream SHA does not match the fetched target' \
  <<<"$output" || fail "stale ISO upstream review diagnostic"
[[ $(<"$repo/upstream/qvsync/reviewed-iso-upstream") == "$base_sha" ]] ||
  fail "stale ISO review changed tracked baseline"

if output=$(
  git -C "$repo" qvsync --record-reviewed-iso-upstream "$iso_upstream_sha" 2>&1
); then
  fail "missing ISO upstream ledger guard"
fi
grep -Fq 'missing ISO upstream review ledger' <<<"$output" ||
  fail "missing ISO upstream ledger diagnostic"

mkdir -p "$repo/upstream/qvsync/iso-upstream-reviews"
iso_ledger="$repo/upstream/qvsync/iso-upstream-reviews/$iso_upstream_sha.psv"
printf '%s\n' \
  "# base=$base_sha" \
  "# target=$iso_upstream_sha" \
  '# commit|decision|owner|summary|verification' \
  "$iso_upstream_sha|combine|release/iso|Port the reviewed ISO fix|native ISO ownership checks" \
  >"$iso_ledger"
output=$(
  git -C "$repo" qvsync --record-reviewed-iso-upstream "$iso_upstream_sha" 2>&1
) || fail "record exact reviewed ISO upstream target"
grep -Fq "Recorded reviewed ISO upstream target $iso_upstream_sha" \
  <<<"$output" || fail "reviewed ISO upstream record result"
[[ $(<"$repo/upstream/qvsync/reviewed-iso-upstream") == \
  "$iso_upstream_sha" ]] || fail "tracked reviewed ISO baseline"
[[ $(git -C "$repo" rev-parse HEAD) == "$os_head" ]] ||
  fail "recording ISO review changed local OS history"
if git -C "$repo" merge-base --is-ancestor "$iso_upstream_sha" HEAD; then
  fail "recording ISO review merged upstream"
fi
[[ $(git --git-dir="$iso_upstream_bare" rev-parse refs/heads/quattro) == \
  "$iso_upstream_sha" ]] || fail "recording review mutated ISO upstream"
pass "validated ISO review advances only its independent tracked baseline"

output=$(git -C "$repo" qvsync --audit 2>&1) ||
  fail "post-review upstream audit"
grep -Fq 'Upstream commits (0)' <<<"$output" ||
  fail "reviewed baseline audit range"
grep -Fq 'ISO upstream commits (0)' <<<"$output" ||
  fail "reviewed ISO baseline audit range"
pass "future audits start at both independent reviewed baselines"

grep -Eq 'Start with .*git qvsync --audit' "$root/AGENTS.md" ||
  fail "Codex qvsync audit instruction"
grep -Fq 'retire-qvos' "$root/AGENTS.md" ||
  fail "Codex capability decision ledger"
grep -Fq 'maintainer roadmaps as advisory signals' "$root/AGENTS.md" ||
  fail "Codex upstream roadmap instruction"
grep -Fq 'remove duplicate implementations' "$root/upstream/qvsync/qvsync-audit" ||
  fail "Codex duplicate implementation cleanup"
grep -Fq 'reviewed-iso-upstream' "$root/AGENTS.md" ||
  fail "root independent ISO upstream baseline"
grep -Fq -- '--record-reviewed-iso-upstream' \
  "$root/upstream/qvsync/qvsync" \
  "$root/upstream/qvsync/README.md" \
  "$root/upstream/qvsync/AGENTS.md" ||
  fail "qvsync ISO review recording contract"
if rg -q 'release/iso/(upstream-ref|omarchy-iso-qvos-tui\.patch)|QVOS_OMARCHY_ISO' \
  "$root/upstream/qvsync"; then
  fail "qvsync restored the executable ISO upstream seam"
fi
grep -Fq 'complete its software reconciliation' "$root/upstream/qvsync/AGENTS.md" ||
  fail "qvsync software reconciliation route"
grep -Fq 'independent downstream distribution' "$root/AGENTS.md" ||
  fail "root downstream product contract"
grep -Fq 'never product authority' "$root/AGENTS.md" ||
  fail "root upstream authority boundary"
grep -Fq 'Never move them out' "$root/AGENTS.md" ||
  fail "root workflow retention contract"
grep -Fq "automatically create or update the nearest owner-local \`AGENTS.md\`" \
  "$root/AGENTS.md" || fail "conditional workflow documentation contract"
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
pass "root keeps downstream intake policy while conditional workflows stay local"
