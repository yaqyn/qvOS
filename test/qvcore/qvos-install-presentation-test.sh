#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
presentation="$root/qvcore/install/helpers/presentation.sh"
show_env="$root/qvcore/install/preflight/show-env.sh"
logging="$root/qvcore/install/helpers/logging.sh"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
event_log="$test_root/events"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"$QVOS_TEST_EVENT_LOG"
SCRIPT

# shellcheck disable=SC2016
size_output=$(
  setsid env \
    QVOS_PATH="$root" \
    QVOS_TEST_EVENT_LOG="$event_log" \
    PATH="$test_bin:/usr/bin" \
    bash -c '
      set -eEuo pipefail
      source "$1"
      printf "%s %s\n" "$TERM_WIDTH" "$TERM_HEIGHT"
    ' _ "$presentation" </dev/null 2>/dev/null
)
[[ $size_output == "80 24" ]] ||
  fail "terminal probe fallback under strict error handling"

: >"$event_log"
# shellcheck disable=SC2016
env \
  QVOS_PATH="/home/test/.local/share/qvos" \
  QVOS_INSTALL="/home/test/.local/share/qvos/qvcore/install" \
  QVOS_REPO=$'https://example.invalid/qvos\e[31m\nforged' \
  QVOS_PROVIDER_CHANNEL="stable" \
  QVOS_USER_NAME="Private Test Name" \
  QVOS_USER_EMAIL="private@example.invalid" \
  QVOS_TEST_EVENT_LOG="$event_log" \
  PATH="$test_bin:/usr/bin" \
  bash -c 'set -eEuo pipefail; source "$1"' _ "$show_env"

grep -Fqx -- 'log --level info   QVOS_USER_NAME=[set]' "$event_log" ||
  fail "installer user name presence reporting"
grep -Fqx -- 'log --level info   QVOS_USER_EMAIL=[set]' "$event_log" ||
  fail "installer user email presence reporting"
grep -Fqx -- 'log --level info   QVOS_PATH=/home/test/.local/share/qvos' "$event_log" ||
  fail "installer diagnostic environment reporting"
if rg -n 'Private Test Name|private@example\.invalid' "$event_log"; then
  fail "installer environment log exposes personal identity"
fi
if LC_ALL=C rg -n $'\e|forged$' "$event_log"; then
  fail "installer environment log permits terminal or line injection"
fi

# A progress renderer can finish after its output terminal disappears. Screen
# cleanup is presentation only and must not fail the completed install stage.
# shellcheck disable=SC1090
source "$logging"
clear() {
  return 17
}
sleep 60 &
QVOS_ISO_PROGRESS_PID=$!
stop_log_output
[[ -z ${QVOS_ISO_PROGRESS_PID:-} ]] ||
  fail "installer progress process cleanup"

printf 'ok - qvOS installer presentation survives unavailable TTYs without logging identity values\n'
