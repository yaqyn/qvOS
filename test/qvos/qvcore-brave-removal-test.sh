#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
installed="$test_root/installed"
profile="$test_root/home/.config/BraveSoftware/profile"
log="$test_root/actions.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$(dirname -- "$profile")"
printf 'personal\n' >"$profile"
for name in omarchy-pkg-present omarchy-pkg-missing omarchy-cmd-present \
  omarchy-install-browser omarchy-default-browser omarchy-remove-browser \
  pacman gum; do
  install -m 0755 /dev/stdin "$test_bin/$name" <<'SCRIPT'
#!/bin/bash
case ${0##*/} in
omarchy-pkg-present) [[ -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-pkg-missing) [[ ! -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-cmd-present) [[ -f $QVOS_TEST_INSTALLED ]] ;;
omarchy-install-browser) install -m 0644 /dev/null "$QVOS_TEST_INSTALLED"; echo install >>"$QVOS_TEST_LOG" ;;
omarchy-default-browser) echo default >>"$QVOS_TEST_LOG" ;;
omarchy-remove-browser) rm -f "$QVOS_TEST_INSTALLED"; echo remove >>"$QVOS_TEST_LOG" ;;
pacman) exit 0 ;;
gum) exit 0 ;;
esac
SCRIPT
done

run_brave() {
  HOME="$test_root/home" \
    PATH="$test_bin:$PATH" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_LOG="$log" \
    "$root/qv/core/brave.sh" "$@"
}

run_brave install >/dev/null
[[ -f $installed ]] || fail "Brave package installation"
[[ -f $test_root/home/.local/state/qvos/qvcore/brave ]] ||
  fail "Brave enrollment"
run_brave install >/dev/null
[[ $(grep -c '^install$' "$log") == "1" ]] ||
  fail "Brave Install reuses compatible software"

run_brave remove --yes >/dev/null
[[ ! -f $installed ]] || fail "Brave package removal"
[[ ! -e $test_root/home/.local/state/qvos/qvcore/brave ]] ||
  fail "Brave enrollment removal"
[[ $(<"$profile") == "personal" ]] || fail "Brave profile preservation"

run_brave remove --yes >/dev/null
[[ $(grep -c '^remove$' "$log") == "1" ]] ||
  fail "unenrolled Brave removal is inert"

printf 'ok - Brave Install reuses software and Remove preserves its profile\n'
