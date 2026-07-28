#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
user_bin="$test_root/home/.local/bin"
state_dir="$test_root/state/qvos/software"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin" "$user_bin" "$state_dir"
printf '# test baseline\n' >"$state_dir/baseline.tsv"
for command_name in codex supabase custom-tool; do
  install -m 0755 /dev/stdin "$user_bin/$command_name" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
done

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
case $1 in
-Qqe) printf 'alacritty\ncustom-package\n' ;;
-Qqm) exit 0 ;;
-Qo) exit 1 ;;
*) exit 0 ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/expac" <<'SCRIPT'
#!/bin/bash
case $2 in
%N) exit 0 ;;
%d) printf 'test package\n' ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/npm" <<'SCRIPT'
#!/bin/bash
printf '{"dependencies":{}}\n'
SCRIPT

run_software() {
  HOME="$test_root/home" \
    XDG_STATE_HOME="$test_root/state" \
    PATH="$test_bin:/usr/bin" \
    OMARCHY_PATH="$root" \
    QVOS_PERSONAL_USER_BIN_DIR="$user_bin" \
    QVOS_PERSONAL_APPLICATIONS_DIR="$test_root/apps" \
    QVOS_PERSONAL_SYSTEM_BIN_DIR="$test_root/system-bin" \
    "$root/qv/maintenance/personal-software" "$@"
}

output=$(run_software --status)
grep -Eq 'Pacman[[:space:]]+custom-package' <<<"$output" ||
  fail "personal package inventory"
grep -Eq 'Standalone[[:space:]]+custom-tool' <<<"$output" ||
  fail "personal standalone inventory"
if grep -Eq '(^|[[:space:]])(alacritty|codex|supabase)([[:space:]]|$)' <<<"$output"; then
  fail "qvOS base or direct-manifest command exposed as personal software"
fi

if run_software --remove-qvcore >/dev/null 2>&1; then
  fail "retired qvCORE personal-software scope accepted"
fi
if rg -q 'qvcore|qvCORE|software-ownership|software-removal-groups' \
  "$root/qv/maintenance/personal-software"; then
  fail "personal software retains qvCORE ownership machinery"
fi

printf 'ok - personal software excludes manifest-owned tools without owning qvCORE\n'
