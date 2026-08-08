#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
runtime_root="$test_root/runtime"
systemd_log="$test_root/systemd-args"
localsend_log="$test_root/localsend-args"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home" "$test_bin" "$runtime_root"
touch "$test_home/one file.txt" "$test_home/two.txt"
install -d "$test_home/folder"

install -m 0755 /dev/stdin "$test_bin/qv-cmd-missing" <<'SCRIPT'
#!/bin/bash
[[ ${QVOS_TEST_LOCALSEND_MISSING:-0} == "1" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemd-run" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_SYSTEMD_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/wl-paste" <<'SCRIPT'
#!/bin/bash
printf 'private clipboard\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/localsend" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_LOCALSEND_LOG"
SCRIPT

run_share() {
  HOME="$test_home" \
    XDG_RUNTIME_DIR="$runtime_root" \
    QVOS_TEST_SYSTEMD_LOG="$systemd_log" \
    QVOS_TEST_LOCALSEND_LOG="$localsend_log" \
    PATH="$test_bin:/usr/bin" \
    "$root/qvcore/share/share" "$@"
}

run_share file "$test_home/one file.txt" "$test_home/two.txt"
expected=$'--user\n--quiet\n--collect\nlocalsend\n--headless\nsend\n'"$test_home/one file.txt"$'\n'"$test_home/two.txt"
[[ $(<"$systemd_log") == "$expected" ]] || fail "share file boundaries"
run_share folder "$test_home/folder"
grep -Fxq "$test_home/folder" "$systemd_log" || fail "share folder boundary"

run_share clipboard
clipboard_path=$(tail -n 1 "$systemd_log")
[[ $clipboard_path == "$runtime_root/qvos/share/clipboard."* ]] ||
  fail "private clipboard runtime path"
[[ -f $clipboard_path && $(stat -c '%a' -- "$clipboard_path") == "600" ]] ||
  fail "private clipboard mode"
run_share --send-clipboard-temp "$clipboard_path"
[[ ! -e $clipboard_path ]] || fail "clipboard cleanup"
[[ $(<"$localsend_log") == $'--headless\nsend\n'"$clipboard_path" ]] ||
  fail "clipboard sender boundaries"

printf 'do not remove\n' >"$runtime_root/qvos/share/victim"
if run_share --send-clipboard-temp \
  "$runtime_root/qvos/share/clipboard.fake/../victim" >/dev/null 2>&1; then
  fail "traversal-shaped clipboard cleanup path"
fi
[[ -f $runtime_root/qvos/share/victim ]] || fail "foreign runtime file preservation"

if QVOS_TEST_LOCALSEND_MISSING=1 run_share clipboard >/dev/null 2>&1; then
  fail "missing LocalSend"
fi
if run_share file "$test_home/missing" >/dev/null 2>&1; then
  fail "missing share file"
fi
printf 'ok - Share validates paths and cleans private clipboard staging\n'
