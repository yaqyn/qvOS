#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
installed="$test_root/warp-installed"
log="$test_root/actions.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
for name in omarchy-qvos-setup-dns omarchy-cmd-present omarchy-pkg-present \
  omarchy-pkg-missing omarchy-pkg-drop systemctl warp-cli pacman gum; do
  install -m 0755 /dev/stdin "$test_bin/$name" <<'SCRIPT'
#!/bin/bash
case ${0##*/} in
omarchy-qvos-setup-dns)
  printf 'dns\t%s\n' "$1" >>"$QVOS_TEST_LOG"
  [[ $1 != "WARP" ]] || install -m 0644 /dev/null "$QVOS_TEST_INSTALLED"
  ;;
omarchy-cmd-present) [[ -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-pkg-present) [[ -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-pkg-missing) [[ ! -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-pkg-drop) rm -f "$QVOS_TEST_INSTALLED"; echo drop >>"$QVOS_TEST_LOG" ;;
systemctl | pacman | gum) exit 0 ;;
warp-cli)
  if [[ $* == *status* ]]; then
    printf '{"status":"Connected"}\n'
  else
    printf '{"registration":"ready"}\n'
  fi
  ;;
esac
SCRIPT
done

run_warp() {
  HOME="$test_root/home" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_LOG="$log" \
    "$root/qv/core/warp.sh" "$@"
}

run_warp install >/dev/null
[[ -f $test_root/home/.local/state/qvos/qvcore/warp ]] ||
  fail "WARP enrollment"
grep -Fqx $'dns\tWARP' "$log" || fail "WARP network configuration"

run_warp remove --yes >/dev/null
[[ ! -f $installed ]] || fail "WARP package removal"
[[ ! -e $test_root/home/.local/state/qvos/qvcore/warp ]] ||
  fail "WARP enrollment removal"
grep -Fqx $'dns\tDHCP' "$log" || fail "WARP network cleanup"
grep -Fqx 'drop' "$log" || fail "WARP software cleanup"

printf 'ok - WARP Install verifies networking and Remove restores DHCP\n'
