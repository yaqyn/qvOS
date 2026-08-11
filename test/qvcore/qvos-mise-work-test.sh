#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
owner="$root/qvcore/install/config/mise-work.sh"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
event_log="$test_root/events"
package_dir="$test_root/packages"
fixture_root="$test_root/fixture"
archive_root=node-v24.1.2-linux-x64

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$package_dir" \
  "$fixture_root/$archive_root/bin" \
  "$fixture_root/$archive_root/lib/node_modules/npm/bin"
install -m 0755 /dev/stdin \
  "$fixture_root/$archive_root/bin/node" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
for command in npm npx; do
  install -m 0755 /dev/stdin \
    "$fixture_root/$archive_root/lib/node_modules/npm/bin/$command-cli.js" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
  ln -s "../lib/node_modules/npm/bin/$command-cli.js" \
    "$fixture_root/$archive_root/bin/$command"
done
tar -czf "$package_dir/$archive_root.tar.gz" -C "$fixture_root" "$archive_root"

install -m 0755 /dev/stdin "$test_bin/mise" <<'SCRIPT'
#!/bin/bash
printf '%s' "$1" >>"$QVOS_TEST_EVENT_LOG"
shift
printf '\t%s' "$@" >>"$QVOS_TEST_EVENT_LOG"
printf '\n' >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

run_owner() {
  local home=$1
  shift

  HOME="$home" \
    PATH="$test_bin:/usr/bin" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_DATA_HOME="$home/.local/share" \
    XDG_STATE_HOME="$home/.local/state" \
    QVOS_NODE_PACKAGE_DIR="$package_dir" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    bash -euo pipefail -c 'source "$1"' _ "$owner" "$@"
}

offline_home="$test_root/offline-home"
install -d "$offline_home"
: >"$event_log"
OMARCHY_CHROOT_INSTALL=1 run_owner "$offline_home"
runtime="$offline_home/.local/share/mise/installs/node/24.1.2"
[[ -x $runtime/bin/node && -L $runtime/bin/npm && -L $runtime/bin/npx ]] ||
  fail "offline Node.js LTS runtime"
[[ $(<"$offline_home/Work/.mise.toml") == \
  $'[env]\n_.path = "{{ cwd }}/bin"' ]] || fail "native Mise work config"
grep -Fqx $'trust\t'"$offline_home/Work/.mise.toml" "$event_log" ||
  fail "native Mise work config trust"
grep -Fqx $'use\t-g\tnode@24.1.2' "$event_log" ||
  fail "offline Node.js selection"
runtime_inode=$(stat -c '%i' "$runtime")
OMARCHY_CHROOT_INSTALL=1 run_owner "$offline_home"
[[ $(stat -c '%i' "$runtime") == "$runtime_inode" ]] ||
  fail "idempotent offline Node.js extraction"

custom_home="$test_root/custom-home"
install -d "$custom_home/Work"
printf '[tools]\npython = "latest"\n' >"$custom_home/Work/.mise.toml"
: >"$event_log"
run_owner "$custom_home" 2>"$test_root/custom-warning"
[[ $(<"$custom_home/Work/.mise.toml") == \
  $'[tools]\npython = "latest"' ]] || fail "custom Mise config preservation"
! rg -q '^trust' "$event_log" || fail "custom Mise config was trusted"
grep -Fqx $'use\t-g\tnode@lts' "$event_log" ||
  fail "online installation does not select Node.js LTS"
grep -Fq 'preserved the existing Mise work configuration' \
  "$test_root/custom-warning" || fail "custom Mise preservation notice"

weak_home="$test_root/weak-home"
install -d "$weak_home/Work"
printf '%s\n' $'[env]\n_.path = "{{ cwd }}/bin"' >"$weak_home/Work/.mise.toml"
chmod 0666 "$weak_home/Work/.mise.toml"
: >"$event_log"
run_owner "$weak_home" 2>"$test_root/weak-warning"
! rg -q '^trust' "$event_log" || fail "weak Mise config was trusted"
[[ $(stat -c '%a' "$weak_home/Work/.mise.toml") == "666" ]] ||
  fail "weak Mise config mode was changed"

multiple_home="$test_root/multiple-home"
install -d "$multiple_home"
cp "$package_dir/$archive_root.tar.gz" \
  "$package_dir/node-v22.1.0-linux-x64.tar.gz"
if OMARCHY_CHROOT_INSTALL=1 run_owner "$multiple_home" \
  >"$test_root/multiple-output" 2>&1; then
  fail "multiple offline Node.js archives were accepted"
fi
rm -f -- "$package_dir/node-v22.1.0-linux-x64.tar.gz"

unsafe_package_dir="$test_root/unsafe-packages"
unsafe_fixture="$test_root/unsafe-fixture"
unsafe_home="$test_root/unsafe-home"
install -d "$unsafe_package_dir" "$unsafe_fixture/unexpected-root/bin" "$unsafe_home"
install -m 0755 /dev/null "$unsafe_fixture/unexpected-root/bin/node"
tar -czf "$unsafe_package_dir/node-v24.1.2-linux-x64.tar.gz" \
  -C "$unsafe_fixture" unexpected-root
if HOME="$unsafe_home" PATH="$test_bin:/usr/bin" \
  QVOS_NODE_PACKAGE_DIR="$unsafe_package_dir" \
  QVOS_TEST_EVENT_LOG="$event_log" OMARCHY_CHROOT_INSTALL=1 \
  bash -euo pipefail -c 'source "$1"' _ "$owner" \
  >"$test_root/unsafe-output" 2>&1; then
  fail "unsafe offline Node.js archive layout was accepted"
fi
[[ ! -e $unsafe_home/.local/share/mise/installs/node/24.1.2 ]] ||
  fail "unsafe archive created a Node.js runtime"

linked_home="$test_root/linked-home"
external_runtime="$test_root/external-runtime"
install -d \
  "$linked_home/.local/share/mise/installs/node" \
  "$external_runtime"
printf 'preserve\n' >"$external_runtime/sentinel"
ln -s "$external_runtime" \
  "$linked_home/.local/share/mise/installs/node/24.1.2"
if OMARCHY_CHROOT_INSTALL=1 run_owner "$linked_home" \
  >"$test_root/linked-output" 2>&1; then
  fail "linked Node.js runtime was accepted"
fi
[[ $(<"$external_runtime/sentinel") == "preserve" ]] ||
  fail "linked Node.js runtime target was modified"

printf 'ok - qvOS installs one bounded Node.js LTS through one native path\n'
