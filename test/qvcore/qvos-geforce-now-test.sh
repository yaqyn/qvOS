#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
temporary_root="$test_root/tmp"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home" "$test_bin" "$temporary_root"
touch "$action_log"
install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'STUB'
#!/bin/bash
exit 0
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'STUB'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-drop" <<'STUB'
#!/bin/bash
printf 'drop\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/qv-pkg-present" <<'STUB'
#!/bin/bash
[[ ${QVOS_TEST_FLATPAK_PREEXISTING:-no} == "yes" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/gum" <<'STUB'
#!/bin/bash
printf 'confirm\n' >>"$QVOS_TEST_ACTION_LOG"
[[ ${QVOS_TEST_CONFIRM:-yes} == "yes" ]]
STUB
install -m 0755 /dev/stdin "$test_bin/curl" <<'STUB'
#!/bin/bash
output=""
while (($# > 0)); do
  if [[ $1 == "--output" ]]; then
    output=$2
    shift 2
  else
    shift
  fi
done
[[ -n $output ]] || exit 2
if [[ ${QVOS_TEST_DOWNLOAD:-ok} == "fail" ]]; then
  printf 'download-failed\n' >>"$QVOS_TEST_ACTION_LOG"
  exit 22
fi
printf '%s\n' \
  '#!/bin/bash' \
  'printf "installer\\n" >>"$QVOS_TEST_ACTION_LOG"' \
  'touch "$QVOS_TEST_GEFORCE_INSTALLED"' >"$output"
truncate -s 1048576 "$output"
printf 'download\n' >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/flatpak" <<'STUB'
#!/bin/bash
case $1 in
info) [[ -f $QVOS_TEST_GEFORCE_INSTALLED ]] ;;
uninstall)
  printf 'uninstall\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  unlink -- "$QVOS_TEST_GEFORCE_INSTALLED"
  ;;
*) exit 2 ;;
esac
STUB

run_geforce() {
  HOME="$test_home" \
    QVOS_PATH="$root" \
    PATH="$test_bin:/usr/bin" \
    TMPDIR="$temporary_root" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_CONFIRM="${QVOS_TEST_CONFIRM:-yes}" \
    QVOS_TEST_DOWNLOAD="${QVOS_TEST_DOWNLOAD:-ok}" \
    QVOS_TEST_FLATPAK_PREEXISTING="${QVOS_TEST_FLATPAK_PREEXISTING:-no}" \
    QVOS_TEST_GEFORCE_INSTALLED="$test_root/geforce-installed" \
    "$@"
}

QVOS_TEST_CONFIRM=no
export QVOS_TEST_CONFIRM
run_geforce "$root/bin/qv-install-gaming-geforce-now" >/dev/null
[[ $(<"$action_log") == "confirm" ]] ||
  fail "GeForce NOW cancellation preceded every mutation and download"
[[ -z $(find "$temporary_root" -mindepth 1 -print -quit) ]] ||
  fail "cancelled GeForce NOW temporary residue"

QVOS_TEST_CONFIRM=yes
export QVOS_TEST_CONFIRM
: >"$action_log"
QVOS_TEST_DOWNLOAD=fail
export QVOS_TEST_DOWNLOAD
if run_geforce "$root/bin/qv-install-gaming-geforce-now" >/dev/null 2>&1; then
  fail "failed GeForce NOW download"
fi
[[ $(<"$action_log") == $'confirm\npackage\tflatpak\ndownload-failed\ndrop\tflatpak' ]] ||
  fail "failed GeForce NOW download package rollback"
[[ -z $(find "$temporary_root" -mindepth 1 -print -quit) ]] ||
  fail "failed GeForce NOW download cleanup"

QVOS_TEST_DOWNLOAD=ok
export QVOS_TEST_DOWNLOAD
: >"$action_log"
run_geforce "$root/bin/omarchy-install-gaming-geforce-now" >/dev/null
[[ -f $test_root/geforce-installed ]] || fail "GeForce NOW result verification fixture"
[[ $(<"$action_log") == $'confirm\npackage\tflatpak\ndownload\ninstaller' ]] ||
  fail "GeForce NOW confirmed package, download, and vendor execution order"
[[ -z $(find "$temporary_root" -mindepth 1 -print -quit) ]] ||
  fail "GeForce NOW private download cleanup"

user_data="$test_home/.var/app/com.nvidia.geforcenow/config/user.conf"
install -D -m 0600 /dev/stdin "$user_data" <<'DATA'
user data
DATA
: >"$action_log"
run_geforce "$root/bin/qv-remove-gaming-geforce-now" >/dev/null
[[ $(<"$action_log") == $'uninstall\tuninstall -y com.nvidia.geforcenow' ]] ||
  fail "GeForce NOW exact Flatpak removal"
[[ -f $user_data ]] || fail "GeForce NOW normal removal preserves user data"

if run_geforce "$root/bin/qv-install-gaming-geforce-now" unexpected \
  >/dev/null 2>&1; then
  fail "GeForce NOW argument validation"
fi

printf 'ok - GeForce NOW stays an explicit, cleaned, result-verified vendor install\n'
