#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
action_log="$test_root/actions.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_root/source/qvcore/gaming" "$test_root/home"
install -m 0755 /dev/stdin "$test_root/source/qvcore/gaming/app" <<'SCRIPT'
#!/bin/bash
printf 'app\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

run_owner() {
  HOME="$test_root/home" \
    QVOS_PATH="$test_root/source" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$root/qvcore/gaming/steam-remove" "$@"
}

[[ $(run_owner --list) == $'Keep Game Libraries\nRemove Local Game Libraries' ]] ||
  fail "Steam removal scope list"

safe_library="$test_root/home/.local/share/Steam/steamapps/libraryfolders.vdf"
install -D -m 0600 /dev/stdin "$safe_library" <<'DATA'
user library
DATA
run_owner -- "Keep Game Libraries" >/dev/null
[[ $(<"$action_log") == $'app\tremove steam' && -f $safe_library ]] ||
  fail "safe Steam removal touched game data"

: >"$action_log"
data_paths=(
  "$test_root/home/.steam"
  "$test_root/home/.local/share/Steam"
  "$test_root/home/.config/steam"
  "$test_root/home/.cache/steam"
)
for path in "${data_paths[@]}"; do
  install -D -m 0600 /dev/stdin "$path/fixture" <<'DATA'
preserve unless explicitly selected
DATA
done
run_owner -- "Remove Local Game Libraries" >/dev/null
[[ $(<"$action_log") == $'app\tremove steam' ]] ||
  fail "explicit Steam data removal bypassed the native package owner"
for path in "${data_paths[@]}"; do
  [[ ! -e $path && ! -L $path ]] || fail "explicit Steam data removal: $path"
done

external_data="$test_root/external-steam"
install -D -m 0600 /dev/stdin "$external_data/library" <<'DATA'
external library
DATA
ln -s "$external_data" "$test_root/home/.steam"
: >"$action_log"
set +e
run_owner -- "Remove Local Game Libraries" >/dev/null 2>&1
removal_status=$?
set -e
if ((removal_status == 0)); then
  fail "Steam removal followed a symbolic-link data path"
fi
[[ ! -s $action_log && -f $external_data/library ]] ||
  fail "Steam preflight preceded package or external-data mutation"
unlink -- "$test_root/home/.steam"

external_cache="$test_root/external-cache"
install -D -m 0600 /dev/stdin "$external_cache/steam/fixture" <<'DATA'
external parent
DATA
rmdir -- "$test_root/home/.cache"
ln -sT "$external_cache" "$test_root/home/.cache"
[[ -L $test_root/home/.cache && -d $test_root/home/.cache/steam ]] ||
  fail "Steam external-parent fixture"
[[ $(realpath -e -- "$test_root/home/.cache/steam") == "$external_cache/steam" ]] ||
  fail "Steam external-parent fixture resolution"
: >"$action_log"
set +e
removal_output=$(run_owner -- "Remove Local Game Libraries" 2>&1)
removal_status=$?
set -e
if ((removal_status == 0)); then
  printf '%s\n' "$removal_output" >&2
  fail "Steam removal followed a symbolic-link parent"
fi
[[ ! -s $action_log && -f $external_cache/steam/fixture ]] ||
  fail "Steam external-parent preflight preceded mutation"
unlink -- "$test_root/home/.cache"

if run_owner -- "Delete Everything" >/dev/null 2>&1; then
  fail "unknown Steam removal scope"
fi

grep -Fqx \
  'steam|package|steam|tui|true|tui|true|qv-install-gaming-steam|qvcore/gaming/steam-remove' \
  "$root/qvcore/menu/software-actions.psv" ||
  fail "Steam catalog safe removal owner"
grep -Fqx \
  'steam|uninstall|Remove Steam|action|No Steam removal choices are available.|Remove Local Game Libraries|Remove Steam, local game libraries, settings, and caches|true' \
  "$root/qvcore/tui/action/choices.psv" ||
  fail "Steam destructive scope contract"

printf 'ok - Steam removal preserves game libraries unless explicitly selected\n'
