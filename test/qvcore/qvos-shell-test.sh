#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/shell/install"
test_root=$(mktemp -d)

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_owner() {
  HOME=$1 QVOS_PATH="$root" "$owner"
}

"$root/qvcore/shell/check"

fresh_home="$test_root/fresh-home"
install -d "$fresh_home/.local/share"
ln -s "$root" "$fresh_home/.local/share/qvos"
cp "$root/qvcore/shell/files/bashrc" "$fresh_home/.bashrc"
run_owner "$fresh_home"
# shellcheck disable=SC2016
grep -Fqx 'source "$HOME/.local/share/qvos/qvcore/shell/files/rc"' \
  "$fresh_home/.bashrc" || fail "fresh native Bash source"
# shellcheck disable=SC2016
if grep -Fqx 'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$fresh_home/.bashrc"; then
  fail "fresh Bash configuration duplicates runtime aliases"
fi
HOME="$fresh_home" QVOS_PATH="$root" TERM=dumb \
  bash --noprofile --norc -c \
  'source "$HOME/.local/share/qvos/qvcore/shell/files/rc"; alias cy >/dev/null; alias hx >/dev/null; complete -p qv >/dev/null' ||
  fail "fresh shell startup"

native_home="$test_root/native-home"
install -d "$native_home"
install -m 0644 /dev/stdin "$native_home/.bashrc" <<'BASHRC'
source "$HOME/.local/share/qvos/qvcore/shell/files/rc"
source "$HOME/.local/share/qvos/qvcore/shell/files/rc"
source "$HOME/.local/lib/qvos/shell/aliases"
export PERSONAL_SHELL_VALUE=preserve
BASHRC
cp "$native_home/.bashrc" "$test_root/native-bashrc-before"
run_owner "$native_home"
runtime_aliases="$native_home/.local/lib/qvos/shell/aliases"
cmp -s "$root/qvcore/shell/aliases" "$runtime_aliases" ||
  fail "runtime alias publication"
[[ $(stat -c '%a' -- "$runtime_aliases") == "644" ]] ||
  fail "runtime alias mode"
# shellcheck disable=SC2016
[[ $(grep -Fxc 'source "$HOME/.local/share/qvos/qvcore/shell/files/rc"' \
  "$native_home/.bashrc") == 1 ]] || fail "native Bash source deduplication"
# shellcheck disable=SC2016
if grep -Fqx 'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$native_home/.bashrc"; then
  fail "native Bash configuration duplicates runtime aliases"
fi
grep -Fqx 'export PERSONAL_SHELL_VALUE=preserve' "$native_home/.bashrc" ||
  fail "personal Bash content preservation"
native_backup_root="$native_home/.local/state/qvos/shell-backups"
[[ -d $native_backup_root && ! -L $native_backup_root &&
  $(stat -c '%a' "$native_home/.local/state/qvos") == "700" &&
  $(stat -c '%a' "$native_backup_root") == "700" ]] ||
  fail "private native Bash backup directory"
mapfile -t native_backups < <(find "$native_backup_root" -maxdepth 1 \
  -type f -name 'bashrc.*' -print)
(( ${#native_backups[@]} == 1 )) || fail "private native Bash backup"
cmp -s "$test_root/native-bashrc-before" "${native_backups[0]}" ||
  fail "private native Bash backup content"
if compgen -G "$native_home/.bashrc.bak.*" >/dev/null; then
  fail "native Bash backup leaked beside active configuration"
fi

first_hashes=$(find "$native_home" -type f -exec sha256sum {} + | sort)
first_inodes=$(find "$native_home" -type f -exec stat -c '%i %n' {} + | sort)
run_owner "$native_home"
[[ $(find "$native_home" -type f -exec sha256sum {} + | sort) == \
  "$first_hashes" ]] || fail "idempotent shell content"
[[ $(find "$native_home" -type f -exec stat -c '%i %n' {} + | sort) == \
  "$first_inodes" ]] || fail "idempotent shell publication"

custom_home="$test_root/custom-home"
install -d "$custom_home"
install -m 0644 /dev/stdin "$custom_home/.bashrc" <<'BASHRC'
export CUSTOM_ONLY=yes
source "$HOME/.local/lib/qvos/shell/aliases"
source "$HOME/.local/lib/qvos/shell/aliases"
BASHRC
cp "$custom_home/.bashrc" "$test_root/custom-bashrc-before"
run_owner "$custom_home"
# shellcheck disable=SC2016
[[ $(grep -Fxc 'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$custom_home/.bashrc") == 1 ]] || fail "custom Bash runtime source"
grep -Fqx 'export CUSTOM_ONLY=yes' "$custom_home/.bashrc" ||
  fail "custom Bash content preservation"
custom_backup_root="$custom_home/.local/state/qvos/shell-backups"
mapfile -t custom_backups < <(find "$custom_backup_root" -maxdepth 1 \
  -type f -name 'bashrc.*' -print)
(( ${#custom_backups[@]} == 1 )) || fail "private custom Bash backup"
cmp -s "$test_root/custom-bashrc-before" "${custom_backups[0]}" ||
  fail "private custom Bash backup content"
if compgen -G "$custom_home/.bashrc.bak.*" >/dev/null; then
  fail "custom Bash backup leaked beside active configuration"
fi

historical_home="$test_root/historical-home"
install -d "$historical_home"
install -m 0644 /dev/stdin "$historical_home/.bashrc" <<'BASHRC'
source ~/.local/share/qvos/default/bash/rc
source "$HOME/.local/share/omarchy/default/bash/rc"
source "$HOME/.local/share/qvos/shell/aliases"
alias hx="helix"
BASHRC
run_owner "$historical_home"
for preserved_line in \
  'source ~/.local/share/qvos/default/bash/rc' \
  "source \"\$HOME/.local/share/omarchy/default/bash/rc\"" \
  "source \"\$HOME/.local/share/qvos/shell/aliases\"" \
  'alias hx="helix"'; do
  grep -Fqx "$preserved_line" "$historical_home/.bashrc" ||
    fail "historical Bash content preservation: $preserved_line"
done
# shellcheck disable=SC2016
[[ $(grep -Fxc 'source "$HOME/.local/lib/qvos/shell/aliases"' \
  "$historical_home/.bashrc") == 1 ]] ||
  fail "historical Bash file receives only the native runtime source"

unsafe_home="$test_root/unsafe-home"
outside="$test_root/outside-bashrc"
install -d "$unsafe_home"
printf 'outside\n' >"$outside"
ln -s "$outside" "$unsafe_home/.bashrc"
if run_owner "$unsafe_home" >/dev/null 2>&1; then
  fail "linked Bash configuration accepted"
fi
[[ $(<"$outside") == "outside" ]] || fail "linked Bash target changed"

completion_output=$(HOME="$custom_home" QVOS_PATH="$root" \
  PATH="$root/bin:/usr/bin" bash --noprofile --norc -c \
  'source "$QVOS_PATH/qvcore/shell/files/completions"; complete -p qv; complete -p omarchy')
grep -Fq 'complete -o default -F _qvos_complete qv' <<<"$completion_output" ||
  fail "native qv completion"
grep -Fq 'complete -o default -F _qvos_complete omarchy' <<<"$completion_output" ||
  fail "compatibility completion"

printf 'ok - qvOS Bash ownership is minimal, atomic, and preservation-safe\n'
