#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
systemctl_log="$test_root/systemctl.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_home" "$test_bin"
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
case $* in
"--user show-environment")
  printf 'HOME=%s\n' "$HOME"
  ;;
"--user daemon-reload")
  printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
  ;;
"--user is-active --quiet elephant.service" | \
"--user is-active --quiet app-walker@autostart.service")
  exit 0
  ;;
"--user restart elephant.service" | \
"--user restart app-walker@autostart.service")
  printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
  ;;
*) exit 2 ;;
esac
SCRIPT

config_paths=(
  autostart/walker.desktop
  elephant/calc.toml
  elephant/desktopapplications.toml
  systemd/user/app-walker@autostart.service.d/restart.conf
  walker/config.toml
)
for config_path in "${config_paths[@]}"; do
  target="$test_home/.config/$config_path"
  install -D -m 0644 /dev/stdin "$target" <<EOF
custom $config_path
EOF
done

HOME="$test_home" \
  QVOS_PATH="$root" \
  OMARCHY_PATH="$test_root/stale-source" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/bin/qv-refresh-walker"

for config_path in "${config_paths[@]}"; do
  target="$test_home/.config/$config_path"
  mapfile -t backups < <(
    find "${target%/*}" -maxdepth 1 -type f -name "${target##*/}.bak.*" -print
  )
  ((${#backups[@]} == 1)) || fail "one Walker backup: $config_path"
  grep -Fqx "custom $config_path" "${backups[0]}" ||
    fail "Walker backup content: $config_path"
  if [[ $config_path != "walker/config.toml" ]]; then
    cmp -s "$root/config/$config_path" "$target" ||
      fail "restored Walker config: $config_path"
  fi
done
grep -Fq 'theme = "qvos-menu"' "$test_home/.config/walker/config.toml" ||
  fail "reconciled Walker theme"
grep -Fq '[providers.sets.qvos-menu]' "$test_home/.config/walker/config.toml" ||
  fail "reconciled Walker provider set"
HOME="$test_home" QVOS_PATH="$root" PATH="$test_bin:/usr/bin" \
  "$root/qvcore/menu/install" --status || fail "refreshed menu status"
expected_systemctl=$'--user daemon-reload\n--user restart elephant.service\n--user restart app-walker@autostart.service'
[[ $(<"$systemctl_log") == "$expected_systemctl" ]] ||
  fail "single Walker reconciliation reload"
printf 'ok - Walker refresh preflights, backs up, restores, and reconciles once\n'

incomplete="$test_root/incomplete"
incomplete_home="$test_root/incomplete-home"
install -d \
  "$incomplete/qvcore" \
  "$incomplete/config/autostart" \
  "$incomplete/config/elephant" \
  "$incomplete/config/systemd/user/app-walker@autostart.service.d" \
  "$incomplete/config/walker" \
  "$incomplete_home/.config/walker"
ln -s "$root/qvcore/menu" "$incomplete/qvcore/menu"
ln -s "$root/qvcore/config" "$incomplete/qvcore/config"
ln -s "$root/qvcore/tui" "$incomplete/qvcore/tui"
ln -s "$root/default" "$incomplete/default"
for config_path in \
  autostart/walker.desktop \
  elephant/desktopapplications.toml \
  systemd/user/app-walker@autostart.service.d/restart.conf \
  walker/config.toml; do
  install -D -m 0644 "$root/config/$config_path" "$incomplete/config/$config_path"
done
printf 'preserve me\n' >"$incomplete_home/.config/walker/config.toml"
set +e
incomplete_output=$(
  HOME="$incomplete_home" QVOS_PATH="$incomplete" PATH="$test_bin:/usr/bin" \
    "$root/qvcore/menu/refresh-walker" 2>&1
)
incomplete_status=$?
set -e
((incomplete_status == 1)) || fail "incomplete Walker preflight status"
grep -Fq 'Missing qvOS menu source:' <<<"$incomplete_output" ||
  fail "incomplete Walker preflight message"
grep -Fqx 'preserve me' "$incomplete_home/.config/walker/config.toml" ||
  fail "incomplete Walker preflight preservation"
if find "$incomplete_home/.config" -name '*.bak.*' -print -quit | grep -q .; then
  fail "incomplete Walker preflight created a backup"
fi
printf 'ok - incomplete Walker sources fail before user configuration changes\n'

adapter_fixture="$test_root/adapter-fixture"
adapter_log="$test_root/adapter.log"
install -d "$adapter_fixture/qvcore/menu"
install -m 0755 /dev/stdin "$adapter_fixture/qvcore/menu/refresh-walker" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_ADAPTER_LOG"
SCRIPT
for adapter in qv-refresh-walker omarchy-refresh-walker; do
  QVOS_PATH="$adapter_fixture" QVOS_TEST_ADAPTER_LOG="$adapter_log" \
    "$root/bin/$adapter" "two words"
done
[[ $(<"$adapter_log") == $'two words\ntwo words' ]] ||
  fail "Walker adapter argument preservation"
printf 'ok - native and compatibility Walker commands share one owner\n'
