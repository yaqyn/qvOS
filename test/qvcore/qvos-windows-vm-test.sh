#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_source="$test_root/source"
test_bin="$test_root/bin"
package_log="$test_root/packages.log"
docker_log="$test_root/docker.log"
launch_log="$test_root/launch.log"
post_launch_log="$test_root/post-launch.log"
session_launch_log="$test_root/session-launch.log"
rdp_args_log="$test_root/rdp-args.log"
rdp_password_log="$test_root/rdp-password.log"
image_state="$test_root/windows-image"
container_state="$test_root/windows-container"
legacy_container_state="$test_root/legacy-windows-container"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_home" \
  "$test_source/qvcore/windows" \
  "$test_source/applications/icons" \
  "$test_bin"
touch "$test_root/kvm"
printf 'icon fixture\n' >"$test_source/applications/icons/windows.png"
install -m 0644 "$root/qvcore/windows/lib" "$test_source/qvcore/windows/lib"
install -m 0755 "$root/qvcore/windows/reconcile" "$test_source/qvcore/windows/reconcile"

install -m 0755 /dev/stdin "$test_bin/package-owner" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_PACKAGE_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/docker-compose" <<'SCRIPT'
#!/bin/bash
printf 'compose %s\n' "$*" >>"$QVOS_TEST_DOCKER_LOG"
if [[ ${1:-} == "-f" && ${3:-} == "up" && ${QVOS_TEST_COMPOSE_TOUCH_CONTAINER:-false} == "true" ]]; then
  touch "$QVOS_TEST_WINDOWS_CONTAINER_STATE"
elif [[ ${1:-} == "-f" && ${3:-} == "down" && -e $QVOS_TEST_WINDOWS_CONTAINER_STATE ]]; then
  unlink -- "$QVOS_TEST_WINDOWS_CONTAINER_STATE"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/docker" <<'SCRIPT'
#!/bin/bash
printf 'docker %s\n' "$*" >>"$QVOS_TEST_DOCKER_LOG"
case $* in
"info")
  [[ ${QVOS_TEST_DOCKER_UNAVAILABLE:-false} != "true" ]]
  ;;
"container inspect qvos-windows")
  [[ -e $QVOS_TEST_WINDOWS_CONTAINER_STATE ]]
  ;;
"container inspect omarchy-windows")
  [[ -e $QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE ]]
  ;;
"rename omarchy-windows qvos-windows")
  [[ -e $QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE ]] || exit 1
  mv -- "$QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE" "$QVOS_TEST_WINDOWS_CONTAINER_STATE"
  ;;
"rename qvos-windows omarchy-windows")
  [[ -e $QVOS_TEST_WINDOWS_CONTAINER_STATE ]] || exit 1
  mv -- "$QVOS_TEST_WINDOWS_CONTAINER_STATE" "$QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE"
  exit 0
  ;;
"image inspect dockurr/windows")
  [[ -e $QVOS_TEST_WINDOWS_IMAGE_STATE ]]
  ;;
"inspect --format {{.State.Status}} qvos-windows")
  [[ -e $QVOS_TEST_WINDOWS_CONTAINER_STATE ]] || exit 1
  printf 'running\n'
  ;;
"inspect qvos-windows")
  [[ -e $QVOS_TEST_WINDOWS_CONTAINER_STATE ]]
  ;;
"image rm dockurr/windows")
  [[ ! -e $QVOS_TEST_WINDOWS_IMAGE_STATE ]] || unlink "$QVOS_TEST_WINDOWS_IMAGE_STATE"
  ;;
"logs --follow qvos-windows")
  printf 'Downloading Windows installer...\n'
  printf 'Windows started successfully\n'
  ;;
"logs --tail 200 qvos-windows")
  printf 'Windows started successfully\n'
  ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$test_bin/timedatectl" <<'SCRIPT'
#!/bin/bash
printf 'Africa/Cairo\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/windows-launch-owner" <<'SCRIPT'
#!/bin/bash
printf 'launched\n' >"$QVOS_TEST_WINDOWS_POST_LAUNCH_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/systemd-run" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_WINDOWS_SESSION_LAUNCH_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/uwsm" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-windows-vm" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/xfreerdp3" <<'SCRIPT'
#!/bin/bash
IFS= read -r password || true
printf '%s\n' "$password" >"$QVOS_TEST_WINDOWS_RDP_PASSWORD_LOG"
printf '%s\n' "$@" >"$QVOS_TEST_WINDOWS_RDP_ARGS_LOG"
exit "${QVOS_TEST_WINDOWS_RDP_STATUS:-0}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf '[{"focused":true,"scale":1.5}]\n'
SCRIPT
install -m 0755 /dev/stdin "$test_bin/notify-send" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/nc" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sleep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
run_windows() {
  HOME="$test_home" \
    QVOS_PATH="$test_source" \
    PATH="$test_bin:/usr/bin" \
    QVOS_WINDOWS_KVM_PATH="$test_root/kvm" \
    QVOS_WINDOWS_PACKAGE_OWNER="$test_bin/package-owner" \
    QVOS_WINDOWS_LAUNCH_OWNER="$test_bin/windows-launch-owner" \
    QVOS_WINDOWS_TOTAL_RAM_GB=16 \
    QVOS_WINDOWS_TOTAL_CORES=8 \
    QVOS_WINDOWS_AVAILABLE_GB=200 \
    QVOS_TEST_PACKAGE_LOG="$package_log" \
    QVOS_TEST_DOCKER_LOG="$docker_log" \
    QVOS_TEST_WINDOWS_POST_LAUNCH_LOG="$post_launch_log" \
    QVOS_TEST_WINDOWS_IMAGE_STATE="$image_state" \
    QVOS_TEST_WINDOWS_CONTAINER_STATE="$container_state" \
    QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE="$legacy_container_state" \
    "$root/qvcore/windows/manage" "$@"
}

run_windows_live_owner() {
  HOME="$test_home" \
    QVOS_PATH="$test_source" \
    PATH="$test_bin:/usr/bin" \
    QVOS_WINDOWS_KVM_PATH="$test_root/kvm" \
    QVOS_WINDOWS_PACKAGE_OWNER="$test_bin/package-owner" \
    QVOS_WINDOWS_TOTAL_RAM_GB=16 \
    QVOS_WINDOWS_TOTAL_CORES=8 \
    QVOS_WINDOWS_AVAILABLE_GB=200 \
    QVOS_TEST_PACKAGE_LOG="$package_log" \
    QVOS_TEST_DOCKER_LOG="$docker_log" \
    QVOS_TEST_WINDOWS_IMAGE_STATE="$image_state" \
    QVOS_TEST_WINDOWS_CONTAINER_STATE="$container_state" \
    QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE="$legacy_container_state" \
    QVOS_TEST_WINDOWS_SESSION_LAUNCH_LOG="$session_launch_log" \
    "$root/qvcore/windows/manage" "$@"
}

run_windows_command() {
  HOME="$test_home" \
    QVOS_PATH="$test_source" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_DOCKER_LOG="$docker_log" \
    QVOS_TEST_WINDOWS_CONTAINER_STATE="$container_state" \
    QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE="$legacy_container_state" \
    QVOS_TEST_WINDOWS_RDP_ARGS_LOG="$rdp_args_log" \
    QVOS_TEST_WINDOWS_RDP_PASSWORD_LOG="$rdp_password_log" \
    QVOS_TEST_WINDOWS_RDP_STATUS="${QVOS_TEST_WINDOWS_RDP_STATUS:-0}" \
    QVOS_TEST_COMPOSE_TOUCH_CONTAINER=true \
    "$root/qvcore/windows/command" "$@"
}

run_windows_reconcile() {
  local reconcile_home=$1
  shift

  HOME="$reconcile_home" \
    QVOS_PATH="$test_source" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_DOCKER_LOG="$docker_log" \
    QVOS_TEST_DOCKER_UNAVAILABLE="${QVOS_TEST_DOCKER_UNAVAILABLE:-false}" \
    QVOS_TEST_WINDOWS_CONTAINER_STATE="$container_state" \
    QVOS_TEST_WINDOWS_LEGACY_CONTAINER_STATE="$legacy_container_state" \
    "$root/qvcore/windows/reconcile" "$@"
}

prepare_legacy_home() {
  local reconcile_home=$1
  local source_compose=$2

  install -d -m 0700 \
    "$reconcile_home/.config/windows" \
    "$reconcile_home/.windows" \
    "$reconcile_home/Windows"
  install -d -m 0755 "$reconcile_home/.local/share/applications"
  sed \
    -e "s|$test_home|$reconcile_home|g" \
    -e 's/container_name: qvos-windows/container_name: omarchy-windows/' \
    "$source_compose" >"$reconcile_home/.config/windows/docker-compose.yml"
  chmod 0600 "$reconcile_home/.config/windows/docker-compose.yml"
  install -m 0644 /dev/stdin \
    "$reconcile_home/.local/share/applications/windows-vm.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Windows
Exec=uwsm app -- omarchy-windows-vm launch
Type=Application
DESKTOP
}

schema=$(run_windows install --qvos-form)
jq -e '
  .title == "Configure Windows VM" and
  [.fields[].key] == ["ram", "cpus", "disk", "username", "password"] and
  (.fields[] | select(.key == "cpus") | .kind) == "number" and
  (.fields[] | select(.key == "cpus") | .min) == 1 and
  (.fields[] | select(.key == "password") | .kind) == "password"
' <<<"$schema" >/dev/null || fail "Windows owner form schema"
printf 'ok - Windows resources and credentials use the shared owner-form contract\n'

form_file="$test_root/form.json"
install -m 0600 /dev/stdin "$form_file" <<'JSON'
{"ram":"4G","cpus":"2","disk":"64G","username":"docker","password":"private-pass"}
JSON
export QVOS_ACTION_FORM_VALUES="$form_file"

rollback_state="$test_root/rollback-first"
run_windows install --qvos-rollback-check
run_windows install --qvos-rollback-snapshot "$rollback_state"
install_output=$(run_windows install)
run_windows install --qvos-rollback-seal "$rollback_state"
run_windows install --qvos-post-success
[[ $(<"$post_launch_log") == "launched" ]] ||
  fail "Windows verified-install launch owner"
[[ ! -s $docker_log ]] || fail "Windows Install started the VM download"
session_output=$(run_windows_live_owner install --qvos-post-success)
grep -Fq 'Downloading Windows installer' <<<"$session_output" ||
  fail "Windows first-launch download output"
grep -Fq 'Windows started successfully' <<<"$session_output" ||
  fail "Windows first-launch ready boundary"
grep -Fqx -- \
  '--user --collect --quiet --description=qvOS Windows VM session -- uwsm app -- qv-windows-vm launch' \
  "$session_launch_log" || fail "Windows ready-session handoff"
[[ $(stat -c '%a' "$test_home/.config/windows/docker-compose.yml") == "600" ]] ||
  fail "Windows Compose credentials are not private"
grep -Fq 'PASSWORD: "private-pass"' "$test_home/.config/windows/docker-compose.yml" ||
  fail "Windows Compose credentials"
grep -Fqx 'freerdp openbsd-netcat' "$package_log" ||
  fail "Windows package delegation"
[[ $install_output != *private-pass* ]] || fail "Windows Install printed credentials"
post_rollback_state="$test_root/post-rollback"
run_windows install --qvos-post-success-rollback-check
run_windows install --qvos-post-success-rollback-snapshot "$post_rollback_state"
install -d "$test_home/.windows/tmp"
printf 'partial image\n' >"$test_home/.windows/tmp/win11x64.iso"
touch "$image_state" "$container_state"
run_windows install --qvos-post-success-rollback-seal "$post_rollback_state"
run_windows install --qvos-post-success-rollback-restore "$post_rollback_state"
[[ ! -e $image_state && ! -e $container_state ]] ||
  fail "Windows first-launch Stop retained its container image"
if find "$test_home/.windows" -mindepth 1 -print -quit | grep -q .; then
  fail "Windows first-launch Stop retained partial VM data"
fi
[[ $(run_windows install --qvos-post-success-cancel-status "$post_rollback_state") == "target-not-detected" ]] ||
  fail "Windows first-launch Stop state"
printf 'ok - Windows first launch streams through exact Stop cleanup\n'
run_windows install --qvos-rollback-restore "$rollback_state"
[[ ! -e $test_home/.config/windows/docker-compose.yml ]] ||
  fail "Windows Stop retained new configuration"
[[ ! -e $test_home/.windows ]] || fail "Windows Stop retained a new virtual disk directory"
[[ ! -e $test_home/Windows ]] || fail "Windows Stop retained a new shared directory"
printf 'ok - Windows Install is private, deferred, and exactly reversible\n'

install -d "$test_home/.windows" "$test_home/Windows"
printf 'existing disk\n' >"$test_home/.windows/disk.img"
printf 'personal file\n' >"$test_home/Windows/personal.txt"
rollback_state="$test_root/rollback-existing"
run_windows install --qvos-rollback-snapshot "$rollback_state"
run_windows install >/dev/null
run_windows install --qvos-rollback-seal "$rollback_state"
run_windows install --qvos-rollback-restore "$rollback_state"
[[ -f $test_home/.windows/disk.img ]] || fail "Windows Stop removed a pre-existing virtual disk"
[[ -f $test_home/Windows/personal.txt ]] || fail "Windows Stop removed shared personal files"
printf 'ok - Windows Stop preserves pre-existing VM and shared data\n'

run_windows install >/dev/null
keep_options=$(run_windows uninstall --list)
[[ $keep_options == $'Keep Virtual Disk\nDelete Virtual Disk' ]] ||
  fail "Windows uninstall scopes"
run_windows uninstall -- "Keep Virtual Disk" >/dev/null
[[ -f $test_home/.windows/disk.img ]] || fail "safe Windows uninstall removed the virtual disk"
[[ -f $test_home/Windows/personal.txt ]] || fail "safe Windows uninstall removed shared files"
[[ ! -e $test_home/.config/windows/docker-compose.yml ]] ||
  fail "safe Windows uninstall retained configuration"

run_windows install >/dev/null
run_windows uninstall -- "Delete Virtual Disk" >/dev/null
[[ ! -e $test_home/.windows ]] || fail "destructive Windows uninstall retained the virtual disk"
[[ -f $test_home/Windows/personal.txt ]] || fail "destructive Windows uninstall removed shared files"
grep -Fq 'compose -f ' "$docker_log" || fail "Windows uninstall did not stop its container"
printf 'ok - Windows uninstall defaults safe and deletes only the explicitly selected disk\n'

grep -Fq 'windows|file|.config/windows/docker-compose.yml|tui|true|tui|false|qvcore/windows/manage install|qvcore/windows/manage uninstall' \
  "$root/qvcore/menu/software-actions.psv" || fail "Windows shared TUI route"
grep -Fq 'windows|install|owner-json-v1' "$root/qvcore/tui/action/forms.psv" ||
  fail "Windows form catalog"
grep -Fq 'windows|install|owner-state-v1' "$root/qvcore/tui/action/rollbacks.psv" ||
  fail "Windows rollback catalog"
grep -Fq 'windows|install|launch|owner-v1' "$root/qvcore/tui/action/post-actions.psv" ||
  fail "Windows post-success action catalog"
[[ -x $root/qvcore/tui/action/post-run ]] ||
  fail "Windows post-success source runner is not executable"
grep -Fq 'windows|uninstall|Remove Windows|action|' "$root/qvcore/tui/action/choices.psv" ||
  fail "Windows removal choice catalog"
if rg -i '\b(super|ctrl|alt|shift|f[0-9]+)\b' "$root/qvcore/tui/success-guidance.psv" >/dev/null; then
  fail "success guidance depends on key bindings"
fi
printf 'ok - every Windows lifecycle stage stays inside shared TUI contracts\n'

install -d "$test_home/.local/lib/qvos/tui/action"
install -m 0755 "$root/qvcore/windows/command" "$test_source/qvcore/windows/command"
install -m 0755 "$root/qvcore/windows/launch" "$test_source/qvcore/windows/launch"
install -m 0755 /dev/stdin "$test_home/.local/lib/qvos/tui/action/launch" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_WINDOWS_LAUNCH_LOG"
SCRIPT
for adapter in qv-windows-vm omarchy-windows-vm; do
  for operation in install remove; do
    HOME="$test_home" \
      QVOS_PATH="$test_source" \
      QVOS_TEST_WINDOWS_LAUNCH_LOG="$launch_log" \
      "$root/bin/$adapter" "$operation"
  done
done
[[ $(<"$launch_log") == $'windows\nwindows\nwindows\nwindows' ]] ||
  fail "direct Windows lifecycle commands bypassed the TUI"
printf 'ok - direct Install and Remove commands converge on the same Windows TUI\n'

(( $(wc -l <"$root/bin/qv-windows-vm") <= 12 )) ||
  fail "Windows native adapter contains implementation"
(( $(wc -l <"$root/bin/omarchy-windows-vm") <= 5 )) ||
  fail "Windows compatibility adapter contains implementation"
# shellcheck disable=SC2016
grep -Fqx 'exec "$QVOS_PATH/qvcore/windows/command" "$@"' "$root/bin/qv-windows-vm" ||
  fail "Windows native adapter is not direct"
# shellcheck disable=SC2016
grep -Fqx 'exec "$QVOS_PATH/qvcore/windows/command" "$@"' "$root/bin/omarchy-windows-vm" ||
  fail "Windows compatibility adapter is not direct"
rg -q '^# qv:summary=' "$root/bin/qv-windows-vm" ||
  fail "Windows native adapter lacks metadata"
if rg -q '^# (qv|omarchy):' "$root/bin/omarchy-windows-vm"; then
  fail "Windows compatibility adapter duplicates metadata"
fi
printf 'ok - the native and compatibility Windows commands share one unprivileged owner\n'

run_windows install >/dev/null
compose_file="$test_home/.config/windows/docker-compose.yml"
chmod 0644 "$compose_file"
: >"$docker_log"
launch_output=$(run_windows_command launch)
[[ $(stat -c '%a' "$compose_file") == "600" ]] ||
  fail "Windows launch did not repair private Compose permissions"
[[ ! -e $container_state ]] || fail "Windows launch did not auto-stop the VM"
[[ $(<"$rdp_password_log") == "private-pass" ]] ||
  fail "Windows launch did not send the credential over standard input"
grep -Fqx '/from-stdin:force' "$rdp_args_log" ||
  fail "Windows launch did not require standard-input credentials"
grep -Fqx '/u:docker' "$rdp_args_log" || fail "Windows launch omitted the user"
grep -Fqx '/f' "$rdp_args_log" || fail "Windows launch omitted fullscreen mode"
grep -Fqx '/scale:140' "$rdp_args_log" || fail "Windows launch omitted accessible display scaling"
if grep -Fq 'private-pass' "$rdp_args_log" || [[ $launch_output == *private-pass* ]]; then
  fail "Windows launch exposed its credential in arguments or output"
fi
grep -Fq 'compose -f ' "$docker_log" || fail "Windows launch did not use Compose"
printf 'ok - Windows launch keeps credentials out of argv and adapts display scaling\n'

: >"$docker_log"
run_windows_command launch --keep-alive >/dev/null
[[ -e $container_state ]] || fail "Windows keep-alive stopped the VM"
status_output=$(run_windows_command status)
grep -Fq 'Windows VM: running' <<<"$status_output" || fail "Windows runtime status"
run_windows_command stop >/dev/null
[[ ! -e $container_state ]] || fail "Windows stop retained the container"
printf 'ok - Windows keep-alive, status, and stop are explicit and accessible\n'

set +e
QVOS_TEST_WINDOWS_RDP_STATUS=42 run_windows_command launch >/dev/null 2>&1
rdp_status=$?
set -e
(( rdp_status == 42 )) || fail "Windows launch hid the RDP failure status"
[[ ! -e $container_state ]] || fail "Windows RDP failure retained the container"
printf 'ok - Windows launch preserves failures while still auto-stopping safely\n'

cp -- "$compose_file" "$test_root/safe-compose.yml"
sed -i 's/127\.0\.0\.1:8006:8006/0.0.0.0:8006:8006/' "$compose_file"
: >"$docker_log"
if run_windows_command launch >/dev/null 2>&1; then
  fail "Windows launch accepted a public Compose listener"
fi
[[ ! -s $docker_log ]] || fail "Windows launch invoked Docker for an unsafe Compose file"
cp -- "$test_root/safe-compose.yml" "$compose_file"
printf '    privileged: true\n' >>"$compose_file"
if run_windows_command status >/dev/null 2>&1; then
  fail "Windows status accepted an extended Compose service"
fi
cp -- "$test_root/safe-compose.yml" "$compose_file"
mv -- "$compose_file" "$test_root/real-compose.yml"
ln -s "$test_root/real-compose.yml" "$compose_file"
: >"$docker_log"
if run_windows_command launch >/dev/null 2>&1; then
  fail "Windows launch accepted a symlinked Compose file"
fi
[[ ! -s $docker_log ]] || fail "Windows launch invoked Docker for a symlinked Compose file"
unlink -- "$compose_file"
mv -- "$test_root/real-compose.yml" "$compose_file"
printf 'ok - Windows rejects public listeners, foreign structure, and symlinked config before Docker\n'

migration_home="$test_root/migration-home"
prepare_legacy_home "$migration_home" "$compose_file"
rm -f -- "$container_state" "$legacy_container_state"
touch "$legacy_container_state"
: >"$docker_log"
migration_output=$(run_windows_reconcile "$migration_home")
grep -Fq 'Migrated Windows VM internals to qvOS identity.' <<<"$migration_output" ||
  fail "Windows identity migration result"
[[ -e $container_state && ! -e $legacy_container_state ]] ||
  fail "Windows identity migration did not rename the existing container"
grep -Fqx '    container_name: qvos-windows' \
  "$migration_home/.config/windows/docker-compose.yml" ||
  fail "Windows identity migration did not publish native Compose state"
grep -Fqx 'Exec=uwsm app -- qv-windows-vm launch' \
  "$migration_home/.local/share/applications/windows-vm.desktop" ||
  fail "Windows identity migration did not publish the native launcher"
(( $(find "$migration_home" -type f -name '*.qvos-backup.*' | wc -l) == 2 )) ||
  fail "Windows identity migration backup set"
[[ -z $(run_windows_reconcile "$migration_home") ]] ||
  fail "Windows identity migration is not quiet when already converged"
run_windows_reconcile "$migration_home" --check
(( $(find "$migration_home" -type f -name '*.qvos-backup.*' | wc -l) == 2 )) ||
  fail "Windows identity migration is not idempotent"
printf 'ok - Windows identity migration preserves and renames exact existing state atomically\n'

deferred_home="$test_root/deferred-home"
prepare_legacy_home "$deferred_home" "$compose_file"
rm -f -- "$container_state" "$legacy_container_state"
touch "$legacy_container_state"
deferred_snapshot=$(
  stat -c '%n|%a|%i|%Y' \
    "$deferred_home/.config/windows/docker-compose.yml" \
    "$deferred_home/.local/share/applications/windows-vm.desktop"
  sha256sum \
    "$deferred_home/.config/windows/docker-compose.yml" \
    "$deferred_home/.local/share/applications/windows-vm.desktop"
)
set +e
deferred_output=$(QVOS_TEST_DOCKER_UNAVAILABLE=true \
  run_windows_reconcile "$deferred_home" 2>&1)
deferred_status=$?
set -e
(( deferred_status == 0 )) || fail "Windows unavailable-Docker migration status"
grep -Fq 'migration deferred until Docker is available' <<<"$deferred_output" ||
  fail "Windows unavailable-Docker migration diagnostic"
[[ $(
  stat -c '%n|%a|%i|%Y' \
    "$deferred_home/.config/windows/docker-compose.yml" \
    "$deferred_home/.local/share/applications/windows-vm.desktop"
  sha256sum \
    "$deferred_home/.config/windows/docker-compose.yml" \
    "$deferred_home/.local/share/applications/windows-vm.desktop"
) == "$deferred_snapshot" ]] ||
  fail "Windows unavailable-Docker migration changed file state"
grep -Fqx '    container_name: omarchy-windows' \
  "$deferred_home/.config/windows/docker-compose.yml" ||
  fail "Windows unavailable-Docker migration changed Compose state"
grep -Fqx 'Exec=uwsm app -- omarchy-windows-vm launch' \
  "$deferred_home/.local/share/applications/windows-vm.desktop" ||
  fail "Windows unavailable-Docker migration changed launcher state"
if find "$deferred_home" -type f -name '*.qvos-backup.*' -print -quit | grep -q .; then
  fail "Windows unavailable-Docker migration wrote a backup without changing state"
fi
printf 'ok - Windows identity migration defers without partial changes when Docker is unavailable\n'

conflict_home="$test_root/conflict-home"
prepare_legacy_home "$conflict_home" "$compose_file"
touch "$container_state" "$legacy_container_state"
if run_windows_reconcile "$conflict_home" >/dev/null 2>&1; then
  fail "Windows identity migration accepted conflicting containers"
fi
grep -Fqx '    container_name: omarchy-windows' \
  "$conflict_home/.config/windows/docker-compose.yml" ||
  fail "Windows container-conflict path changed Compose state"
grep -Fqx 'Exec=uwsm app -- omarchy-windows-vm launch' \
  "$conflict_home/.local/share/applications/windows-vm.desktop" ||
  fail "Windows container-conflict path changed launcher state"
if find "$conflict_home" -type f -name '*.qvos-backup.*' -print -quit | grep -q .; then
  fail "Windows container-conflict path wrote a backup"
fi
printf 'ok - Windows identity migration fails closed on container conflicts\n'
