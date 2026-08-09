#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
packages="$test_root/packages"
mise_tools="$test_root/mise-tools"
action_log="$test_root/actions.log"
state_root="$test_home/.local/state/qvos/development/environments"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/development/environments" \
  "$source_root/development/devel" \
  "$source_root/qvcore/direct" \
  "$source_root/qvcore/install/packaging" \
  "$test_home" \
  "$test_bin" \
  "$packages" \
  "$mise_tools"
install -m 0755 "$root/development/environments/manage" \
  "$source_root/development/environments/manage"
install -m 0644 "$root/development/environments/environments.psv" \
  "$source_root/development/environments/environments.psv"
install -m 0644 "$root/development/devel/packages.tsv" \
  "$source_root/development/devel/packages.tsv"
install -m 0644 "$root/qvcore/direct/manifest.tsv" \
  "$source_root/qvcore/direct/manifest.tsv"
install -m 0644 "$root/qvcore/install/packaging/base.packages" \
  "$source_root/qvcore/install/packaging/base.packages"

for command_name in qv-pkg-present qv-pkg-add qv-pkg-drop pacman mise; do
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${0##*/} in
qv-pkg-present)
  [[ -f $QVOS_TEST_PACKAGES/$1 ]]
  ;;
qv-pkg-add)
  for package in "$@"; do
    [[ ${QVOS_TEST_FAIL_PACKAGE:-} != "$package" ]] || exit 91
    install -m 0644 /dev/null "$QVOS_TEST_PACKAGES/$package"
    printf 'package-add\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
qv-pkg-drop)
  for package in "$@"; do
    rm -f -- "$QVOS_TEST_PACKAGES/$package"
    printf 'package-drop\t%s\n' "$package" >>"$QVOS_TEST_LOG"
  done
  ;;
pacman)
  [[ $1 == "-Rns" && $2 == "--print" && $3 == "--" ]]
  printf 'package-preflight\t%s\n' "$4" >>"$QVOS_TEST_LOG"
  ;;
mise)
  case $1 in
  ls)
    [[ $2 == "--global" && $4 == "--json" ]]
    tool=$3
    if [[ -f $QVOS_TEST_MISE/$tool ]]; then
      request=$(<"$QVOS_TEST_MISE/$tool")
      jq -n --arg request "$request" \
        '[{requested_version: $request, installed: true, active: true}]'
    else
      printf '[]\n'
    fi
    ;;
  use)
    [[ $2 == "--global" && $3 == "--yes" ]]
    source=$4
    [[ ${QVOS_TEST_FAIL_MISE:-} != "$source" ]] || exit 92
    tool=${source%@*}
    request=${source##*@}
    printf '%s\n' "$request" >"$QVOS_TEST_MISE/$tool"
    printf 'mise-use\t%s\n' "$source" >>"$QVOS_TEST_LOG"
    ;;
  unuse)
    [[ $2 == "--global" && $3 == "--yes" ]]
    source=$4
    tool=${source%@*}
    rm -f -- "$QVOS_TEST_MISE/$tool"
    printf 'mise-unuse\t%s\n' "$source" >>"$QVOS_TEST_LOG"
    ;;
  *) exit 93 ;;
  esac
  ;;
esac
SCRIPT
done

run_manager() {
  HOME="$test_home" \
    XDG_STATE_HOME="$test_home/.local/state" \
    PATH="$test_bin:/usr/bin" \
    QVOS_PATH="$source_root" \
    QVOS_TEST_LOG="$action_log" \
    QVOS_TEST_MISE="$mise_tools" \
    QVOS_TEST_PACKAGES="$packages" \
    "$source_root/development/environments/manage" "$@"
}

if run_manager install invalid >"$test_root/invalid.out" 2>&1; then
  fail "invalid environment was accepted"
fi
[[ ! -e $state_root && ! -L $state_root ]] ||
  fail "invalid environment created state"

run_manager install node >/dev/null
[[ -f $state_root/node && $(<"$state_root/node") == "mise|node@lts" ]] ||
  fail "Node enrollment does not contain its exact component"
[[ $(stat -c '%a' "$state_root") == "700" &&
  $(stat -c '%a' "$state_root/node") == "600" &&
  $(stat -c '%a' "$state_root/owned.psv") == "600" ]] ||
  fail "environment enrollment is not private"
grep -Fqx 'mise|node@lts' "$state_root/owned.psv" ||
  fail "qvOS-created Node ownership was not recorded"
run_manager install node >/dev/null
[[ $(grep -c $'^mise-use\tnode@lts$' "$action_log") == 1 ]] ||
  fail "environment rerun reinstalled a verified runtime"
printf '22\n' >"$mise_tools/node"
run_manager remove node >/dev/null 2>&1
[[ -f $mise_tools/node && $(<"$mise_tools/node") == "22" ]] ||
  fail "environment removal discarded a changed Mise selection"
! grep -Fqx 'mise|node@lts' "$state_root/owned.psv" ||
  fail "changed Mise ownership remained after environment removal"

printf '1.23\n' >"$mise_tools/go"
run_manager install go >/dev/null
[[ $(<"$mise_tools/go") == "1.23" ]] ||
  fail "environment installation replaced a pre-existing Mise selection"
! grep -Fqx 'mise|go@latest' "$state_root/owned.psv" ||
  fail "environment installation adopted a pre-existing Mise selection"
run_manager remove go >/dev/null
[[ -f $mise_tools/go && $(<"$mise_tools/go") == "1.23" ]] ||
  fail "environment removal discarded a pre-existing Mise selection"

run_manager install java >/dev/null
run_manager install scala >/dev/null
run_manager remove java >/dev/null
[[ ! -e $state_root/java && -f $mise_tools/java ]] ||
  fail "Java removal broke the enrolled Scala environment"
grep -Fqx 'mise|java@latest' "$state_root/owned.psv" ||
  fail "shared Java ownership was discarded too early"
run_manager remove scala >/dev/null
for tool in java scala scala-cli; do
  [[ ! -e $mise_tools/$tool ]] ||
    fail "last shared runtime owner did not remove: $tool"
done
if rg -q '^mise\|(java|scala|scala-cli)@' "$state_root/owned.psv"; then
  fail "shared Mise ownership remained after the last enrollment"
fi

install -m 0644 /dev/null "$packages/composer"
run_manager install php >/dev/null
for package in php composer php-sqlite; do
  [[ -f $packages/$package ]] || fail "PHP package missing: $package"
done
run_manager remove php >/dev/null
[[ -f $packages/composer ]] || fail "PHP removal deleted a pre-existing package"
[[ ! -e $packages/php && ! -e $packages/php-sqlite ]] ||
  fail "PHP removal retained qvOS-created packages"
if grep -Fq $'package-drop\tcomposer' "$action_log"; then
  fail "PHP removal claimed a pre-existing package"
fi

set +e
failure_output=$(QVOS_TEST_FAIL_MISE=rust@latest run_manager install rust 2>&1)
failure_status=$?
set -e
((failure_status != 0)) || fail "failed Mise install reported success"
[[ ! -e $state_root/rust && ! -e $state_root/.rust.pending &&
  ! -e $state_root/.rust.transaction && ! -e $mise_tools/rust ]] ||
  fail "failed Mise install retained partial state"
! grep -Fqx 'mise|rust@latest' "$state_root/owned.psv" ||
  fail "failed Mise install retained ownership"
[[ $failure_output != *"installed and enrolled"* ]] ||
  fail "failed Mise install claimed enrollment"

unsafe_home="$test_root/unsafe-home"
external_state="$test_root/external-state"
install -d "$unsafe_home/.local/state/qvos/development" "$external_state"
ln -s "$external_state" \
  "$unsafe_home/.local/state/qvos/development/environments"
if HOME="$unsafe_home" \
  XDG_STATE_HOME="$unsafe_home/.local/state" \
  PATH="$test_bin:/usr/bin" \
  QVOS_PATH="$source_root" \
  QVOS_TEST_LOG="$action_log" \
  QVOS_TEST_MISE="$mise_tools" \
  QVOS_TEST_PACKAGES="$packages" \
  "$source_root/development/environments/manage" install node \
  >"$test_root/unsafe.out" 2>"$test_root/unsafe.err"; then
  fail "environment manager accepted a linked state root"
fi
grep -Fq 'Refusing unsafe environment state' "$test_root/unsafe.err" ||
  fail "environment manager omitted its unsafe-state error"
[[ -z $(find "$external_state" -mindepth 1 -print -quit) ]] ||
  fail "environment manager wrote through a linked state root"

mv "$source_root/qvcore/install/packaging/base.packages" \
  "$source_root/qvcore/install/packaging/base.packages.safe"
ln -s "$source_root/qvcore/install/packaging/base.packages.safe" \
  "$source_root/qvcore/install/packaging/base.packages"
action_count=$(wc -l <"$action_log")
if run_manager install java >"$test_root/source.out" 2>"$test_root/source.err"; then
  fail "environment manager accepted a linked ownership source"
fi
grep -Fq 'Refusing an unsafe development ownership source' \
  "$test_root/source.err" ||
  fail "environment manager omitted its unsafe-source error"
[[ $(wc -l <"$action_log") == "$action_count" ]] ||
  fail "environment manager mutated tools after unsafe-source detection"
unlink -- "$source_root/qvcore/install/packaging/base.packages"
mv "$source_root/qvcore/install/packaging/base.packages.safe" \
  "$source_root/qvcore/install/packaging/base.packages"

environment_count=$(awk -F '|' '$1 !~ /^#/ && NF { count++ } END { print count }' \
  "$root/development/environments/environments.psv")
((environment_count == 18)) || fail "native environment inventory count"
for forbidden in \
  'curl .*\|.*sh' \
  'rustup self uninstall' \
  'rm -rf' \
  'sudo sed' \
  '\.bashrc' \
  '/usr/local/bin/opam'; do
  if rg -q "$forbidden" \
    "$root/development/environments" \
    "$root/bin/qv-install-dev-env" \
    "$root/bin/qv-remove-dev-env" \
    "$root/bin/omarchy-install-dev-env" \
    "$root/bin/omarchy-remove-dev-env"; then
    fail "native environment lifecycle retains unsafe behavior: $forbidden"
  fi
done
for route in install remove; do
  native="$root/bin/qv-$route-dev-env"
  compatibility="$root/bin/omarchy-$route-dev-env"
  [[ -x $native && -x $compatibility ]] ||
    fail "development environment adapter mode: $route"
  rg -q '^# qv:summary=' "$native" ||
    fail "native environment adapter metadata: $route"
  ! rg -q '^# (qv|omarchy):' "$compatibility" ||
    fail "environment compatibility adapter duplicates metadata: $route"
  (($(wc -l <"$compatibility") <= 5)) ||
    fail "environment compatibility adapter contains implementation: $route"
done
if rg --pcre2 -q '^((ruby-on-rails|go|php|python|elixir|zig|rust|java|dotnet|ocaml|clojure|scala|node|bun|deno|laravel|symfony|phoenix)\|)(?!state\|)' \
  "$root/qvcore/menu/software-actions.psv"; then
  fail "development environment menu infers ownership from installed software"
fi
if rg -q 'omarchy-(install|remove)-dev-env' \
  "$root/qvcore/menu/software-actions.psv"; then
  fail "development environment menu routes through compatibility"
fi

printf 'ok - development environments are private, shared, retry-safe, and non-adopting\n'
