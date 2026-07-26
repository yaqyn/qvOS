#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
command_path="$root/qv/desktop/web/qvos-website-open"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
launch_log="$test_root/launch"

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

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash

case ",${QVOS_TEST_COMMANDS:-}," in
*,"$1",*) exit 0 ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-menu-input" <<'SCRIPT'
#!/bin/bash

printf '%s\n' "${QVOS_TEST_URL_INPUT:-}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-webapp" <<'SCRIPT'
#!/bin/bash

printf '%s\n' "$*" >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash

exit 0
SCRIPT

run_launcher() {
  QVOS_TEST_COMMANDS="${QVOS_TEST_COMMANDS:-}" \
    QVOS_TEST_URL_INPUT="${QVOS_TEST_URL_INPUT:-}" \
    QVOS_TEST_LAUNCH_LOG="$launch_log" \
    PATH="$test_bin:/usr/bin" \
    "$command_path" "$@"
}

assert_launch() {
  local input="$1"
  local expected="$2"
  local description="$3"

  QVOS_TEST_COMMANDS="omarchy-launch-webapp" run_launcher "$input"
  [[ "$(<"$launch_log")" == "$expected" ]] || fail "$description"
  pass "$description"
}

assert_rejected() {
  local input="$1"
  local description="$2"

  rm -f "$launch_log"
  if QVOS_TEST_COMMANDS="omarchy-launch-webapp" run_launcher "$input" >/dev/null 2>&1; then
    fail "$description"
  fi
  [[ ! -e $launch_log ]] || fail "$description"
  pass "$description"
}

assert_launch "youtube" "https://www.youtube.com" "single names receive HTTPS, www, and .com"
assert_launch "youtube.net" "https://www.youtube.net" "explicit common TLDs are preserved"
assert_launch "music.youtube" "https://music.youtube.com" "subdomain shorthand receives only .com"
assert_launch "music.youtube.net" "https://music.youtube.net" "complete subdomains are preserved"
assert_launch "youtube/watch?v=example" "https://www.youtube.com/watch?v=example" "paths and queries survive shorthand completion"
assert_launch "youtube.co.uk" "https://youtube.co.uk" "two-letter country endings are preserved"
assert_launch "http://youtube.net/watch" "https://youtube.net/watch" "explicit HTTP URLs are upgraded to HTTPS"
assert_launch "https://youtube.com/watch?v=example" "https://youtube.com/watch?v=example" "explicit HTTPS URLs are preserved"
assert_launch "https://example.com:443/path" "https://example.com:443/path" "valid explicit ports are preserved"
assert_launch "https://127.0.0.1/settings" "https://127.0.0.1/settings" "valid explicit IPv4 websites are preserved"
pass "website names and explicit URLs normalize safely"

assert_launch "youtube.com/watch?v=abc&utm_source=test&fbclid=123&t=40" "https://www.youtube.com/watch?v=abc&t=40" "known tracking fields are removed"
assert_launch "example.com/page?UTM_MEDIUM=email&gclid=123#section" "https://www.example.com/page#section" "case-insensitive tracking fields are removed before fragments"
assert_launch "example.com/?ref=partner&source=menu&id=3" "https://www.example.com/?ref=partner&source=menu&id=3" "ambiguous query fields are preserved"
assert_launch "example.com/reset?token=abc&utm_source=test" "https://www.example.com/reset?token=abc&utm_source=test" "sensitive links bypass cleaning"
assert_launch "https://files.example.com/file?X-Amz-Signature=abc&utm_source=test" "https://files.example.com/file?X-Amz-Signature=abc&utm_source=test" "signed links bypass cleaning"
assert_launch "example.com/callback?utm_source=test#access_token=abc" "https://www.example.com/callback?utm_source=test#access_token=abc" "fragment authentication links bypass cleaning"
assert_launch "example.com/authorize?client_id=abc&utm_source=test" "https://www.example.com/authorize?client_id=abc&utm_source=test" "authorization links bypass cleaning"
pass "tracking cleanup preserves functional and sensitive links"

QVOS_TEST_COMMANDS="omarchy-menu-input,omarchy-launch-webapp" QVOS_TEST_URL_INPUT="  www.youtube.com  " run_launcher
[[ "$(<"$launch_log")" == "https://www.youtube.com" ]] || fail "prompted URL launch"
pass "the keybinding prompt launches the selected website as an Omarchy web app"

assert_rejected "ftp://example.com" "unsupported schemes are rejected"
assert_rejected "https://user:pass@example.com" "embedded credentials are rejected"
assert_rejected "https:///missing-host" "missing hostnames are rejected"
assert_rejected "https://-example.com" "malformed explicit hostnames are rejected"
assert_rejected "https://example.com:0" "zero ports are rejected"
assert_rejected "https://example.com:65536" "out-of-range ports are rejected"
assert_rejected "https://999.1.1.1" "invalid IPv4 websites are rejected"
assert_rejected "https://[::1]" "unsupported IPv6 websites are rejected"
assert_rejected "not a website" "spaces are rejected"
assert_rejected ".youtube" "leading dots are rejected"
assert_rejected "youtube..com" "empty hostname labels are rejected"
assert_rejected "youtubé" "non-ASCII shorthand is rejected"
assert_rejected $'youtube\n.com' "control characters are rejected"
printf -v oversized_url 'a%.0s' {1..2049}
assert_rejected "$oversized_url" "oversized websites are rejected"
printf -v oversized_label 'a%.0s' {1..64}
assert_rejected "$oversized_label.com" "oversized hostname labels are rejected"
pass "strict input and URL validation rejects unsafe forms"

rm -f "$launch_log"
QVOS_TEST_COMMANDS="omarchy-menu-input,omarchy-launch-webapp" QVOS_TEST_URL_INPUT="" run_launcher
[[ ! -e $launch_log ]] || fail "empty prompt launch"
pass "an empty prompt exits without launching"

if QVOS_TEST_COMMANDS="" run_launcher youtube.com >/dev/null 2>&1; then
  fail "missing web-app launcher failure"
fi
pass "a missing web-app launcher fails clearly"

set +e
QVOS_TEST_COMMANDS="omarchy-launch-webapp" run_launcher youtube.com extra >/dev/null 2>&1
usage_status=$?
set -e
((usage_status == 2)) || fail "unexpected argument status"
pass "unexpected arguments show usage"
