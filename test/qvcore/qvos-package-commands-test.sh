#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
home="$test_root/home"
state="$test_root/installed"
log="$test_root/actions.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_package() {
  HOME="$home" \
    QVOS_PATH="$root" \
    QVOS_TEST_PACKAGE_STATE="$state" \
    QVOS_TEST_PACKAGE_LOG="$log" \
    PATH="$test_bin:/usr/bin" \
    "$root/qvcore/packages/$1" "${@:2}"
}

install -d -m 0700 "$test_bin" "$home"
printf 'alpha\n' >"$state"
: >"$log"

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Q)
  [[ ${2:-} == "--" && $# == 3 ]] || exit 2
  grep -Fxq -- "$3" "$QVOS_TEST_PACKAGE_STATE"
  ;;
-S)
  printf 'pacman' >>"$QVOS_TEST_PACKAGE_LOG"
  printf ':<%s>' "$@" >>"$QVOS_TEST_PACKAGE_LOG"
  printf '\n' >>"$QVOS_TEST_PACKAGE_LOG"
  [[ ${QVOS_TEST_FAIL_INSTALL:-0} != "1" ]] || exit 42
  seen_boundary=0
  for argument in "$@"; do
    if (( seen_boundary )); then
      printf '%s\n' "$argument" >>"$QVOS_TEST_PACKAGE_STATE"
    elif [[ $argument == "--" ]]; then
      seen_boundary=1
    fi
  done
  sort -u -o "$QVOS_TEST_PACKAGE_STATE" "$QVOS_TEST_PACKAGE_STATE"
  ;;
-D)
  printf 'database' >>"$QVOS_TEST_PACKAGE_LOG"
  printf ':<%s>' "$@" >>"$QVOS_TEST_PACKAGE_LOG"
  printf '\n' >>"$QVOS_TEST_PACKAGE_LOG"
  ;;
-R | -Rns)
  printf 'remove' >>"$QVOS_TEST_PACKAGE_LOG"
  printf ':<%s>' "$@" >>"$QVOS_TEST_PACKAGE_LOG"
  printf '\n' >>"$QVOS_TEST_PACKAGE_LOG"
  seen_boundary=0
  for argument in "$@"; do
    if (( seen_boundary )); then
      awk -v package="$argument" '$0 != package' \
        "$QVOS_TEST_PACKAGE_STATE" >"$QVOS_TEST_PACKAGE_STATE.next"
      mv -- "$QVOS_TEST_PACKAGE_STATE.next" "$QVOS_TEST_PACKAGE_STATE"
    elif [[ $argument == "--" ]]; then
      seen_boundary=1
    fi
  done
  ;;
-Slq)
  printf 'alpha\nbeta\n'
  ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

printf 'sudo:<%s>\n' "$*" >>"$QVOS_TEST_PACKAGE_LOG"
case ${1:-} in
-v) exit 0 ;;
-n)
  [[ ${2:-} == "true" && $# == 2 ]] || exit 2
  exit 0
  ;;
esac
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/yay" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-S)
  printf 'yay' >>"$QVOS_TEST_PACKAGE_LOG"
  printf ':<%s>' "$@" >>"$QVOS_TEST_PACKAGE_LOG"
  printf '\n' >>"$QVOS_TEST_PACKAGE_LOG"
  [[ ${QVOS_TEST_FAIL_INSTALL:-0} != "1" ]] || exit 43
  seen_boundary=0
  for argument in "$@"; do
    if (( seen_boundary )); then
      argument=${argument#aur/}
      printf '%s\n' "$argument" >>"$QVOS_TEST_PACKAGE_STATE"
    elif [[ $argument == "--" ]]; then
      seen_boundary=1
    fi
  done
  sort -u -o "$QVOS_TEST_PACKAGE_STATE" "$QVOS_TEST_PACKAGE_STATE"
  ;;
-Slqa)
  printf 'delta\nepsilon\n'
  ;;
-Qqe)
  cat "$QVOS_TEST_PACKAGE_STATE"
  ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/fzf" <<'SCRIPT'
#!/bin/bash
exit 130
SCRIPT

# shellcheck source=qvcore/packages/sudo-keepalive disable=SC1091
source "$root/qvcore/packages/sudo-keepalive"
QVOS_TEST_PACKAGE_LOG="$log" PATH="$test_bin:/usr/bin" \
  qvos_sudo_keepalive_start
keepalive_pid=$QVOS_SUDO_KEEPALIVE_PID
[[ $keepalive_pid =~ ^[1-9][0-9]*$ ]] ||
  fail "native sudo keepalive did not record its child"
kill -0 "$keepalive_pid" 2>/dev/null ||
  fail "native sudo keepalive child is not running"
keepalive_sleep_pid=
for _ in {1..100}; do
  keepalive_sleep_pid=$(pgrep -P "$keepalive_pid" sleep || true)
  [[ $keepalive_sleep_pid =~ ^[1-9][0-9]*$ ]] && break
done
[[ $keepalive_sleep_pid =~ ^[1-9][0-9]*$ ]] ||
  fail "native sudo keepalive sleep child is not running"
qvos_sudo_keepalive_stop
[[ -z $QVOS_SUDO_KEEPALIVE_PID ]] ||
  fail "native sudo keepalive retained its child state"
if kill -0 "$keepalive_pid" 2>/dev/null; then
  fail "native sudo keepalive left its child running"
fi
if kill -0 "$keepalive_sleep_pid" 2>/dev/null; then
  fail "native sudo keepalive orphaned its sleep child"
fi
grep -Fqx 'sudo:<-v>' "$log" ||
  fail "native sudo keepalive did not acquire one credential"
printf 'ok - package sudo refresh has explicit bounded ownership\n'

if run_package add >/dev/null 2>&1; then
  fail "empty package installation was accepted"
fi
run_package add alpha beta
grep -Fxq beta "$state" || fail "missing package was not registered"
grep -Fqx 'pacman:<-S>:<--noconfirm>:<--needed>:<-->:<alpha>:<beta>' "$log" ||
  fail "Pacman install did not preserve exact arguments"
install_count=$(grep -c '^pacman:' "$log")
run_package add alpha beta
(( $(grep -c '^pacman:' "$log") == install_count )) ||
  fail "idempotent package add reinstalled present packages"

if QVOS_TEST_FAIL_INSTALL=1 run_package add gamma >/dev/null 2>&1; then
  fail "failed Pacman installation was reported as success"
fi
grep -Fxq gamma "$state" && fail "failed package appeared installed"
before_invalid=$(wc -l <"$log")
if run_package add --config >/dev/null 2>&1; then
  fail "option-shaped package target was accepted"
fi
(( $(wc -l <"$log") == before_invalid )) ||
  fail "invalid package target reached a privileged command"
printf 'ok - package add is validated, idempotent, exact, and verified\n'

run_package present alpha beta || fail "present package readback"
run_package missing gamma || fail "missing package readback"
if run_package present alpha gamma; then
  fail "mixed present package readback"
fi
if run_package missing alpha beta; then
  fail "all-present package set reported missing"
fi
run_package present || fail "empty present set is not true"
if run_package missing; then
  fail "empty missing set is true"
fi
printf 'ok - package presence helpers preserve set semantics\n'

run_package drop alpha gamma
grep -Fqx 'remove:<-Rns>:<--noconfirm>:<-->:<alpha>' "$log" ||
  fail "package drop did not limit removal to installed names"
grep -Fxq alpha "$state" && fail "removed package remained installed"
run_package drop
printf 'ok - package removal is exact and absence-safe\n'

run_package aur-add delta
grep -Fxq delta "$state" || fail "AUR package was not verified"
grep -Fqx 'yay:<-S>:<--noconfirm>:<--needed>:<-->:<delta>' "$log" ||
  fail "Yay install did not preserve exact arguments"
aur_install_count=$(grep -c '^yay:' "$log")
run_package aur-add delta
(( $(grep -c '^yay:' "$log") == aur_install_count )) ||
  fail "idempotent AUR add reinstalled a present package"
if run_package aur-add ../unsafe >/dev/null 2>&1; then
  fail "unsafe AUR package target was accepted"
fi
printf 'ok - explicit AUR installation is validated and verified\n'

before_cancel=$(wc -l <"$log")
run_package install
run_package aur-install
run_package remove
(( $(wc -l <"$log") == before_cancel )) ||
  fail "canceled package picker reached a mutation"
printf 'ok - package picker cancellation is a clean no-op\n'

HOME="$home" QVOS_PATH="$root" QVOS_TEST_PACKAGE_STATE="$state" \
  QVOS_TEST_PACKAGE_LOG="$log" PATH="$test_bin:/usr/bin" \
  "$root/bin/omarchy-pkg-present" beta ||
  fail "package compatibility route does not share the native owner"
"$root/bin/qv" pkg add --help | grep -F 'Binary:' >/dev/null ||
  fail "native package help"
"$root/bin/qv" pkg add --help | grep -F 'qv-pkg-add' >/dev/null ||
  fail "native package catalog binary"
printf 'ok - native and compatibility package routes share one owner\n'

package_migration="$root/qvcore/migrations/1786297116.sh"
printf '%s\n' \
  elephant \
  elephant-bluetooth \
  elephant-calc \
  elephant-clipboard \
  elephant-desktopapplications \
  elephant-files \
  elephant-menus \
  elephant-providerlist \
  elephant-runner \
  elephant-symbols \
  elephant-todo \
  elephant-unicode \
  elephant-websearch \
  omarchy-nvim \
  omarchy-walker >"$state"
: >"$log"

if QVOS_TEST_FAIL_INSTALL=1 \
  HOME="$home" QVOS_PATH="$root" QVOS_TEST_PACKAGE_STATE="$state" \
  QVOS_TEST_PACKAGE_LOG="$log" PATH="$test_bin:/usr/bin" \
  bash -euo pipefail "$package_migration" >/dev/null 2>&1; then
  fail "provider app migration ignored replacement installation failure"
fi
for package in omarchy-nvim omarchy-walker elephant-bluetooth \
  elephant-runner elephant-todo elephant-unicode; do
  grep -Fxq -- "$package" "$state" ||
    fail "provider app migration removed a package after install failure"
done
if grep -q '^remove:' "$log"; then
  fail "provider app migration removed packages before replacements"
fi

HOME="$home" QVOS_PATH="$root" QVOS_TEST_PACKAGE_STATE="$state" \
  QVOS_TEST_PACKAGE_LOG="$log" PATH="$test_bin:/usr/bin" \
  bash -euo pipefail "$package_migration" >/dev/null
for package in walker elephant elephant-calc elephant-clipboard \
  elephant-desktopapplications elephant-files elephant-menus \
  elephant-providerlist elephant-symbols elephant-websearch; do
  grep -Fxq -- "$package" "$state" ||
    fail "official package replacement is missing: $package"
done
for package in omarchy-nvim omarchy-walker elephant-bluetooth \
  elephant-runner elephant-todo elephant-unicode; do
  ! grep -Fxq -- "$package" "$state" ||
    fail "retired provider package remains: $package"
done
grep -Fqx \
  'remove:<-R>:<--noconfirm>:<-->:<omarchy-nvim>:<omarchy-walker>:<elephant-bluetooth>:<elephant-runner>:<elephant-todo>:<elephant-unicode>' \
  "$log" || fail "provider app migration removal is not exact"
if grep -q 'remove:<-Rns' "$log"; then
  fail "provider app migration used recursive package removal"
fi
package_snapshot=$(sha256sum "$state")
HOME="$home" QVOS_PATH="$root" QVOS_TEST_PACKAGE_STATE="$state" \
  QVOS_TEST_PACKAGE_LOG="$log" PATH="$test_bin:/usr/bin" \
  bash -euo pipefail "$package_migration" >/dev/null
[[ $(sha256sum "$state") == "$package_snapshot" ]] ||
  fail "provider app package migration is not idempotent"
printf 'ok - provider app bundles migrate safely to explicit official packages\n'
