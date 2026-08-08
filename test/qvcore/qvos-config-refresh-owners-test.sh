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

install -D -m 0755 "$root/qvcore/config/refresh" \
  "$source_root/qvcore/config/refresh"
for owner in refresh-hypridle refresh-hyprlock refresh-hyprsunset refresh-swayosd; do
  install -D -m 0755 "$root/qvcore/config/$owner" \
    "$source_root/qvcore/config/$owner"
done
for config_path in \
  hypr/hypridle.conf \
  hypr/hyprlock.conf \
  hypr/hyprsunset.conf \
  swayosd/config.toml \
  swayosd/style.css; do
  install -D -m 0644 "$root/config/$config_path" \
    "$source_root/config/$config_path"
done
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
  hypr/hypridle.conf \
  hypr/hyprlock.conf \
  hypr/hyprsunset.conf \
  swayosd/config.toml \
  swayosd/style.css; do
  cmp -s "$root/config/$config_path" "$test_home/.config/$config_path" ||
    fail "refreshed config mismatch: $config_path"
done
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
install -D -m 0644 /dev/stdin "$source_root/config/$template_path" <<'CONFIG'
[Service]
Restart=always
CONFIG
run_owner "$source_root/qvcore/config/refresh" "$template_path"
cmp -s \
  "$source_root/config/$template_path" \
  "$test_home/.config/$template_path" ||
  fail "systemd template config refresh"
pass "config refresh accepts bounded systemd template paths"

printf 'preserve before failed preflight\n' \
  >"$test_home/.config/swayosd/config.toml"
rm "$source_root/config/swayosd/style.css"
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
