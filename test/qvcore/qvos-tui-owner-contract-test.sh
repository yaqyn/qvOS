#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
fixture="$test_root/fixture"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

"$root/qvcore/tui/owner-contracts" --check >/dev/null ||
  fail "tracked owner manifest drift"

install -d \
  "$fixture/applications" \
  "$fixture/bin" \
  "$fixture/qvcore/demo" \
  "$fixture/qvcore/demo/assets" \
  "$fixture/qvcore/menu" \
  "$fixture/qvcore/tui/task"
install -m 0644 /dev/stdin "$fixture/qvcore/tui/external-owners.psv" <<'EXTERNAL'
# command|reason
passwd|System account password owner
EXTERNAL
install -m 0644 /dev/stdin "$fixture/qvcore/tui/task/actions.psv" <<'TASKS'
# slug|title|summary|rings|behavior|presentation|requires_sudo|primary|active|complete|owner
test-task|Test Task|Exercise a delegated owner|1|information|tui|false||||omarchy test owner inspect
password|Password|Exercise an external owner|3|mutation|native|false|Change|Changing|Changed|passwd
TASKS
install -m 0644 /dev/stdin "$fixture/qvcore/menu/software-actions.psv" <<'SOFTWARE'
# slug|probe kind|probe value|install presentation|install sudo|uninstall presentation|uninstall sudo|install owner|uninstall owner
test-software|package|test|tui|true|tui|true|omarchy-software-install test|omarchy-software-remove test
SOFTWARE
install -m 0644 /dev/stdin "$fixture/qvcore/menu/software-installers.psv" <<'INSTALLERS'
# slug|icon|name|breadcrumb|keywords|presentation|sudo|probe kind|probe value|summary|owner
test-installer|x|Test|Settings|test|tui|true|package|test|Install test|qvcore/menu/install-test
INSTALLERS
install -m 0755 /dev/stdin "$fixture/bin/omarchy-test-owner" <<'OWNER'
#!/bin/bash
OMARCHY_PATH=${OMARCHY_PATH:?}
exec "$OMARCHY_PATH/qvcore/demo/owner" "$@"
OWNER
install -m 0755 /dev/stdin "$fixture/qvcore/demo/owner" <<'DOMAIN'
#!/bin/bash
# qvos:contract=applications/demo.desktop
# qvos:contract=qvcore/demo/assets
exec "$OMARCHY_PATH/qvcore/demo/readback"
DOMAIN
install -m 0644 /dev/stdin "$fixture/applications/demo.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Demo
DESKTOP
install -m 0644 /dev/stdin "$fixture/qvcore/demo/assets/message.txt" <<'ASSET'
Ready
ASSET
install -m 0755 /dev/stdin "$fixture/qvcore/demo/readback" <<'READBACK'
#!/bin/bash
printf 'State: Ready\n'
READBACK
for owner in omarchy-software-install omarchy-software-remove; do
  install -m 0755 /dev/stdin "$fixture/bin/$owner" <<'SOFTWARE_OWNER'
#!/bin/bash
printf 'software owner\n'
SOFTWARE_OWNER
done
install -m 0755 /dev/stdin "$fixture/qvcore/menu/install-test" <<'INSTALL_OWNER'
#!/bin/bash
printf 'installer owner\n'
INSTALL_OWNER

QVOS_OWNER_CONTRACT_ROOT="$fixture" \
  "$root/qvcore/tui/owner-contracts" --write >/dev/null
QVOS_OWNER_CONTRACT_ROOT="$fixture" \
  "$root/qvcore/tui/owner-contracts" --check >/dev/null ||
  fail "generated owner manifest check"

grep -Eq \
  '^omarchy test owner inspect\|task:test-task\|applications/demo.desktop@[0-9a-f]{64},bin/omarchy-test-owner@[0-9a-f]{64},qvcore/demo/assets/message.txt@[0-9a-f]{64},qvcore/demo/owner@[0-9a-f]{64},qvcore/demo/readback@[0-9a-f]{64}$' \
  "$fixture/qvcore/tui/owner-contracts.psv" ||
  fail "thin adapter and recursive qvOS dependencies are all contracted"
grep -Fq 'passwd|task:password|external@-' \
  "$fixture/qvcore/tui/owner-contracts.psv" ||
  fail "external native owner classification"
grep -Fq 'omarchy-software-install test|software:test-software:install|' \
  "$fixture/qvcore/tui/owner-contracts.psv" ||
  fail "paired Software install owner coverage"
grep -Fq 'qvcore/menu/install-test|installer:test-installer|' \
  "$fixture/qvcore/tui/owner-contracts.psv" ||
  fail "install-only owner coverage"

printf '\n# changed nested owner behavior\n' >>"$fixture/qvcore/demo/readback"
if output=$(
  QVOS_OWNER_CONTRACT_ROOT="$fixture" \
    "$root/qvcore/tui/owner-contracts" --check 2>&1
); then
  fail "changed nested owner source was accepted without review"
fi
grep -Fq \
  'catalog owners or their sources changed; review them, then run qvcore/tui/owner-contracts --write' \
  <<<"$output" ||
  fail "changed owner review instruction"

QVOS_OWNER_CONTRACT_ROOT="$fixture" \
  "$root/qvcore/tui/owner-contracts" --write >/dev/null
QVOS_OWNER_CONTRACT_ROOT="$fixture" \
  "$root/qvcore/tui/owner-contracts" --check >/dev/null ||
  fail "reviewed owner manifest refresh"

printf '%s\n' '# qvos:contract=outside/demo' \
  >>"$fixture/qvcore/demo/readback"
if output=$(
  QVOS_OWNER_CONTRACT_ROOT="$fixture" \
    "$root/qvcore/tui/owner-contracts" --write 2>&1
); then
  fail "invalid static dependency declaration was accepted"
fi
grep -Fq \
  'qvcore/demo/readback has an invalid qvos:contract declaration' \
  <<<"$output" ||
  fail "invalid static dependency declaration diagnostic"
sed -i '$d' "$fixture/qvcore/demo/readback"

printf '%s\n' \
  'unknown|Unknown|Unresolved owner|1|mutation|tui|false|Run|Running|Ran|omarchy-missing-owner' \
  >>"$fixture/qvcore/tui/task/actions.psv"
if output=$(
  QVOS_OWNER_CONTRACT_ROOT="$fixture" \
    "$root/qvcore/tui/owner-contracts" --write 2>&1
); then
  fail "unresolved repository owner was classified silently"
fi
grep -Fq 'unresolved repository owner: omarchy-missing-owner' <<<"$output" ||
  fail "unresolved owner diagnostic"

printf 'ok - every TUI catalog route has a deliberate, drift-checked owner contract\n'
