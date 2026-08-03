#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

"$root/qvcore/packages/check" >/dev/null

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

printf 'ok - qvOS owns package policy while Omarchy remains the credited Stable provider\n'
