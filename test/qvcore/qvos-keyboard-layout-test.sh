#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
vconsole="$test_root/vconsole.conf"
input="$test_home/.config/hypr/input.lua"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

reset_input() {
  install -D -m 0640 "$root/qvcore/config/files/hypr/input.lua" "$input"
}

run_import() {
  HOME="$test_home" \
  QVOS_CONFIG_TESTING=1 \
  QVOS_CONFIG_VCONSOLE="$vconsole" \
    "$root/qvcore/config/keyboard-layout" "$@"
}

install -d -m 0700 "$test_home"
reset_input
install -m 0644 /dev/stdin "$vconsole" <<'VCONSOLE'
XKBLAYOUT="de"
XKBVARIANT="nodeadkeys"
VCONSOLE
run_import
grep -Fqx '    kb_layout = "de",' "$input" ||
  fail "console layout was not published"
grep -Fqx '    kb_variant = "nodeadkeys",' "$input" ||
  fail "console variant was not published"
[[ $(stat -c '%a' "$input") == "640" ]] ||
  fail "input config mode changed"
pass "bounded console layout and variant publish atomically"

before_identity=$(stat -c '%i:%Y:%Z' "$input")
before_hash=$(sha256sum "$input")
run_import
[[ $(stat -c '%i:%Y:%Z' "$input") == "$before_identity" &&
  $(sha256sum "$input") == "$before_hash" ]] ||
  fail "idempotent import replaced the input config"
pass "current keyboard state is a no-op"

install -m 0644 /dev/stdin "$vconsole" <<'VCONSOLE'
XKBLAYOUT=us
VCONSOLE
run_import
grep -Fqx '    kb_layout = "us",' "$input" ||
  fail "unquoted console layout was not accepted"
! rg -q '^[[:space:]]*kb_variant[[:space:]]*=' "$input" ||
  fail "absent console variant left a stale Hyprland variant"
pass "absent console variant removes stale state"

install -m 0644 /dev/stdin "$vconsole" <<'VCONSOLE'
XKBLAYOUT="us,ara"
XKBVARIANT=",digits"
VCONSOLE
for _ in {1..8}; do
  run_import &
done
wait
[[ $(grep -Fc '    kb_layout = "us,ara",' "$input") == 1 &&
  $(grep -Fc '    kb_variant = ",digits",' "$input") == 1 ]] ||
  fail "concurrent imports produced an incomplete input config"
if find "$test_home/.config/hypr" -name '.qvos-input-*' -print -quit |
  grep -q .; then
  fail "keyboard import left staging files"
fi
pass "concurrent imports serialize to one complete result"

assert_rejected_unchanged() {
  local description=$1

  cp -a -- "$input" "$test_root/before.lua"
  if run_import >/dev/null 2>&1; then
    fail "$description was accepted"
  fi
  cmp -s -- "$test_root/before.lua" "$input" ||
    fail "$description changed the input config"
}

install -m 0644 /dev/stdin "$vconsole" <<'VCONSOLE'
XKBLAYOUT=us
XKBLAYOUT=ara
VCONSOLE
assert_rejected_unchanged "duplicate console layout"

printf 'XKBLAYOUT=us; touch %s\n' "$test_root/layout-injection" >"$vconsole"
assert_rejected_unchanged "unsafe console layout"
[[ ! -e $test_root/layout-injection ]] ||
  fail "unsafe console layout executed content"

install -m 0644 /dev/stdin "$vconsole" <<'VCONSOLE'
XKBVARIANT=intl
VCONSOLE
assert_rejected_unchanged "variant without a layout"
pass "malformed and inconsistent console input fails closed"

install -m 0644 /dev/stdin "$vconsole" <<'VCONSOLE'
XKBLAYOUT=fr
VCONSOLE
printf '%s\n' '    kb_layout = "extra",' >>"$input"
assert_rejected_unchanged "duplicate Hyprland layout"
reset_input
sed -i '/kb_options/i\    kb_variant = load("unsafe"),' "$input"
assert_rejected_unchanged "malformed Hyprland variant"
reset_input

outside="$test_root/outside.lua"
cp -a -- "$input" "$outside"
rm -- "$input"
ln -s -- "$outside" "$input"
if run_import >/dev/null 2>&1; then
  fail "linked input config was accepted"
fi
cmp -s -- "$root/qvcore/config/files/hypr/input.lua" "$outside" ||
  fail "linked input target was changed"
rm -- "$input"
reset_input

real_vconsole="$test_root/real-vconsole.conf"
cp -a -- "$vconsole" "$real_vconsole"
rm -- "$vconsole"
ln -s -- "$real_vconsole" "$vconsole"
if run_import >/dev/null 2>&1; then
  fail "linked console config was accepted"
fi
pass "linked source and target files are preserved"

if HOME="$test_home" QVOS_CONFIG_VCONSOLE="$real_vconsole" \
  "$root/qvcore/config/keyboard-layout" >/dev/null 2>&1; then
  fail "ungated test source override was accepted"
fi
if run_import unexpected >/dev/null 2>&1; then
  fail "keyboard-layout owner accepted arguments"
fi
pass "test override and command input are bounded"
