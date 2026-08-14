#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
system_root="$test_root/system"
test_bin="$test_root/bin"
test_user=$(id -un)
verify="$root/qvcore/install/post-install/verify"

cleanup() {
  [[ ! -d $test_root ]] || rm -r -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_verify() {
  HOME="$test_root/home" \
    USER="$test_user" \
    QVOS_PATH="$root" \
    QVOS_PROVIDER_CHANNEL=stable \
    QVOS_INSTALL_VERIFY_ROOT="$system_root" \
    QVOS_INSTALL_VERIFY_TESTING=1 \
    QVOS_INSTALL_VERIFY_TARGET="${QVOS_INSTALL_VERIFY_TARGET:-}" \
    QVOS_TEST_PACMAN_OUTPUT="${QVOS_TEST_PACMAN_OUTPUT:-}" \
    QVOS_TEST_PACMAN_STATUS="${QVOS_TEST_PACMAN_STATUS:-0}" \
    QVOS_TEST_SYSTEM_ROOT="$system_root" \
    PATH="$test_bin:/usr/bin" \
    bash "$verify"
}

install -d -m 0700 \
  "$test_bin" \
  "$system_root/etc/pacman.d" \
  "$system_root/etc/sddm.conf.d" \
  "$system_root/usr/lib" \
  "$system_root/usr/local/bin" \
  "$system_root/usr/local/share/wayland-sessions" \
  "$system_root/var/lib/pacman/local/example-1-1"
install -m 0644 \
  "$root/qvcore/packages/provider/omarchy/pacman-stable.conf" \
  "$system_root/etc/pacman.conf"
install -m 0644 \
  "$root/qvcore/packages/provider/omarchy/mirrorlist-stable" \
  "$system_root/etc/pacman.d/mirrorlist"
install -m 0755 \
  "$root/qvcore/boot/session-start" \
  "$system_root/usr/local/bin/qvos-session"
install -m 0644 \
  "$root/qvcore/boot/wayland-sessions/qvos.desktop" \
  "$system_root/usr/local/share/wayland-sessions/qvos.desktop"
printf '[Theme]\nCurrent=qvos\n' \
  >"$system_root/etc/sddm.conf.d/qvos.conf"
printf '[General]\nDisplayServer=wayland\n' \
  >"$system_root/etc/sddm.conf.d/10-wayland.conf"
printf '[Autologin]\nUser=%s\nSession=qvos\n' "$test_user" \
  >"$system_root/etc/sddm.conf.d/autologin.conf"
printf 'example package\n' \
  >"$system_root/var/lib/pacman/local/example-1-1/desc"
printf '9\n' \
  >"$system_root/var/lib/pacman/local/ALPM_DB_VERSION"
: >"$system_root/var/lib/pacman/local/example-1-1/files"
printf 'example mtree\n' \
  >"$system_root/var/lib/pacman/local/example-1-1/mtree"

: >"$system_root/var/lib/pacman/local/ALPM_DB_VERSION"
if run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a truncated database version"
fi
printf '9\n' \
  >"$system_root/var/lib/pacman/local/ALPM_DB_VERSION"

rm -- "$system_root/var/lib/pacman/local/ALPM_DB_VERSION"
if run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a missing database version"
fi
printf '9\n' \
  >"$system_root/var/lib/pacman/local/ALPM_DB_VERSION"

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

[[ ${1:-} == "--root" && ${2:-} == "$QVOS_TEST_SYSTEM_ROOT" &&
  ${3:-} == "-Qkkq" && $# == 3 ]] || exit 64
[[ -z ${QVOS_TEST_PACMAN_OUTPUT:-} ]] ||
  printf '%s\n' "$QVOS_TEST_PACMAN_OUTPUT"
exit "${QVOS_TEST_PACMAN_STATUS:-0}"
SCRIPT

run_verify

if QVOS_INSTALL_VERIFY_TARGET=1 run_verify >/dev/null 2>&1; then
  fail "fixture mode entered the privileged release-target boundary"
fi

printf 'intact\n' >"$system_root/usr/lib/qvos-test"
QVOS_TEST_PACMAN_OUTPUT='example /usr/lib/qvos-test' \
QVOS_TEST_PACMAN_STATUS=1 \
  run_verify

QVOS_TEST_PACMAN_OUTPUT=$'cups /etc/cups/classes.conf\ncups /etc/cups/printers.conf' \
QVOS_TEST_PACMAN_STATUS=1 \
  run_verify

: >"$system_root/usr/lib/qvos-truncated"
if QVOS_TEST_PACMAN_OUTPUT='example /usr/lib/qvos-truncated' \
  QVOS_TEST_PACMAN_STATUS=1 \
  run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a truncated package file"
fi

if QVOS_TEST_PACMAN_OUTPUT='example /usr/lib/qvos-missing' \
  QVOS_TEST_PACMAN_STATUS=1 \
  run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a missing package file"
fi

QVOS_TEST_PACMAN_OUTPUT=$'mkinitcpio /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook\nmkinitcpio /usr/share/libalpm/hooks/90-mkinitcpio-install.hook' \
QVOS_TEST_PACMAN_STATUS=1 \
  run_verify

if QVOS_TEST_PACMAN_OUTPUT='error: unreadable package metadata' \
  QVOS_TEST_PACMAN_STATUS=1 \
  run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted an unreadable package database"
fi

if QVOS_TEST_PACMAN_OUTPUT='sudo: a password is required' \
  QVOS_TEST_PACMAN_STATUS=1 \
  run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a failed privileged inspection"
fi

if QVOS_TEST_PACMAN_STATUS=1 run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted unexplained package drift"
fi

if QVOS_TEST_PACMAN_STATUS=2 run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a failed package inspection"
fi

: >"$system_root/var/lib/pacman/local/example-1-1/mtree"
if run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a truncated local package record"
fi
printf 'example mtree\n' \
  >"$system_root/var/lib/pacman/local/example-1-1/mtree"

lock_target="$test_root/foreign-lock"
: >"$lock_target"
ln -s "$lock_target" "$system_root/var/lib/pacman/db.lck"
if run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a linked Pacman lock"
fi
[[ -f $lock_target ]] || fail "installed-state verifier changed a foreign lock"
unlink -- "$system_root/var/lib/pacman/db.lck"

printf '\n# drift\n' >>"$system_root/etc/pacman.conf"
if run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted package-provider drift"
fi
install -m 0644 \
  "$root/qvcore/packages/provider/omarchy/pacman-stable.conf" \
  "$system_root/etc/pacman.conf"

: >"$system_root/etc/sddm.conf.d/autologin.conf"
if run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted an empty SDDM handoff"
fi
printf '[Autologin]\nUser=%s\nSession=qvos\n' "$test_user" \
  >"$system_root/etc/sddm.conf.d/autologin.conf"

printf 'drift\n' >"$system_root/usr/local/bin/qvos-session"
if run_verify >/dev/null 2>&1; then
  fail "installed-state verifier accepted a modified session launcher"
fi

printf 'ok - final installed state rejects incomplete and truncated handoffs\n'
