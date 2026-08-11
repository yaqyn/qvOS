#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$root/qvcore/migrations/run"
creator="$root/qvcore/migrations/add"
test_root="$(mktemp -d)"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

make_home() {
  local home=$1

  install -d -m 0700 "$home" "$home/run"
}

source_root="$test_root/source"
home="$test_root/home"
log="$test_root/migrations.log"
install -d "$source_root/qvcore/migrations" "$source_root/qvcore/install"
make_home "$home"
install -m 0644 /dev/stdin "$source_root/qvcore/migrations/100.sh" <<'SCRIPT'
printf '100\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
install -m 0644 /dev/stdin "$source_root/qvcore/migrations/101.sh" <<'SCRIPT'
printf '101\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
chmod 0644 "$source_root/qvcore/migrations"/*.sh
state_root="$home/.local/state/qvos/migrations"
install -d -m 0700 "$state_root"
install -m 0644 /dev/null "$state_root/099.sh"
install -m 0644 /dev/null "$state_root/100.sh"

HOME="$home" \
  XDG_RUNTIME_DIR="$home/run" \
  QVOS_PATH="$source_root" \
  QVOS_TEST_MIGRATION_LOG="$log" \
  "$runner" >/dev/null
[[ $(<"$log") == "101" ]] ||
  fail "current native migration marker was not honored"
[[ ! -e $state_root/099.sh ]] ||
  fail "retired native migration marker remains"
for marker in 100.sh 101.sh; do
  [[ -f $state_root/$marker && ! -s $state_root/$marker ]] ||
    fail "native migration marker missing: $marker"
  [[ $(stat -c '%a' "$state_root/$marker") == "600" ]] ||
    fail "native migration marker is not private: $marker"
done
[[ $(stat -c '%a' "$state_root") == "700" ]] ||
  fail "native migration state is not private"
snapshot=$(find "$home/.local/state/qvos" -printf '%P|%m|%i|%T@\n' | sort)
HOME="$home" \
  XDG_RUNTIME_DIR="$home/run" \
  QVOS_PATH="$source_root" \
  QVOS_TEST_MIGRATION_LOG="$log" \
  "$runner" >/dev/null
[[ $(<"$log") == "101" ]] || fail "current migration reran"
[[ $(find "$home/.local/state/qvos" -printf '%P|%m|%i|%T@\n' | sort) == "$snapshot" ]] ||
  fail "current migration reconciliation changed state"
printf 'ok - native migration markers converge privately and retire with source\n'

baseline_root="$test_root/baseline-source"
baseline_home="$test_root/baseline-home"
baseline_state="$baseline_home/.local/state/qvos/migrations"
install -d "$baseline_root/qvcore/migrations"
make_home "$baseline_home"
install -d -m 0700 "$baseline_state"
install -m 0600 /dev/null "$baseline_state/050.sh"
HOME="$baseline_home" \
  XDG_RUNTIME_DIR="$baseline_home/run" \
  QVOS_PATH="$baseline_root" \
  "$runner" >/dev/null
[[ ! -e $baseline_state/050.sh ]] ||
  fail "compacted migration baseline retained an obsolete marker"
[[ -f $baseline_state/.lock && ! -L $baseline_state/.lock &&
  $(stat -c '%a:%s' "$baseline_state/.lock") == "600:0" ]] ||
  fail "compacted migration baseline did not retain a safe lock"
printf 'ok - an empty migration baseline remains usable and cleans old markers\n'

seed_home="$test_root/seed-home"
seed_log="$test_root/seed.log"
make_home "$seed_home"
HOME="$seed_home" \
  XDG_RUNTIME_DIR="$seed_home/missing-runtime" \
  QVOS_PATH="$source_root" \
  QVOS_INSTALL="$source_root/qvcore/install" \
  QVOS_TEST_MIGRATION_LOG="$seed_log" \
  "$runner" --mark-current >/dev/null
[[ ! -e $seed_log ]] || fail "fresh-install seeding executed a migration"
for marker in 100.sh 101.sh; do
  [[ -f $seed_home/.local/state/qvos/migrations/$marker ]] ||
    fail "fresh-install marker missing: $marker"
done
seed_lock="$seed_home/.local/state/qvos/migrations/.lock"
[[ -f $seed_lock && ! -L $seed_lock && ! -s $seed_lock ]] ||
  fail "fresh-install migration lock is unsafe"
[[ $(stat -c '%a' "$seed_lock") == "600" ]] ||
  fail "fresh-install migration lock is not private"
if HOME="$seed_home" XDG_RUNTIME_DIR="$seed_home/run" \
  QVOS_PATH="$source_root" "$runner" --mark-current >/dev/null 2>&1; then
  fail "migration seeding accepted a non-installer caller"
fi
printf 'ok - fresh installation marks native migrations without executing them\n'

failure_root="$test_root/failure-source"
failure_home="$test_root/failure-home"
failure_log="$test_root/failure.log"
install -d "$failure_root/qvcore/migrations"
make_home "$failure_home"
cat >"$failure_root/qvcore/migrations/200.sh" <<'SCRIPT'
if [[ ${QVOS_TEST_MIGRATION_FAIL:-0} == "1" ]]; then
  exit 7
fi
printf '200\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
install -m 0644 /dev/stdin "$failure_root/qvcore/migrations/201.sh" <<'SCRIPT'
printf '201\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
chmod 0644 "$failure_root/qvcore/migrations"/*.sh
set +e
failure_output=$(HOME="$failure_home" \
  XDG_RUNTIME_DIR="$failure_home/run" \
  QVOS_PATH="$failure_root" \
  QVOS_TEST_MIGRATION_FAIL=1 \
  QVOS_TEST_MIGRATION_LOG="$failure_log" \
  "$runner" 2>&1)
failure_status=$?
set -e
((failure_status == 7)) || fail "failed migration status was not preserved"
grep -Fq 'migration 200 failed; correct the error and retry' <<<"$failure_output" ||
  fail "failed migration did not explain recovery"
[[ ! -e $failure_home/.local/state/qvos/migrations/200.sh ]] ||
  fail "failed migration was marked current"
[[ ! -e $failure_log ]] || fail "later migration ran after failure"
HOME="$failure_home" \
  XDG_RUNTIME_DIR="$failure_home/run" \
  QVOS_PATH="$failure_root" \
  QVOS_TEST_MIGRATION_LOG="$failure_log" \
  "$runner" >/dev/null
[[ $(<"$failure_log") == $'200\n201' ]] ||
  fail "failed migration did not retry in order"
printf 'ok - failures stop without skip state and retry in order\n'

strict_root="$test_root/strict-source"
strict_home="$test_root/strict-home"
strict_log="$test_root/strict.log"
install -d "$strict_root/qvcore/migrations"
make_home "$strict_home"
install -m 0644 /dev/stdin "$strict_root/qvcore/migrations/250.sh" <<'SCRIPT'
printf 'before\n' >>"$QVOS_TEST_MIGRATION_LOG"
false
printf 'after\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
set +e
strict_output=$(HOME="$strict_home" \
  XDG_RUNTIME_DIR="$strict_home/run" \
  QVOS_PATH="$strict_root" \
  QVOS_TEST_MIGRATION_LOG="$strict_log" \
  "$runner" 2>&1)
strict_status=$?
set -e
((strict_status != 0)) || fail "intermediate migration failure was masked"
[[ $(<"$strict_log") == "before" ]] ||
  fail "migration continued after an intermediate failure"
[[ ! -e $strict_home/.local/state/qvos/migrations/250.sh ]] ||
  fail "masked migration failure was marked current"
grep -Fq 'migration 250 failed; correct the error and retry' \
  <<<"$strict_output" || fail "intermediate migration failure was unclear"
printf 'ok - migration strict mode prevents masked partial failures\n'

descriptor_root="$test_root/descriptor-source"
descriptor_home="$test_root/descriptor-home"
descriptor_log="$test_root/descriptor.log"
install -d "$descriptor_root/qvcore/migrations"
make_home "$descriptor_home"
install -m 0644 /dev/stdin \
  "$descriptor_root/qvcore/migrations/275.sh" <<'SCRIPT'
[[ ! -e /proc/$$/fd/9 ]]
bash -c '[[ ! -e /proc/$$/fd/9 ]]'
printf 'isolated\n' >"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
HOME="$descriptor_home" \
  XDG_RUNTIME_DIR="$descriptor_home/run" \
  QVOS_PATH="$descriptor_root" \
  QVOS_TEST_MIGRATION_LOG="$descriptor_log" \
  "$runner" >/dev/null
[[ $(<"$descriptor_log") == "isolated" ]] ||
  fail "migration lock descriptor escaped into migration descendants"
printf 'ok - the migration lock cannot escape into launched services\n'

unsafe_home="$test_root/unsafe-home"
outside="$test_root/outside"
make_home "$unsafe_home"
install -d "$unsafe_home/.local/state/qvos" "$outside"
printf 'preserve\n' >"$outside/marker"
ln -s "$outside" "$unsafe_home/.local/state/qvos/migrations"
if HOME="$unsafe_home" XDG_RUNTIME_DIR="$unsafe_home/run" \
  QVOS_PATH="$source_root" "$runner" >/dev/null 2>&1; then
  fail "migration runner accepted symbolic-link state"
fi
[[ $(<"$outside/marker") == "preserve" ]] ||
  fail "unsafe migration state changed external data"

unsafe_marker_home="$test_root/unsafe-marker-home"
make_home "$unsafe_marker_home"
install -d -m 0700 "$unsafe_marker_home/.local/state/qvos/migrations"
printf 'preserve\n' \
  >"$unsafe_marker_home/.local/state/qvos/migrations/099.sh"
if HOME="$unsafe_marker_home" XDG_RUNTIME_DIR="$unsafe_marker_home/run" \
  QVOS_PATH="$source_root" "$runner" >/dev/null 2>&1; then
  fail "migration runner accepted a nonempty retired marker"
fi
grep -Fqx 'preserve' \
  "$unsafe_marker_home/.local/state/qvos/migrations/099.sh" ||
  fail "unsafe retired migration marker was removed"
printf 'ok - unsafe state is rejected before migration mutation\n'

lock_root="$test_root/lock-source"
lock_home="$test_root/lock-home"
lock_log="$test_root/lock.log"
lock_started="$test_root/lock-started"
install -d "$lock_root/qvcore/migrations"
make_home "$lock_home"
cat >"$lock_root/qvcore/migrations/300.sh" <<'SCRIPT'
printf 'started\n' >"$QVOS_TEST_MIGRATION_STARTED"
sleep 1
printf '300\n' >>"$QVOS_TEST_MIGRATION_LOG"
SCRIPT
chmod 0644 "$lock_root/qvcore/migrations/300.sh"
HOME="$lock_home" \
  XDG_RUNTIME_DIR="$lock_home/run" \
  QVOS_PATH="$lock_root" \
  QVOS_TEST_MIGRATION_LOG="$lock_log" \
  QVOS_TEST_MIGRATION_STARTED="$lock_started" \
  "$runner" >/dev/null &
first_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -e $lock_started ]] && break
  sleep 0.01
done
[[ -e $lock_started ]] || fail "concurrency fixture did not start"
set +e
lock_output=$(HOME="$lock_home" \
  XDG_RUNTIME_DIR="$lock_home/run" \
  QVOS_PATH="$lock_root" \
  QVOS_TEST_MIGRATION_LOG="$lock_log" \
  QVOS_TEST_MIGRATION_STARTED="$lock_started" \
  "$runner" 2>&1)
lock_status=$?
set -e
((lock_status != 0)) || fail "concurrent migration run was accepted"
grep -Fq 'another migration run is active' <<<"$lock_output" ||
  fail "concurrent migration failure was unclear"
wait "$first_pid"
[[ $(<"$lock_log") == "300" ]] || fail "serialized migration result"
printf 'ok - concurrent migration execution is serialized\n'

creator_root="$test_root/creator"
install -d "$creator_root/qvcore/migrations"
git -C "$creator_root" init -q
created=$(QVOS_PATH="$creator_root" "$creator" --no-edit)
[[ $created =~ /qvcore/migrations/[0-9]+\.sh$ && -f $created ]] ||
  fail "migration creator path"
[[ $(stat -c '%a' "$created") == "644" ]] ||
  fail "migration creator mode"
[[ $(<"$created") == '# shellcheck shell=bash' ]] ||
  fail "migration creator safe template"
printf 'ok - migration creation targets only the native owner directory\n'
