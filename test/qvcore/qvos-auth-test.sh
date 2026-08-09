#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
policy="$root/qvcore/security/auth-policy"
auth="$root/qvcore/security/auth"
test_root=$(/usr/bin/mktemp -d)
system_root="$test_root/system"
test_bin="$test_root/bin"
uid=$(/usr/bin/id -u)
gid=$(/usr/bin/id -g)
account=$(/usr/bin/id -un)
pam_sudo="$system_root/etc/pam.d/sudo"
pam_polkit="$system_root/etc/pam.d/polkit-1"
package_state="$test_root/packages"
package_log="$test_root/packages.log"

cleanup() {
  [[ ! -d $test_root ]] || /usr/bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_policy() {
  QVOS_AUTH_SYSTEM_ROOT="$system_root" \
    QVOS_SECURITY_TESTING=1 \
    "$policy" "$@"
}

install -d \
  "$system_root/etc/pam.d" \
  "$system_root/run" \
  "$system_root/usr/lib/security" \
  "$system_root/var/lib"
chmod 0755 "$system_root/run" "$system_root/etc/pam.d"
install -m 0644 /dev/stdin "$pam_sudo" <<'PAM'
auth include system-auth
account include system-auth
session include system-auth
PAM
install -m 0644 /dev/stdin "$pam_polkit" <<'PAM'
auth include system-auth
account include system-auth
session include system-auth
PAM
install -m 0644 /dev/null "$system_root/usr/lib/security/pam_fprintd.so"
install -m 0644 /dev/null "$system_root/usr/lib/security/pam_u2f.so"
pam_sudo_original=$(<"$pam_sudo")
pam_polkit_original=$(<"$pam_polkit")

[[ $(run_policy status fingerprint) == "disabled" ]] ||
  fail "fingerprint starts disabled"
run_policy enable fingerprint
for pam_file in "$pam_sudo" "$pam_polkit"; do
  grep -Fqx '# qvOS authentication: fingerprint' "$pam_file" ||
    fail "fingerprint PAM block start"
  grep -Fqx 'auth      sufficient pam_fprintd.so' "$pam_file" ||
    fail "fingerprint PAM policy"
done
fingerprint_state="$system_root/var/lib/qvos/security/auth/fingerprint.enabled"
[[ -f $fingerprint_state && ! -L $fingerprint_state &&
  $(stat -c '%u:%g:%a' "$fingerprint_state") == "$uid:$gid:600" &&
  $(<"$fingerprint_state") == "fingerprint enabled" ]] ||
  fail "private fingerprint intent"
fingerprint_before=$(stat -c '%n|%i|%y' "$pam_sudo" "$pam_polkit" "$fingerprint_state")
run_policy reconcile fingerprint
[[ $(stat -c '%n|%i|%y' "$pam_sudo" "$pam_polkit" "$fingerprint_state") == \
  "$fingerprint_before" ]] || fail "fingerprint reconciliation is idempotent"
run_policy disable fingerprint
[[ $(<"$pam_sudo") == "$pam_sudo_original" &&
  $(<"$pam_polkit") == "$pam_polkit_original" &&
  ! -e $fingerprint_state && ! -L $fingerprint_state ]] ||
  fail "fingerprint disable restores unowned PAM content"

if QVOS_AUTH_SYSTEM_ROOT="$system_root" \
  QVOS_SECURITY_TESTING=1 \
  QVOS_AUTH_TEST_FAIL_AFTER=1 \
  "$policy" enable fingerprint >/dev/null 2>&1; then
  fail "injected PAM transaction failure succeeded"
fi
[[ $(<"$pam_sudo") == "$pam_sudo_original" &&
  $(<"$pam_polkit") == "$pam_polkit_original" &&
  ! -e $fingerprint_state ]] ||
  fail "failed PAM transaction did not roll back"

printf '%s\n' \
  '# qvOS authentication: fingerprint' \
  'auth      required pam_fprintd.so' \
  '# qvOS authentication end: fingerprint' \
  "$pam_sudo_original" >"$pam_sudo"
if run_policy disable fingerprint >/dev/null 2>&1; then
  fail "modified managed PAM block was accepted"
fi
grep -Fqx 'auth      required pam_fprintd.so' "$pam_sudo" ||
  fail "modified managed PAM block was overwritten"
printf '%s\n' "$pam_sudo_original" >"$pam_sudo"

if printf '%s:fixture-key\nextra-data\n' "$account" |
  run_policy enable fido2 "$uid" >/dev/null 2>&1; then
  fail "multi-line FIDO2 registration was accepted"
fi
[[ $(<"$pam_sudo") == "$pam_sudo_original" ]] ||
  fail "invalid FIDO2 registration changed PAM"
oversized_registration=$(printf '%*s' 16385 '' | tr ' ' a)
if printf '%s:%s\n' "$account" "$oversized_registration" |
  run_policy enable fido2 "$uid" >/dev/null 2>&1; then
  fail "oversized FIDO2 registration was accepted"
fi
[[ $(<"$pam_sudo") == "$pam_sudo_original" ]] ||
  fail "oversized FIDO2 registration changed PAM"
printf '%s:fixture-key-handle,fixture-public-key\n' "$account" |
  run_policy enable fido2 "$uid"
fido_state="$system_root/var/lib/qvos/security/auth/fido2.enabled"
fido_credential="$system_root/etc/qvos/security/fido2"
[[ -f $fido_credential && ! -L $fido_credential &&
  $(stat -c '%u:%g:%a' "$fido_credential") == "$uid:$gid:600" ]] ||
  fail "private root-owned FIDO2 credential"
grep -Fqx \
  'auth      sufficient pam_u2f.so cue authfile=/etc/qvos/security/fido2' \
  "$pam_sudo" || fail "FIDO2 PAM policy"
chmod 0640 "$fido_credential"
if run_policy disable fido2 >/dev/null 2>&1; then
  fail "unsafe FIDO2 credential was accepted"
fi
[[ -f $fido_state ]] || fail "unsafe FIDO2 disable changed enabled intent"
grep -Fqx '# qvOS authentication: fido2' "$pam_sudo" ||
  fail "unsafe FIDO2 disable changed PAM policy"
chmod 0600 "$fido_credential"
fido_credential_content=$(<"$fido_credential")
printf 'modified-root-credential\n' >"$fido_credential"
if run_policy disable fido2 >/dev/null 2>&1; then
  fail "modified FIDO2 credential was accepted"
fi
[[ -f $fido_state ]] || fail "modified FIDO2 credential changed enabled intent"
grep -Fqx '# qvOS authentication: fido2' "$pam_sudo" ||
  fail "modified FIDO2 credential changed PAM policy"
printf '%s\n' "$fido_credential_content" >"$fido_credential"
run_policy disable fido2
[[ ! -e $fido_state && ! -e $fido_credential &&
  $(<"$pam_sudo") == "$pam_sudo_original" &&
  $(<"$pam_polkit") == "$pam_polkit_original" ]] ||
  fail "FIDO2 disable restores unowned PAM content and removes only owned state"

printf 'administrator-owned-credential\n' >"$fido_credential"
chmod 0600 "$fido_credential"
if run_policy reconcile fido2 >/dev/null 2>&1; then
  fail "untracked FIDO2 credential was adopted"
fi
grep -Fqx 'administrator-owned-credential' "$fido_credential" ||
  fail "untracked FIDO2 credential was changed"
rm -f -- "$fido_credential"

mv "$pam_sudo" "$test_root/real-sudo"
ln -s "$test_root/real-sudo" "$pam_sudo"
if run_policy reconcile fingerprint >/dev/null 2>&1; then
  fail "linked PAM file was accepted"
fi
unlink "$pam_sudo"
mv "$test_root/real-sudo" "$pam_sudo"

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/auth-policy" <<'SCRIPT'
#!/bin/bash
exec env \
  QVOS_AUTH_SYSTEM_ROOT="$QVOS_TEST_AUTH_SYSTEM_ROOT" \
  QVOS_SECURITY_TESTING=1 \
  "$QVOS_TEST_AUTH_POLICY" "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
exec "$@"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Q)
  [[ ${2:-} == "--" && $# == 3 ]] || exit 64
  grep -Fqx -- "$3" "$QVOS_TEST_PACKAGE_STATE"
  ;;
-S)
  shift
  while [[ ${1:-} != "--" ]]; do shift; done
  shift
  for package in "$@"; do
    grep -Fqx -- "$package" "$QVOS_TEST_PACKAGE_STATE" 2>/dev/null ||
      printf '%s\n' "$package" >>"$QVOS_TEST_PACKAGE_STATE"
    printf 'add:%s\n' "$package" >>"$QVOS_TEST_PACKAGE_LOG"
  done
  ;;
-Rns)
  shift
  while [[ ${1:-} != "--" ]]; do shift; done
  shift
  for package in "$@"; do
    grep -Fxv -- "$package" "$QVOS_TEST_PACKAGE_STATE" >"$QVOS_TEST_PACKAGE_STATE.next" || true
    mv "$QVOS_TEST_PACKAGE_STATE.next" "$QVOS_TEST_PACKAGE_STATE"
    printf 'drop:%s\n' "$package" >>"$QVOS_TEST_PACKAGE_LOG"
  done
  ;;
*) exit 64 ;;
esac
SCRIPT
for command_name in fprintd-enroll fprintd-verify; do
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
done
install -m 0755 /dev/stdin "$test_bin/fido2-token" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "-L" ]] || exit 64
[[ ${QVOS_TEST_FIDO_AVAILABLE:-1} == "1" ]] || exit 0
echo /dev/hidraw-fixture
SCRIPT
install -m 0755 /dev/stdin "$test_bin/pamu2fcfg" <<'SCRIPT'
#!/bin/bash
printf '%s:fixture-key-handle,fixture-public-key\n' "$(id -un)"
SCRIPT

home="$test_root/home"
state_home="$home/state"
config_home="$home/config"
install -d "$config_home/hypr" "$state_home"
install -m 0644 /dev/stdin "$config_home/hypr/hyprlock.conf" <<'HYPRLOCK'
input-field {
  fingerprint:enabled = false
  placeholder_text = <span>Custom prompt</span>
}
HYPRLOCK
: >"$package_state"
: >"$package_log"
export \
  HOME="$home" \
  XDG_CONFIG_HOME="$config_home" \
  XDG_STATE_HOME="$state_home" \
  QVOS_PATH="$root" \
  QVOS_SECURITY_TESTING=1 \
  QVOS_AUTH_ROOT_HELPER="$test_bin/auth-policy" \
  QVOS_TEST_AUTH_SYSTEM_ROOT="$system_root" \
  QVOS_TEST_AUTH_POLICY="$policy" \
  QVOS_TEST_PACKAGE_STATE="$package_state" \
  QVOS_TEST_PACKAGE_LOG="$package_log" \
  PATH="$test_bin:/usr/bin"

"$auth" setup fingerprint >/dev/null
grep -Fqx '  fingerprint:enabled = true' "$config_home/hypr/hyprlock.conf" ||
  fail "fingerprint setup enables only its Hyprlock setting"
grep -Fqx '  placeholder_text = <span>Custom prompt</span>' \
  "$config_home/hypr/hyprlock.conf" ||
  fail "fingerprint setup preserves the custom prompt"
[[ -f $state_home/qvos/security/auth/fingerprint.package ]] ||
  fail "fingerprint package ownership marker"
cp "$config_home/hypr/hyprlock.conf" "$test_root/hyprlock-valid"
sed -i '/fingerprint:enabled/d' "$config_home/hypr/hyprlock.conf"
if "$auth" remove fingerprint >/dev/null 2>&1; then
  fail "malformed Hyprlock configuration was accepted during disable"
fi
[[ $(run_policy status fingerprint) == "enabled" ]] ||
  fail "invalid Hyprlock configuration changed fingerprint intent"
grep -Fq '# qvOS authentication: fingerprint' "$pam_sudo" ||
  fail "invalid Hyprlock configuration changed fingerprint PAM policy"
mv "$test_root/hyprlock-valid" "$config_home/hypr/hyprlock.conf"
"$auth" remove fingerprint >/dev/null
grep -Fqx '  fingerprint:enabled = false' "$config_home/hypr/hyprlock.conf" ||
  fail "fingerprint removal disables its Hyprlock setting"
grep -Fqx 'drop:fprintd' "$package_log" ||
  fail "fingerprint removal drops only its qvOS-added package"

printf 'fprintd\n' >"$package_state"
"$auth" setup fingerprint >/dev/null
[[ ! -e $state_home/qvos/security/auth/fingerprint.package ]] ||
  fail "pre-existing fingerprint package was adopted"
"$auth" remove fingerprint >/dev/null
grep -Fqx 'fprintd' "$package_state" ||
  fail "pre-existing fingerprint package was removed"
: >"$package_state"

"$auth" setup fido2 >/dev/null
[[ -f $state_home/qvos/security/auth/fido2.package ]] ||
  fail "FIDO2 package ownership marker"
"$auth" remove fido2 >/dev/null
grep -Fqx 'drop:pam-u2f' "$package_log" ||
  fail "FIDO2 removal drops only its qvOS-added package"

QVOS_TEST_FIDO_AVAILABLE=0
export QVOS_TEST_FIDO_AVAILABLE
if "$auth" setup fido2 >/dev/null 2>&1; then
  fail "missing FIDO2 hardware was accepted"
fi
[[ -z $(grep -Fx 'pam-u2f' "$package_state" || true) ]] ||
  fail "failed FIDO2 setup left its newly added package"

QVOS_TEST_FIDO_AVAILABLE=1
export QVOS_TEST_FIDO_AVAILABLE
unsafe_marker="$state_home/qvos/security/auth/fido2.package"
ln -s "$test_root/foreign-package-state" "$unsafe_marker"
if "$auth" setup fido2 >/dev/null 2>&1; then
  fail "unsafe package marker was accepted"
fi
[[ -z $(grep -Fx 'pam-u2f' "$package_state" || true) ]] ||
  fail "unsafe package state triggered a package installation"
[[ $(run_policy status fido2) == "disabled" ]] ||
  fail "unsafe package state changed authentication intent"
! grep -Fq '# qvOS authentication: fido2' "$pam_sudo" ||
  fail "unsafe package state changed PAM"
unlink "$unsafe_marker"

printf 'ok - optional authentication is native, transactional, private, and ownership-safe\n'
