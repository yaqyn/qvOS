#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
context_dir="$root/qvcore/desktop/context"
thunar_dir="$root/qvcore/thunar"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
project_dir="$test_root/project space"
launch_log="$test_root/launch"
runtime_root="$test_root/.local/share/qvos"

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

install -d "$test_bin" "$project_dir/subdir" "$runtime_root/desktop"
cp -a "$context_dir" "$runtime_root/desktop/context"
touch "$project_dir/example.txt"
ln -s "$project_dir" "$test_root/project-link"

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash

case $1 in
activewindow) printf '%s\n' "${QVOS_TEST_ACTIVE_WINDOW:-{}}" ;;
*) exit 1 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/uwsm-app" <<'SCRIPT'
#!/bin/bash

printf '%s\n' "$*" >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-editor" <<'SCRIPT'
#!/bin/bash

printf 'editor %s\n' "$*" >"$QVOS_TEST_LAUNCH_LOG"
SCRIPT

run_with_mocks() {
  QVOS_TEST_ACTIVE_WINDOW="${QVOS_TEST_ACTIVE_WINDOW:-{}}" \
    QVOS_TEST_LAUNCH_LOG="$launch_log" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$@"
}

canonical_project="$(readlink -f "$project_dir")"
actual="$("$context_dir/qvos-active-location" "$project_dir")"
[[ $actual == "$canonical_project" ]] || fail "explicit directory"

actual="$("$context_dir/qvos-active-location" "$project_dir/example.txt")"
[[ $actual == "$canonical_project" ]] || fail "explicit file"

project_uri="file://${project_dir// /%20}"
actual="$("$context_dir/qvos-active-location" "$project_uri")"
[[ $actual == "$canonical_project" ]] || fail "encoded file URI"

actual="$("$context_dir/qvos-active-location" "$test_root/project-link")"
[[ $actual == "$canonical_project" ]] || fail "symlink canonicalization"
pass "explicit locations normalize to canonical directories"

if "$context_dir/qvos-active-location" "$test_root/missing" >/dev/null 2>&1; then
  fail "missing path accepted"
fi
pass "missing locations are rejected"

run_with_mocks "$context_dir/qvos-launch-terminal-here" terminal "$project_dir"
[[ "$(<"$launch_log")" == "-- xdg-terminal-exec --dir=$canonical_project" ]] || fail "terminal route"

run_with_mocks "$context_dir/qvos-launch-terminal-here" root "$project_dir"
[[ "$(<"$launch_log")" == "-- xdg-terminal-exec --dir=$canonical_project sudo -s" ]] || fail "root terminal route"

run_with_mocks "$context_dir/qvos-launch-terminal-here" codex "$project_dir"
[[ "$(<"$launch_log")" == "-- xdg-terminal-exec --app-id=org.qvos.codex --title=Codex --dir=$canonical_project env QVOS_SLEEP_INHIBIT_REASON=Codex session is active $test_root/.local/share/qvos/bin/omarchy-system-inhibit-sleep $test_root/.local/bin/codex" ]] || fail "Codex route"

run_with_mocks "$context_dir/qvos-launch-terminal-here" codex-yolo "$project_dir"
[[ "$(<"$launch_log")" == "-- xdg-terminal-exec --app-id=org.qvos.codex --title=Codex YOLO --dir=$canonical_project env QVOS_SLEEP_INHIBIT_REASON=Codex session is active $test_root/.local/share/qvos/bin/omarchy-system-inhibit-sleep $test_root/.local/bin/codex --yolo" ]] || fail "Codex YOLO route"

run_with_mocks "$context_dir/qvos-launch-editor-here" "$project_dir"
[[ "$(<"$launch_log")" == "editor $canonical_project" ]] || fail "editor route"
pass "terminal, root, Codex YOLO, and editor launchers preserve location"

run_with_mocks "$thunar_dir/open-here" terminal "$project_dir/example.txt"
[[ "$(<"$launch_log")" == "-- xdg-terminal-exec --dir=$canonical_project" ]] || fail "Thunar terminal route"

run_with_mocks "$thunar_dir/open-here" editor "$project_dir/example.txt"
[[ "$(<"$launch_log")" == "editor $canonical_project" ]] || fail "Thunar editor route"
pass "Thunar actions route files through the shared location resolver"

QVOS_TEST_ACTIVE_WINDOW="$(jq -cn --arg title "$canonical_project - Thunar" '{class: "thunar", title: $title, pid: 0}')"
export QVOS_TEST_ACTIVE_WINDOW
actual="$(run_with_mocks "$context_dir/qvos-active-location")"
[[ $actual == "$canonical_project" ]] || fail "active Thunar location"

QVOS_TEST_ACTIVE_WINDOW="$(jq -cn --arg title "$canonical_project - Code - OSS" '{class: "code-oss", title: $title, pid: 0}')"
export QVOS_TEST_ACTIVE_WINDOW
actual="$(run_with_mocks "$context_dir/qvos-active-location")"
[[ $actual == "$canonical_project" ]] || fail "active Code location"
pass "active Thunar and Code windows resolve their full-path titles"

set +e
run_with_mocks "$thunar_dir/open-here" removed "$project_dir" >/dev/null 2>&1
usage_status=$?
set -e
((usage_status == 2)) || fail "removed launcher mode"
pass "removed launcher modes stay unavailable"
