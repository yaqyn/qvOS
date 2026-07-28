#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
installed_dir="$test_root/installed"
log="$test_root/actions.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$installed_dir" "$test_root/home/.config/gimp"
printf 'personal\n' >"$test_root/home/.config/gimp/settings"
for name in omarchy-pkg-present omarchy-pkg-missing omarchy-pkg-add \
  omarchy-pkg-drop pacman gum; do
  install -m 0755 /dev/stdin "$test_bin/$name" <<'SCRIPT'
#!/bin/bash
case ${0##*/} in
omarchy-pkg-present) [[ -f $QVOS_TEST_INSTALLED_DIR/$1 ]] ;;
omarchy-pkg-missing) [[ ! -f $QVOS_TEST_INSTALLED_DIR/$1 ]] ;;
omarchy-pkg-add)
  for package in "$@"; do
    install -m 0644 /dev/null "$QVOS_TEST_INSTALLED_DIR/$package"
    printf 'add\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
omarchy-pkg-drop)
  for package in "$@"; do
    rm -f "$QVOS_TEST_INSTALLED_DIR/$package"
    printf 'drop\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
pacman | gum) exit 0 ;;
esac
SCRIPT
done

run_media() {
  HOME="$test_root/home" \
    PATH="$test_bin:$PATH" \
    QVOS_TEST_INSTALLED_DIR="$installed_dir" \
    QVOS_TEST_LOG="$log" \
    "$root/qv/core/media.sh" "$@"
}

install -m 0644 /dev/null "$installed_dir/gimp"
run_media install >/dev/null
[[ $(find "$installed_dir" -type f | wc -l) == "7" ]] ||
  fail "complete Media installation"
[[ $(grep -c '^add' "$log") == "6" ]] ||
  fail "Media installs only missing applications"
[[ -f $test_root/home/.local/state/qvos/qvcore/media ]] ||
  fail "Media enrollment"

run_media remove --yes >/dev/null
[[ -z $(find "$installed_dir" -type f -print -quit) ]] ||
  fail "complete Media removal"
[[ $(<"$test_root/home/.config/gimp/settings") == "personal" ]] ||
  fail "Media settings preservation"

printf 'ok - Media converges seven applications and removes only stack software\n'
