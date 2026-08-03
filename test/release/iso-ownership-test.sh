#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

[[ ! -e $root/qvcore/iso ]] || fail "ISO implementation remains in qvCORE"
[[ -x $root/release/iso/build ]] || fail "release-owned image builder"
[[ -x $root/qvcore/tui/bin/qvos-build ]] || fail "installed image-build adapter"
(( $(wc -l <"$root/qvcore/tui/bin/qvos-build") <= 15 )) ||
  fail "TUI image-build adapter contains release implementation"
grep -Fq 'release/iso/build' "$root/qvcore/tui/bin/qvos-build" ||
  fail "TUI adapter bypasses the release owner"
grep -Fq 'release/iso/omarchy-iso-qvos-tui.patch' "$root/release/iso/build" ||
  fail "image builder bypasses its release patch"
grep -Fq 'release/iso/source-permissions' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "ISO patch bypasses release source-permission policy"
[[ $(<"$root/release/iso/upstream-ref") =~ ^[0-9a-f]{40}$ ]] ||
  fail "release ISO reviewed upstream ref"
# shellcheck disable=SC2016
grep -Fq 'omarchy_iso_ref="${QVOS_OMARCHY_ISO_REF:-$reviewed_iso_ref}"' \
  "$root/release/iso/build" || fail "release ISO defaults to reviewed ref"
if grep -Fq 'QVOS_OMARCHY_ISO_REF:-main' "$root/release/iso/build"; then
  fail "release ISO follows a floating upstream branch"
fi

expected=$'.gitattributes\nAGENTS.md\nREADME.md\nbuild\nomarchy-iso-qvos-tui.patch\nsource-permissions\nsyslinux-splash.png\nupstream-ref'
actual=$(find "$root/release/iso" -maxdepth 1 -type f -printf '%f\n' | sort)
[[ $actual == "$expected" ]] || fail "release/iso source inventory"

printf 'ok - image construction has one release owner and one thin TUI adapter\n'
