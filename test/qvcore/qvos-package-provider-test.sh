#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

"$root/qvcore/packages/check" >/dev/null

[[ ! -e $root/default && ! -L $root/default ]] || {
  echo "not ok - inherited default source tree remains" >&2
  exit 1
}

[[ -x $root/qvcore/packages/configure ]] || {
  echo "not ok - native Stable package configuration owner" >&2
  exit 1
}
for adapter in qv-refresh-pacman omarchy-refresh-pacman; do
  grep -Fq 'qvcore/packages/configure' "$root/bin/$adapter" || {
    echo "not ok - package refresh bypasses the native provider owner: $adapter" >&2
    exit 1
  }
done
grep -Fq 'qvcore/packages/AGENTS.md' "$root/AGENTS.md" || {
  echo "not ok - package-provider workflow is not routed" >&2
  exit 1
}
grep -Fq 'default/pacman/' "$root/upstream/qvsync/package-provider-paths" || {
  echo "not ok - qvsync stopped monitoring the upstream provider source" >&2
  exit 1
}
grep -Fq 'package-provider-paths' "$root/upstream/qvsync/qvsync" || {
  echo "not ok - qvsync does not require the provider contract" >&2
  exit 1
}
grep -Fq 'Omarchy package-provider signals' \
  "$root/upstream/qvsync/qvsync-audit" || {
  echo "not ok - qvsync omits provider compatibility signals" >&2
  exit 1
}
if output=$(OMARCHY_PATH="$root" "$root/qvcore/packages/configure" edge 2>&1); then
  echo "not ok - installed package channel accepts Edge" >&2
  exit 1
fi
grep -Fq 'qvOS supports only the Omarchy Stable package channel.' \
  <<<"$output" || {
  echo "not ok - unsupported package channel refusal" >&2
  exit 1
}
provider_fixture="$test_root/qvcore/packages"
mkdir -p "$provider_fixture"
cp -a "$root/qvcore/packages/provider" "$provider_fixture/provider"
cp "$root/qvcore/packages/provider-files" "$provider_fixture/provider-files"
sed -i 's/Required DatabaseOptional/Optional TrustAll/' \
  "$provider_fixture/provider/omarchy/pacman-stable.conf"
if "$provider_fixture/provider-files" stable >/dev/null 2>&1; then
  echo "not ok - provider resolver accepts weakened local source" >&2
  exit 1
fi
if rg -n 'Optional[[:space:]]+TrustAll|SigLevel[[:space:]]*=[[:space:]]*Never' \
  "$root/qvcore/packages/provider/omarchy"; then
  echo "not ok - native provider source contains weak signature policy" >&2
  exit 1
fi
# shellcheck disable=SC2016
grep -Fq 'omarchy_mirror="${QVOS_OMARCHY_MIRROR:-stable}"' \
  "$root/release/iso/build" || {
  echo "not ok - production ISO does not default to Stable" >&2
  exit 1
}

printf 'ok - qvOS owns package policy while Omarchy remains the credited Stable provider\n'
