#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
owner="$root/qvcore/install/helpers/errors"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
runner="$test_root/runner"
install_log="$test_root/install.log"
event_log="$test_root/events"
retry_source="$test_root/retry-source"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$retry_source"
: >"$event_log"

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
style)
  (( $# > 1 )) && printf '%s\n' "${!#}"
  ;;
choose)
  printf '%s\n' "${QVOS_TEST_GUM_CHOICE:-Exit}"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$runner" <<'SCRIPT'
#!/bin/bash
set -eEuo pipefail

owner=$1
mode=$2

stop_log_output() {
  printf 'stop\n' >>"$QVOS_TEST_EVENT_LOG"
}

clear_logo() {
  printf 'clear-logo\n'
}

export TERM_HEIGHT=8
export LOGO_HEIGHT=4
export LOGO_WIDTH=32
export PADDING_LEFT=0

source "$owner"

case $mode in
exit23)
  export CURRENT_SCRIPT="/qvOS/install/configure"
  bash -c 'exit 23'
  ;;
secret)
  /usr/bin/false "super-secret-token"
  ;;
signal)
  kill -TERM "$$"
  ;;
*)
  exit 64
  ;;
esac
SCRIPT

install -m 0644 /dev/stdin "$retry_source/install.sh" <<'SCRIPT'
#!/bin/bash

printf 'retry\n' >>"$QVOS_TEST_EVENT_LOG"
exit 42
SCRIPT

for line_number in {1..20}; do
  printf 'line-%02d\n' "$line_number"
done >"$install_log"

run_case() {
  local choice=$1
  local mode=$2
  local online=$3
  local source_root=$4

  set +e
  CASE_OUTPUT=$(
    QVOS_TEST_GUM_CHOICE="$choice" \
      QVOS_TEST_EVENT_LOG="$event_log" \
      OMARCHY_INSTALL_LOG_FILE="$install_log" \
      OMARCHY_ONLINE_INSTALL="$online" \
      QVOS_PATH="$source_root" \
      PATH="$test_bin:/usr/bin" \
      "$runner" "$owner" "$mode" 2>&1
  )
  CASE_STATUS=$?
  set -e
}

run_case Exit exit23 "" "$root"
(( CASE_STATUS == 23 )) || fail "installer error exit status preservation"
grep -Fq 'qvOS installation stopped!' <<<"$CASE_OUTPUT" ||
  fail "installer error product title"
grep -Fq 'This command halted with exit code 23:' <<<"$CASE_OUTPUT" ||
  fail "installer error reported status"
grep -Fq 'Failed script: /qvOS/install/configure' <<<"$CASE_OUTPUT" ||
  fail "installer failed-script context"
grep -Fq 'line-18' <<<"$CASE_OUTPUT" ||
  fail "small-terminal bounded log tail"
if grep -Fq 'line-17' <<<"$CASE_OUTPUT"; then
  fail "small-terminal log tail overflow"
fi
grep -Fq 'https://github.com/Yaqyn-qvOS/qvOS/issues' <<<"$CASE_OUTPUT" ||
  fail "qvOS installer support route"
if grep -Eqi 'discord|upload log|QR code' <<<"$CASE_OUTPUT"; then
  fail "retired upstream support or log upload"
fi

run_case Exit secret "" "$root"
(( CASE_STATUS == 1 )) || fail "installer command failure status"
grep -Fq 'Failed command: /usr/bin/false' <<<"$CASE_OUTPUT" ||
  fail "installer command-name context"
if grep -Fq 'super-secret-token' <<<"$CASE_OUTPUT"; then
  fail "installer error exposed command arguments"
fi

external_log="$test_root/external.log"
printf 'private-external-log\n' >"$external_log"
rm -f -- "$install_log"
ln -s "$external_log" "$install_log"
run_case Exit secret "" "$root"
if grep -Fq 'private-external-log' <<<"$CASE_OUTPUT"; then
  fail "installer error followed a symbolic-link log"
fi
rm -f -- "$install_log"
printf 'retry log\n' >"$install_log"

: >"$event_log"
run_case "Retry installation" exit23 1 "$retry_source"
(( CASE_STATUS == 42 )) || fail "installer retry process replacement"
grep -Fqx 'retry' "$event_log" || fail "installer retry source route"

run_case Exit signal "" "$root"
(( CASE_STATUS == 143 )) || fail "installer termination status"
grep -Fq 'qvOS installation interrupted.' <<<"$CASE_OUTPUT" ||
  fail "installer termination feedback"

printf 'ok - qvOS installer failures are accurate, private, bounded, and retry-safe\n'
