#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$root/qv/thunar/proton-drive-upload"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
remote_state="$test_root/remote"
action_log="$test_root/actions"
clipboard="$test_root/clipboard"
gum_state="$test_root/gum-state"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
printf '/my-files\n' >"$remote_state"
: >"$action_log"

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
input)
  printf '%s\n' "${QVOS_TEST_PROTON_DESTINATION:-/my-files/qvOS Uploads}"
  ;;
confirm)
  count=0
  [[ ! -f $QVOS_TEST_GUM_STATE ]] || count=$(<"$QVOS_TEST_GUM_STATE")
  count=$((count + 1))
  printf '%s\n' "$count" >"$QVOS_TEST_GUM_STATE"
  [[ ,${QVOS_TEST_GUM_DECLINE:-}, != *",$count,"* ]]
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/proton-drive" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

printf 'proton-drive\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
case ${1:-} in
filesystem)
  case ${2:-} in
  info)
    [[ ${3:-} == "-j" ]]
    grep -Fqx -- "${4:-}" "$QVOS_TEST_REMOTE_STATE"
    ;;
  create-folder)
    printf '%s/%s\n' "${3%/}" "$4" >>"$QVOS_TEST_REMOTE_STATE"
    ;;
  upload)
    [[ ${3:-} == "--conflict-strategy" && ${4:-} == "keep-both" ]]
    arguments=("$@")
    last_index=$((${#arguments[@]} - 1))
    destination=${arguments[last_index]}
    for ((index = 4; index < last_index; index++)); do
      printf '%s/%s\n' \
        "${destination%/}" \
        "$(basename -- "${arguments[index]}")" \
        >>"$QVOS_TEST_REMOTE_STATE"
    done
    ;;
  *)
    exit 1
    ;;
  esac
  ;;
sharing)
  case ${2:-} in
  set-url)
    [[ ${3:-} == "--role" && ${4:-} == "viewer" ]]
    ;;
  status)
    [[ ${3:-} == "-j" ]]
    printf '{"public_link":{"url":"https://drive.proton.me/urls/qvos-test"}}\n'
    ;;
  *)
    exit 1
    ;;
  esac
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/wl-copy" <<'SCRIPT'
#!/bin/bash
cat >"$QVOS_TEST_CLIPBOARD"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf 'notify\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

run_upload() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_CLIPBOARD="$clipboard" \
    QVOS_TEST_GUM_DECLINE="${QVOS_TEST_GUM_DECLINE:-}" \
    QVOS_TEST_GUM_STATE="$gum_state" \
    QVOS_TEST_PROTON_DESTINATION="${QVOS_TEST_PROTON_DESTINATION:-/my-files/qvOS Uploads}" \
    QVOS_TEST_REMOTE_STATE="$remote_state" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$helper" --run "$@"
}

single_file="$test_root/Proposal final.pdf"
printf 'proposal\n' >"$single_file"
run_upload "$single_file"

grep -Fqx '/my-files/qvOS Uploads' "$remote_state" ||
  fail "private destination creation"
grep -Fqx '/my-files/qvOS Uploads/Proposal final.pdf' "$remote_state" ||
  fail "verified uploaded file"
grep -Fqx $'proton-drive\tfilesystem upload --conflict-strategy keep-both '"$single_file"' /my-files/qvOS Uploads' \
  "$action_log" ||
  fail "safe keep-both upload command"
grep -Fqx $'proton-drive\tsharing set-url --role viewer /my-files/qvOS Uploads/Proposal final.pdf' \
  "$action_log" ||
  fail "explicit viewer link command"
[[ $(<"$clipboard") == "https://drive.proton.me/urls/qvos-test" ]] ||
  fail "verified public URL clipboard"
pass "Proton Drive upload creates private storage, verifies it, and shares only by confirmation"

duplicate_one="$test_root/one"
duplicate_two="$test_root/two"
install -d "$duplicate_one" "$duplicate_two"
printf 'one\n' >"$duplicate_one/same.txt"
printf 'two\n' >"$duplicate_two/same.txt"
: >"$action_log"
if run_upload "$duplicate_one/same.txt" "$duplicate_two/same.txt" \
  >/dev/null 2>&1; then
  fail "duplicate selected names succeed"
fi
if grep -Fq $'proton-drive\tfilesystem upload' "$action_log"; then
  fail "duplicate selected names reached upload"
fi
pass "Proton Drive upload rejects ambiguous duplicate selected names"

declined_file="$test_root/Declined.txt"
printf 'declined\n' >"$declined_file"
rm -f "$gum_state"
: >"$action_log"
set +e
QVOS_TEST_GUM_DECLINE=1 \
  QVOS_TEST_PROTON_DESTINATION="/my-files/Declined" \
  run_upload "$declined_file" >/dev/null 2>&1
declined_status=$?
set -e
((declined_status != 0)) ||
  fail "declined remote destination creation succeeds"
if grep -Fq $'proton-drive\tfilesystem upload' "$action_log"; then
  fail "declined remote destination creation reached upload"
fi
pass "Proton Drive upload honors cancellation before mutation"

newline_file="$test_root/"$'unsafe\nname.txt'
printf 'unsafe\n' >"$newline_file"
: >"$action_log"
if run_upload "$newline_file" >/dev/null 2>&1; then
  fail "newline filename succeeds"
fi
if grep -Fq $'proton-drive\tfilesystem upload' "$action_log"; then
  fail "newline filename reached upload"
fi
pass "Proton Drive upload rejects remote-path control characters"

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_PRESENTATION_ARGV_LOG"
SCRIPT
second_file="$test_root/Second upload.txt"
printf 'second\n' >"$second_file"
presentation_argv_log="$test_root/presentation-argv"
QVOS_TEST_PRESENTATION_ARGV_LOG="$presentation_argv_log" \
  PATH="$test_bin:/usr/bin" \
  "$helper" "$single_file" "$second_file"
[[ $(<"$presentation_argv_log") == "$helper"$'\n--run\n'"$single_file"$'\n'"$second_file" ]] ||
  fail "presentation upload argument boundaries"
pass "Proton Drive presentation preserves every selected path as an exact argument"
