#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
owner="$root/qvcore/security/login-policy"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
visudo_state="$test_root/visudo-state"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/visudo" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

[[ $# == 2 && $1 == "-cf" && -f $2 ]] || exit 64
grep -Fqx 'Defaults passwd_tries=10' "$2" || exit 1
[[ ${QVOS_LOGIN_TEST_FAIL_ALWAYS:-} != "1" ]] || exit 1
if [[ ${QVOS_LOGIN_TEST_FAIL_SECOND:-} == "1" ]]; then
  count=0
  [[ ! -f $QVOS_LOGIN_TEST_VISUDO_STATE ]] ||
    count=$(<"$QVOS_LOGIN_TEST_VISUDO_STATE")
  ((count += 1))
  printf '%s\n' "$count" >"$QVOS_LOGIN_TEST_VISUDO_STATE"
  ((count < 2)) || exit 1
fi
SCRIPT

new_fixture() {
  local name=$1
  local fixture="$test_root/$name"

  install -d "$fixture/etc/security" "$fixture/etc/sudoers.d"
  install -m 0644 /dev/stdin "$fixture/etc/security/faillock.conf" <<'CONF'
# Package-provided faillock policy.
# deny = 3
# unlock_time = 600
CONF
  printf '%s\n' "$fixture"
}

run_owner() {
  local fixture=$1
  shift

  QVOS_SECURITY_TESTING=1 \
  QVOS_LOGIN_POLICY_SYSTEM_ROOT="$fixture" \
  QVOS_LOGIN_POLICY_VISUDO="$test_bin/visudo" \
  QVOS_LOGIN_TEST_VISUDO_STATE="$visudo_state" \
    "$owner" "$@"
}

fixture=$(new_fixture success)
run_owner "$fixture"
faillock="$fixture/etc/security/faillock.conf"
sudoers="$fixture/etc/sudoers.d/50-qvos-password-attempts"
expected_block=$'# >>> qvOS login policy >>>\n# Allow typing mistakes without creating a long denial-of-service window.\ndeny = 10\nunlock_time = 120\n# <<< qvOS login policy <<<'
installed_block=$(sed -n \
  '/^# >>> qvOS login policy >>>$/,/^# <<< qvOS login policy <<<$/{p}' \
  "$faillock")
[[ $installed_block == "$expected_block" ]] ||
  fail "faillock marked policy"
[[ $(stat -c '%a' -- "$faillock") == "644" ]] ||
  fail "faillock policy mode"
[[ $(<"$sudoers") == "Defaults passwd_tries=10" &&
  $(stat -c '%a' -- "$sudoers") == "440" ]] ||
  fail "validated sudo password-attempt policy"
state_before=$(stat -c '%n|%a|%i|%y' "$faillock" "$sudoers")
run_owner "$fixture"
[[ $(stat -c '%n|%a|%i|%y' "$faillock" "$sudoers") == \
  "$state_before" ]] || fail "idempotent login policy"

foreign_fixture=$(new_fixture foreign)
printf 'deny = 4\n' >>"$foreign_fixture/etc/security/faillock.conf"
foreign_before=$(sha256sum "$foreign_fixture/etc/security/faillock.conf")
if run_owner "$foreign_fixture" >/dev/null 2>&1; then
  fail "administrator-owned faillock threshold accepted"
fi
[[ $(sha256sum "$foreign_fixture/etc/security/faillock.conf") == \
  "$foreign_before" &&
  ! -e $foreign_fixture/etc/sudoers.d/50-qvos-password-attempts ]] ||
  fail "foreign faillock policy preservation"

modified_fixture=$(new_fixture modified)
run_owner "$modified_fixture"
sed -i 's/^unlock_time = 120$/unlock_time = 600/' \
  "$modified_fixture/etc/security/faillock.conf"
modified_before=$(sha256sum \
  "$modified_fixture/etc/security/faillock.conf" \
  "$modified_fixture/etc/sudoers.d/50-qvos-password-attempts")
if run_owner "$modified_fixture" >/dev/null 2>&1; then
  fail "modified qvOS faillock block accepted"
fi
[[ $(sha256sum \
  "$modified_fixture/etc/security/faillock.conf" \
  "$modified_fixture/etc/sudoers.d/50-qvos-password-attempts") == \
  "$modified_before" ]] || fail "modified qvOS policy preservation"

preflight_fixture=$(new_fixture preflight)
preflight_tmp="$test_root/preflight-tmp"
install -d "$preflight_tmp"
if QVOS_LOGIN_TEST_FAIL_ALWAYS=1 TMPDIR="$preflight_tmp" \
  run_owner "$preflight_fixture" >/dev/null 2>&1; then
  fail "failed initial sudoers validation reported success"
fi
[[ -z $(find "$preflight_tmp" -mindepth 1 -print -quit) &&
  ! -e $preflight_fixture/etc/sudoers.d/50-qvos-password-attempts ]] ||
  fail "login policy preflight cleanup"

linked_fixture=$(new_fixture linked)
mv "$linked_fixture/etc/security/faillock.conf" \
  "$linked_fixture/etc/security/faillock.real"
ln -s faillock.real "$linked_fixture/etc/security/faillock.conf"
if run_owner "$linked_fixture" >/dev/null 2>&1; then
  fail "linked faillock policy accepted"
fi
[[ ! -e $linked_fixture/etc/sudoers.d/50-qvos-password-attempts ]] ||
  fail "linked faillock policy caused partial publication"

rollback_fixture=$(new_fixture rollback)
rollback_before=$(sha256sum "$rollback_fixture/etc/security/faillock.conf")
: >"$visudo_state"
if QVOS_LOGIN_TEST_FAIL_SECOND=1 run_owner "$rollback_fixture" \
  >/dev/null 2>&1; then
  fail "failed staged sudoers validation reported success"
fi
[[ $(sha256sum "$rollback_fixture/etc/security/faillock.conf") == \
  "$rollback_before" &&
  ! -e $rollback_fixture/etc/sudoers.d/50-qvos-password-attempts ]] ||
  fail "login policy rollback"

printf 'ok - qvOS login policy is atomic and leaves package PAM stacks untouched\n'
