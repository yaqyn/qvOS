#!/bin/bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
systemctl_log="$test_root/systemctl.log"
owner="$root/qvcore/config/migrate-runtime-root"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_home/.config/Thunar" \
  "$test_home/.config/hypr" \
  "$test_home/.config/uwsm"
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
SCRIPT

install -m 0644 /dev/stdin "$test_home/.config/hypr/bindings.conf" <<'CONFIG'
exec = ~/.local/share/qvos/desktop/context/tool
exec = ~/.local/share/qvos/thunar/launch
exec = ~/.local/share/qvos/tmux/qvos-tmux
source = ~/.local/share/qvos/default/hypr/input.conf
bindeld = , XF86AudioMicMute, Mute microphone, exec, omarchy-audio-input-mute
bindeld = , XF86MonBrightnessUp, Brightness up, exec, omarchy-brightness-display +5%
bindeld = , XF86KbdBrightnessUp, Keyboard brightness up, exec, omarchy-brightness-keyboard up
bindeld = , XF86AudioRaiseVolume, Volume up, exec, omarchy-swayosd-client --output-volume raise
bindld = SUPER, XF86AudioMute, Switch audio output, exec, omarchy-audio-output-switch
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/hypr/hypridle.conf" <<'CONFIG'
exec = ~/.local/share/qvos/bin/omarchy-launch-screensaver
exec = ~/.local/share/qvos/bin/omarchy-system-suspend-if-safe --watch
CONFIG
install -m 0600 /dev/stdin "$test_home/.config/Thunar/uca.xml" <<'CONFIG'
<command>$HOME/.local/share/qvos/thunar/open-here</command>
CONFIG
install -m 0644 /dev/stdin "$test_home/.config/uwsm/env" <<'CONFIG'
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$OMARCHY_PATH/bin:$PATH:$HOME/.local/bin
export USER_SETTING=preserved

# qvOS PATH begin
export PATH="$HOME/.local/share/qvos/bin:$PATH"
# qvOS PATH end
CONFIG
HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  "$owner" >/dev/null

grep -Fq '.local/lib/qvos/desktop/' "$test_home/.config/hypr/bindings.conf" ||
  fail "desktop runtime migration"
grep -Fq '.local/lib/qvos/thunar/' "$test_home/.config/hypr/bindings.conf" ||
  fail "Thunar runtime migration"
grep -Fq '.local/lib/qvos/tmux/' "$test_home/.config/hypr/bindings.conf" ||
  fail "tmux runtime migration"
grep -Fq '.local/share/qvos/default/' "$test_home/.config/hypr/bindings.conf" ||
  fail "source-root path preservation"
for command in \
  qv-audio-input-mute \
  qv-audio-output-switch \
  qv-brightness-display \
  qv-brightness-keyboard \
  qv-swayosd-client; do
  grep -Fq "$command" "$test_home/.config/hypr/bindings.conf" ||
    fail "promoted desktop control was not migrated: $command"
done
if rg -q 'omarchy-(audio|brightness|swayosd)-' "$test_home/.config/hypr/bindings.conf"; then
  fail "desktop control compatibility route remains after migration"
fi
grep -Fq '.local/lib/qvos/bin/omarchy-launch-screensaver' \
  "$test_home/.config/hypr/hypridle.conf" ||
  fail "screensaver runtime migration"
grep -Fq '.local/lib/qvos/bin/omarchy-system-suspend-if-safe' \
  "$test_home/.config/hypr/hypridle.conf" ||
  fail "suspend runtime migration"
grep -Fq '.local/lib/qvos/thunar/open-here' \
  "$test_home/.config/Thunar/uca.xml" ||
  fail "Thunar action runtime migration"
grep -Fqx 'export QVOS_PATH=$HOME/.local/share/qvos' \
  "$test_home/.config/uwsm/env" ||
  fail "native source environment"
grep -Fqx 'export PATH=$QVOS_PATH/bin:$PATH:$HOME/.local/bin' \
  "$test_home/.config/uwsm/env" ||
  fail "native source path environment"
grep -Fqx 'export USER_SETTING=preserved' "$test_home/.config/uwsm/env" ||
  fail "custom environment preservation"
if grep -Fq '# qvOS PATH begin' "$test_home/.config/uwsm/env"; then
  fail "duplicate source path block cleanup"
fi
[[ $(find "$test_home/.config" -type f -name '*.bak.*' | wc -l) == "4" ]] ||
  fail "changed config backup count"
[[ $(<"$systemctl_log") == "--user daemon-reload" ]] ||
  fail "user service reload"

state_before=$(find "$test_home/.config" -type f -printf '%P|%m|%i|%T@\n' | sort)
HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  "$owner" >/dev/null
[[ $(find "$test_home/.config" -type f -printf '%P|%m|%i|%T@\n' | sort) == \
  "$state_before" ]] ||
  fail "idempotent config migration"
[[ $(wc -l <"$systemctl_log") == "1" ]] ||
  fail "idempotent service reload"

unsafe_home="$test_root/unsafe-home"
external_config="$test_root/external-bindings"
install -d "$unsafe_home/.config/hypr"
printf 'foreign\n' >"$external_config"
ln -s "$external_config" "$unsafe_home/.config/hypr/bindings.conf"
if HOME="$unsafe_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  "$owner" >/dev/null 2>&1; then
  fail "symbolic-link config accepted"
fi
[[ $(<"$external_config") == "foreign" ]] ||
  fail "symbolic-link config preservation"

printf 'ok - source and runtime config roots migrate once without losing user state\n'
