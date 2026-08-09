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
# shellcheck disable=SC2016
grep -Fq 'omarchy_mirror="${QVOS_OMARCHY_MIRROR:-stable}"' \
  "$root/release/iso/build" ||
  fail "release image does not default to the installed Stable channel"
grep -Fq 'omarchy_mirror=edge' "$root/release/iso/build" ||
  fail "release image lacks the explicit development channel"
grep -Fq 'omarchy_mirror=rc' "$root/release/iso/build" ||
  fail "release image lacks the explicit release-candidate channel"
set +e
invalid_channel_output=$(
  QVOS_OMARCHY_MIRROR='../edge' \
    "$root/release/iso/build" --prepare-only 2>&1
)
invalid_channel_status=$?
set -e
((invalid_channel_status == 2)) ||
  fail "release image invalid-channel status"
grep -Fq 'QVOS_OMARCHY_MIRROR must be stable, edge, or rc.' \
  <<<"$invalid_channel_output" ||
  fail "release image accepts an unvalidated package channel"
grep -Fq 'release/iso/source-permissions' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "ISO patch bypasses release source-permission policy"
[[ $(<"$root/release/iso/upstream-ref") =~ ^[0-9a-f]{40}$ ]] ||
  fail "release ISO reviewed upstream ref"
# shellcheck disable=SC2016
grep -Fq 'omarchy_iso_ref="${QVOS_OMARCHY_ISO_REF:-$reviewed_iso_ref}"' \
  "$root/release/iso/build" || fail "release ISO defaults to reviewed ref"
# shellcheck disable=SC2016
grep -Fq 'clone_git_source "$omarchy_iso_repo" "$omarchy_iso_ref" "$target"' \
  "$root/release/iso/build" || fail "local ISO source bypasses reviewed ref"
# shellcheck disable=SC2016
grep -Fq 'if [[ ! -d $target/qvcore/install ]]; then' \
  "$root/release/iso/build" || fail "release ISO native install validation"
# shellcheck disable=SC2016
grep -Fq 'if [[ ! -d $target/qvcore/boot/login ]]; then' \
  "$root/release/iso/build" || fail "release ISO native login validation"
if grep -Fq 'missing install/' "$root/release/iso/build"; then
  fail "release ISO requires the retired install tree"
fi
if sed -n '/^+/p' "$root/release/iso/omarchy-iso-qvos-tui.patch" |
  grep -Fq '/var/log/omarchy-install.log'; then
  fail "release ISO activates the retired installer log identity"
fi
grep -Fq '/var/log/qvos-install.log' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "release ISO native installer log identity"
# shellcheck disable=SC2016
grep -Fq 'validate_staged_iso "$staged_iso"' "$root/release/iso/build" ||
  fail "release ISO staged trust validation"
grep -Fq 'fallback configurator without native helpers' "$root/release/iso/build" ||
  fail "release ISO fallback helper validation"
# shellcheck disable=SC2016
grep -Fq -- '-v "$staged_qvos:/qvos:ro"' "$root/release/iso/build" ||
  fail "release ISO pinned qvOS source mount"
grep -Fq 'package_file.sig' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "release ISO detached package signature retention"
grep -Fq 'Server = file:///var/cache/qvos/mirror/offline/' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "release ISO native offline cache path"
grep -Fq 'qvOS cannot safely install on T2 Macs' \
  "$root/release/iso/omarchy-iso-qvos-tui.patch" ||
  fail "release ISO fallback T2 refusal"
if sed -n '/^+/p' "$root/release/iso/omarchy-iso-qvos-tui.patch" |
  rg -q 'SigLevel[[:space:]]*=[[:space:]]*Never|TrustAll|arch-mact2|linux-t2'; then
  fail "release ISO activates weak package trust or an unsupported T2 kernel"
fi
if rg -q 'copy_tree|fresh-cloning ISO builder source local' "$root/release/iso/build"; then
  fail "local ISO source bypass remains"
fi
if grep -Fq 'QVOS_OMARCHY_ISO_REF:-main' "$root/release/iso/build"; then
  fail "release ISO follows a floating upstream branch"
fi

expected=$'.gitattributes\nAGENTS.md\nREADME.md\nbuild\nomarchy-iso-qvos-tui.patch\nsource-permissions\nsyslinux-splash.png\nupstream-ref'
actual=$(find "$root/release/iso" -maxdepth 1 -type f -printf '%f\n' | sort)
[[ $actual == "$expected" ]] || fail "release/iso source inventory"

printf 'ok - image construction has one release owner and one thin TUI adapter\n'
