#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
source_root="$test_root/source"
test_home="$test_root/home"
restart_log="$test_root/restarts"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

install -d -m 0700 "$test_home"
install -D -m 0755 "$root/qvcore/config/refresh" \
  "$source_root/qvcore/config/refresh"
for owner in refresh-hypridle refresh-hyprlock refresh-hyprsunset refresh-swayosd; do
  install -D -m 0755 "$root/qvcore/config/$owner" \
    "$source_root/qvcore/config/$owner"
done
for config_path in \
  hypr/hyprlock.conf \
  hypr/hyprsunset.conf \
  swayosd/config.toml \
  swayosd/style.css; do
  install -D -m 0644 "$root/qvcore/config/files/$config_path" \
    "$source_root/qvcore/config/files/$config_path"
done
install -D -m 0644 "$root/qvcore/config/files/hypr/hypridle.conf" \
  "$source_root/qvcore/config/files/hypr/hypridle.conf"
for service in hypridle hyprsunset swayosd; do
  install -D -m 0755 /dev/stdin \
    "$source_root/qvcore/desktop/restart/$service" <<'RESTART'
#!/bin/bash
printf '%s\n' "${0##*/}" >>"$QVOS_TEST_RESTART_LOG"
RESTART
done

run_owner() {
  HOME="$test_home" \
    QVOS_PATH="$source_root" \
    QVOS_TEST_RESTART_LOG="$restart_log" \
    "$@"
}

run_owner "$source_root/qvcore/config/refresh-hypridle"
run_owner "$source_root/qvcore/config/refresh-hyprlock"
run_owner "$source_root/qvcore/config/refresh-hyprsunset"
run_owner "$source_root/qvcore/config/refresh-swayosd"

for config_path in \
  hypr/hyprlock.conf \
  hypr/hyprsunset.conf \
  swayosd/config.toml \
  swayosd/style.css; do
  cmp -s "$root/qvcore/config/files/$config_path" "$test_home/.config/$config_path" ||
    fail "refreshed config mismatch: $config_path"
done
cmp -s \
  "$root/qvcore/config/files/hypr/hypridle.conf" \
  "$test_home/.config/hypr/hypridle.conf" ||
  fail "refreshed specialized Hypridle config mismatch"
[[ $(<"$restart_log") == $'hypridle\nhyprsunset\nswayosd' ]] ||
  fail "refresh restart order"
pass "native config refresh owners restore exact defaults before restart"

restart_count=$(wc -l <"$restart_log")
for owner in refresh-hypridle refresh-hyprlock refresh-hyprsunset refresh-swayosd; do
  if run_owner "$source_root/qvcore/config/$owner" unexpected \
    >/dev/null 2>&1; then
    fail "$owner accepted unexpected arguments"
  fi
done
[[ $(wc -l <"$restart_log") == "$restart_count" ]] ||
  fail "invalid refresh restarted a desktop component"
pass "config refresh owners reject unexpected input before mutation"

template_path=systemd/user/app-example@autostart.service.d/restart.conf
install -D -m 0644 /dev/stdin "$source_root/qvcore/config/files/$template_path" <<'CONFIG'
[Service]
Restart=always
CONFIG
run_owner "$source_root/qvcore/config/refresh" "$template_path"
cmp -s \
  "$source_root/qvcore/config/files/$template_path" \
  "$test_home/.config/$template_path" ||
  fail "systemd template config refresh"
pass "config refresh accepts bounded systemd template paths"

printf 'personal lock screen\n' >"$test_home/.config/hypr/hyprlock.conf"
run_owner "$source_root/qvcore/config/refresh" hypr/hyprlock.conf
backup_root="$test_home/.local/state/qvos/config-backups/refresh"
mapfile -t lock_backups < <(
  for path_file in "$backup_root"/*/path; do
    [[ -f $path_file ]] || continue
    [[ $(<"$path_file") == "hypr/hyprlock.conf" ]] || continue
    printf '%s/value\n' "${path_file%/path}"
  done
)
((${#lock_backups[@]} == 1)) || fail "one private config refresh backup"
[[ $(<"${lock_backups[0]}") == "personal lock screen" ]] ||
  fail "private config refresh backup content"
[[ $(stat -c '%a' "$test_home/.local/state/qvos") == "700" &&
  $(stat -c '%a' "$test_home/.local/state/qvos/config-backups") == "700" &&
  $(stat -c '%a' "$backup_root") == "700" &&
  $(stat -c '%a' "${lock_backups[0]%/value}") == "700" &&
  $(stat -c '%a' "${lock_backups[0]%/value}/path") == "600" &&
  $(stat -c '%a' "$backup_root/.lock") == "600" ]] ||
  fail "private config refresh backup permissions"
if find "$test_home/.config" -name '*.bak.*' -print -quit | grep -q .; then
  fail "config refresh backup polluted active configuration"
fi
pass "config refresh preserves recovery values in private qvOS state"

concurrent_path=qvos/concurrent.conf
install -D -m 0644 /dev/stdin \
  "$source_root/qvcore/config/files/$concurrent_path" <<'CONFIG'
native concurrent config
CONFIG
install -D -m 0644 /dev/stdin \
  "$test_home/.config/$concurrent_path" <<'CONFIG'
personal concurrent config
CONFIG
run_owner "$source_root/qvcore/config/refresh" "$concurrent_path" &
first_refresh=$!
run_owner "$source_root/qvcore/config/refresh" "$concurrent_path" &
second_refresh=$!
wait "$first_refresh"
wait "$second_refresh"
mapfile -t concurrent_backups < <(
  for path_file in "$backup_root"/*/path; do
    [[ -f $path_file ]] || continue
    [[ $(<"$path_file") == "$concurrent_path" ]] || continue
    printf '%s/value\n' "${path_file%/path}"
  done
)
((${#concurrent_backups[@]} == 1)) ||
  fail "concurrent refresh created duplicate recovery values"
[[ $(<"${concurrent_backups[0]}") == "personal concurrent config" ]] ||
  fail "concurrent config refresh backup content"
cmp -s "$source_root/qvcore/config/files/$concurrent_path" \
  "$test_home/.config/$concurrent_path" ||
  fail "concurrent config refresh result"
pass "config refresh serializes concurrent publication"

unsafe_home="$test_root/unsafe-home"
outside_state="$test_root/outside-state"
install -d \
  "$unsafe_home/.config/qvos" \
  "$unsafe_home/.local/state" \
  "$outside_state"
printf 'preserve unsafe target\n' >"$unsafe_home/.config/qvos/concurrent.conf"
ln -s "$outside_state" "$unsafe_home/.local/state/qvos"
if HOME="$unsafe_home" QVOS_PATH="$source_root" \
  "$source_root/qvcore/config/refresh" "$concurrent_path" \
  >/dev/null 2>&1; then
  fail "linked private state root accepted"
fi
[[ $(<"$unsafe_home/.config/qvos/concurrent.conf") == \
  "preserve unsafe target" ]] || fail "unsafe state changed active config"
[[ -z $(find "$outside_state" -mindepth 1 -print -quit) ]] ||
  fail "unsafe state link received refresh data"
pass "config refresh rejects linked private state before mutation"

printf 'preserve before failed preflight\n' \
  >"$test_home/.config/swayosd/config.toml"
rm "$source_root/qvcore/config/files/swayosd/style.css"
if run_owner "$source_root/qvcore/config/refresh-swayosd" \
  >/dev/null 2>&1; then
  fail "incomplete SwayOSD source accepted"
fi
[[ $(<"$test_home/.config/swayosd/config.toml") == \
  "preserve before failed preflight" ]] ||
  fail "failed SwayOSD preflight changed an existing config"
[[ $(wc -l <"$restart_log") == "$restart_count" ]] ||
  fail "failed SwayOSD preflight restarted the service"
pass "multi-file SwayOSD refresh preflights the complete source"
