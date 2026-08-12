#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
mirrorlist="$test_root/mirrorlist"
pacman_config="$test_root/pacman.conf"
pacman_log="$test_root/pacman.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

mkdir -p "$source_root"
git -C "$source_root" init -q -b OS
printf 'fixture\n' >"$source_root/payload"
git -C "$source_root" add payload
git -C "$source_root" \
  -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit -qm "Create version fixture"
source_commit=$(git -C "$source_root" rev-parse HEAD)
expected_version="rolling-${source_commit:0:12}"

[[ $(QVOS_VERSION_SOURCE_ROOT="$source_root" "$root/qvcore/version/current") == \
  "$expected_version" ]] || fail "installed rolling version derivation"
branch=$(QVOS_VERSION_SOURCE_ROOT="$source_root" "$root/qvcore/version/branch")
[[ $branch == "OS" ]] || fail "source branch reporting"

printf 'untracked\n' >"$source_root/untracked"
[[ $(QVOS_VERSION_SOURCE_ROOT="$source_root" "$root/qvcore/version/current") == \
  "$expected_version-dirty" ]] || fail "dirty rolling version reporting"
rm -- "$source_root/untracked"

linked_source="$test_root/linked-source"
ln -s "$source_root" "$linked_source"
if QVOS_VERSION_SOURCE_ROOT="$linked_source" \
  "$root/qvcore/version/current" >/dev/null 2>&1; then
  fail "symbolic source checkout accepted"
fi
mkdir "$source_root/nested"
if QVOS_VERSION_SOURCE_ROOT="$source_root/nested" \
  "$root/qvcore/version/current" >/dev/null 2>&1; then
  fail "nested source checkout accepted"
fi
rmdir "$source_root/nested"
empty_source="$test_root/empty-source"
git -C "$test_root" init -q -b OS empty-source
if QVOS_VERSION_SOURCE_ROOT="$empty_source" \
  "$root/qvcore/version/current" >/dev/null 2>&1; then
  fail "source checkout without a commit accepted"
fi
if QVOS_VERSION_SOURCE_ROOT="$empty_source" \
  "$root/qvcore/version/branch" >/dev/null 2>&1; then
  fail "branch accepted a source checkout without a commit"
fi

cat >"$mirrorlist" <<'EOF'
# Server = https://mirror.omarchy.org/$repo/os/$arch
Server = https://stable-mirror.omarchy.org/$repo/os/$arch
EOF
cat >"$pacman_config" <<'EOF'
# Server = https://pkgs.omarchy.org/stable/$arch
Server = https://pkgs.omarchy.org/edge/$arch
EOF
channel=$(
  QVOS_VERSION_MIRRORLIST="$mirrorlist" \
    QVOS_VERSION_PACMAN_CONF="$pacman_config" \
    "$root/qvcore/version/channel"
)
[[ $channel == "stable / edge" ]] || fail "mismatched package channel reporting"

# shellcheck disable=SC2016
printf 'Server = https://pkgs.omarchy.org/stable/$arch\n' >"$pacman_config"
channel=$(
  QVOS_VERSION_MIRRORLIST="$mirrorlist" \
    QVOS_VERSION_PACMAN_CONF="$pacman_config" \
    "$root/qvcore/version/channel"
)
[[ $channel == "stable" ]] || fail "Stable package channel reporting"

channel=$(
  QVOS_VERSION_MIRRORLIST="$test_root/missing-mirrorlist" \
    QVOS_VERSION_PACMAN_CONF="$test_root/missing-pacman.conf" \
    "$root/qvcore/version/channel"
)
[[ $channel == "unknown" ]] || fail "missing package channel reporting"

cat >"$pacman_log" <<'EOF'
[2026-08-01T10:00:00+0000] [ALPM] installed example (1.0-1)
[2026-08-02T11:12:13+0000] [ALPM] upgraded first (1.0-1 -> 1.0-2)
untrusted upgraded text [2026-08-04T00:00:00+0000]
[2026-08-03T03:32:59+0000] [ALPM] upgraded second (2.0-1 -> 2.0-2)
EOF
expected=$(LC_ALL=C TZ=UTC date --date='2026-08-03T03:32:59+0000' '+%A, %B %d %Y at %H:%M')
actual=$(LC_ALL=C TZ=UTC QVOS_VERSION_PACMAN_LOG="$pacman_log" "$root/qvcore/version/packages")
[[ $actual == "$expected" ]] || fail "latest exact package upgrade parsing"

: >"$pacman_log"
[[ $(QVOS_VERSION_PACMAN_LOG="$pacman_log" "$root/qvcore/version/packages") == "unknown" ]] ||
  fail "empty package history reporting"
printf '[malformed] [ALPM] upgraded example (1 -> 2)\n' >"$pacman_log"
[[ $(QVOS_VERSION_PACMAN_LOG="$pacman_log" "$root/qvcore/version/packages") == "unknown" ]] ||
  fail "malformed package history reporting"

for owner in current branch channel packages; do
  if "$root/qvcore/version/$owner" unexpected >/dev/null 2>&1; then
    fail "version $owner accepted unexpected arguments"
  fi
done

native=$(
  QVOS_PATH="$root" QVOS_VERSION_SOURCE_ROOT="$source_root" \
    "$root/bin/qv-version"
)
compatible=$(
  QVOS_PATH="$root" QVOS_VERSION_SOURCE_ROOT="$source_root" \
    "$root/bin/omarchy-version"
)
[[ $native == "$compatible" && $native == "$expected_version" ]] ||
  fail "version compatibility adapter parity"

"$root/qvcore/version/check"
printf 'ok - qvOS version reporting is validated, truthful, and fixture-safe\n'
