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
image_state="$test_root/windows-image"
container_state="$test_root/windows-container"

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
  "$test_source/applications/icons" \
  "$test_bin"
touch "$test_root/kvm"
printf 'icon fixture\n' >"$test_source/applications/icons/windows.png"

install -m 0755 /dev/stdin "$test_bin/package-owner" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_PACKAGE_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/docker-compose" <<'SCRIPT'
#!/bin/bash
printf 'compose %s\n' "$*" >>"$QVOS_TEST_DOCKER_LOG"
if [[ ${1:-} == "-f" && ${3:-} == "down" && -e $QVOS_TEST_WINDOWS_CONTAINER_STATE ]]; then
  unlink "$QVOS_TEST_WINDOWS_CONTAINER_STATE"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/docker" <<'SCRIPT'
#!/bin/bash
printf 'docker %s\n' "$*" >>"$QVOS_TEST_DOCKER_LOG"
case $* in
"image inspect dockurr/windows")
  [[ -e $QVOS_TEST_WINDOWS_IMAGE_STATE ]]
  ;;
"inspect omarchy-windows")
  [[ -e $QVOS_TEST_WINDOWS_CONTAINER_STATE ]]
  ;;
"image rm dockurr/windows")
  [[ ! -e $QVOS_TEST_WINDOWS_IMAGE_STATE ]] || unlink "$QVOS_TEST_WINDOWS_IMAGE_STATE"
  ;;
"logs --follow omarchy-windows")
  printf 'Downloading Windows installer...\n'
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
install -m 0755 /dev/stdin "$test_bin/omarchy-windows-vm" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
run_windows() {
  HOME="$test_home" \
    OMARCHY_PATH="$test_source" \
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
    "$root/qv/windows/manage" "$@"
}

run_windows_live_owner() {
  HOME="$test_home" \
    OMARCHY_PATH="$test_source" \
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
    QVOS_TEST_WINDOWS_SESSION_LAUNCH_LOG="$session_launch_log" \
    "$root/qv/windows/manage" "$@"
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
  '--user --collect --quiet --description=qvOS Windows VM session -- uwsm app -- omarchy-windows-vm launch' \
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

grep -Fq 'windows|file|.config/windows/docker-compose.yml|tui|true|tui|false|qv/windows/manage install|qv/windows/manage uninstall' \
  "$root/qv/menu/software-actions.psv" || fail "Windows shared TUI route"
grep -Fq 'windows|install|owner-json-v1' "$root/qv/tui/action/forms.psv" ||
  fail "Windows form catalog"
grep -Fq 'windows|install|owner-state-v1' "$root/qv/tui/action/rollbacks.psv" ||
  fail "Windows rollback catalog"
grep -Fq 'windows|install|launch|owner-v1' "$root/qv/tui/action/post-actions.psv" ||
  fail "Windows post-success action catalog"
[[ -x $root/qv/tui/action/post-run ]] ||
  fail "Windows post-success source runner is not executable"
grep -Fq 'windows|uninstall|Remove Windows|action|' "$root/qv/tui/action/choices.psv" ||
  fail "Windows removal choice catalog"
if rg -i '\b(super|ctrl|alt|shift|f[0-9]+)\b' "$root/qv/tui/success-guidance.psv" >/dev/null; then
  fail "success guidance depends on key bindings"
fi
printf 'ok - every Windows lifecycle stage stays inside shared TUI contracts\n'

install -d \
  "$test_source/qv/windows" \
  "$test_home/.local/share/qvos/tui/action"
install -m 0755 "$root/qv/windows/launch" "$test_source/qv/windows/launch"
install -m 0755 /dev/stdin "$test_home/.local/share/qvos/tui/action/launch" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_WINDOWS_LAUNCH_LOG"
SCRIPT
for legacy_operation in install remove; do
  HOME="$test_home" \
    OMARCHY_PATH="$test_source" \
    QVOS_TEST_WINDOWS_LAUNCH_LOG="$launch_log" \
    "$root/bin/omarchy-windows-vm" "$legacy_operation"
done
[[ $(<"$launch_log") == $'windows\nwindows' ]] ||
  fail "direct Windows lifecycle commands bypassed the TUI"
printf 'ok - direct Install and Remove commands converge on the same Windows TUI\n'
