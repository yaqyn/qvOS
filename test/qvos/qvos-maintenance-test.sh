#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
source_root="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
state="$test_root/state"
installed="$state/installed"
action_log="$state/actions.log"
pacman_db="$state/pacman"
pacman_log="$state/pacman.log"
proc_root="$state/proc"
sys_root="$state/sys"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$source_root/bin" \
  "$source_root/qv/config/files/hypr/qv" \
  "$source_root/qv/install/packaging" \
  "$source_root/qv/maintenance" \
  "$source_root/qv/shell" \
  "$test_home/.config/hypr/qv" \
  "$test_home/.local/bin" \
  "$test_home/.local/share/qvos/maintenance" \
  "$test_bin" \
  "$state/damaged" \
  "$state/mutable-dirs" \
  "$state/missing-files" \
  "$state/unverified" \
  "$pacman_db" \
  "$proc_root" \
  "$sys_root"

install -m 0755 \
  "$root/qv/maintenance/qvos-repair" \
  "$source_root/qv/maintenance/qvos-repair"
install -m 0755 \
  "$root/qv/maintenance/qv" \
  "$source_root/qv/maintenance/qv"
install -m 0644 \
  "$root/qv/maintenance/essential-packages" \
  "$source_root/qv/maintenance/essential-packages"
install -m 0755 \
  "$root/qv/config/refresh" \
  "$source_root/qv/config/refresh"
install -m 0755 \
  "$root/qv/shell/install" \
  "$source_root/qv/shell/install"
install -m 0755 \
  "$root/qv/shell/status" \
  "$source_root/qv/shell/status"
install -m 0755 \
  "$root/bin/omarchy-qvos-health" \
  "$source_root/bin/omarchy-qvos-health"
install -m 0755 \
  "$root/bin/omarchy-qvos-repair" \
  "$source_root/bin/omarchy-qvos-repair"

install -m 0644 /dev/stdin \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" <<'CONFIG'
misc {
  allow_session_lock_restore = true
}
CONFIG
install -m 0644 /dev/stdin \
  "$source_root/qv/config/files/hypr/qv/windows.conf" <<'CONFIG'
windowrule = float on, match:class ^test$
CONFIG
cp -a \
  "$source_root/qv/config/files/hypr/qv/." \
  "$test_home/.config/hypr/qv/"
printf 'source = ~/.config/hypr/qv/looknfeel.conf\n' \
  >"$test_home/.config/hypr/hyprland.conf"

install -m 0644 /dev/stdin \
  "$source_root/qv/install/packaging/base.packages" <<'PACKAGES'
alacritty
chromium
hyprland
hyprlock
PACKAGES
install -m 0755 /dev/stdin \
  "$source_root/qv/install/desktop-status" <<'SCRIPT'
#!/bin/bash
if [[ -e $QVOS_TEST_STATE/runtime-drift ]]; then
  echo "test runtime bytes or modes differ"
  exit 1
fi
SCRIPT
install -m 0644 /dev/stdin \
  "$source_root/qv/install/desktop" <<'SCRIPT'
# shellcheck shell=bash
rm -f "$QVOS_TEST_STATE/runtime-drift"
install -D -m 0644 \
  "$OMARCHY_PATH/qv/maintenance/essential-packages" \
  "$HOME/.local/share/qvos/maintenance/essential-packages"
install -D -m 0755 \
  "$OMARCHY_PATH/qv/maintenance/qvos-repair" \
  "$HOME/.local/share/qvos/maintenance/qvos-repair"
install -D -m 0755 \
  "$OMARCHY_PATH/qv/maintenance/qv" \
  "$HOME/.local/bin/qv"
SCRIPT

git -C "$source_root" init -q -b OS
git -C "$source_root" config user.name "qvOS Test"
git -C "$source_root" config user.email "test@qvos.invalid"
git -C "$source_root" add -A
git -C "$source_root" commit -qm "Create recovery fixture"
git -C "$source_root" remote add origin https://github.com/Yaqyn-qvOS/qvOS.git
git -C "$source_root" update-ref refs/remotes/origin/OS HEAD

load_installed_defaults() {
  {
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' \
      "$source_root/qv/maintenance/essential-packages"
    printf '%s\n' linux linux-firmware
  } | sort -u >"$installed"
}
load_installed_defaults
touch "$action_log" "$pacman_log"

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Dk)
  if [[ -e $QVOS_TEST_STATE/database-bad ]]; then
    echo "database dependency error"
    exit 1
  fi
  echo "No database errors have been found!"
  ;;
-Qq)
  cat "$QVOS_TEST_INSTALLED"
  ;;
-Qk)
  package=${2:?}
  if [[ -e $QVOS_TEST_STATE/unverified/$package ]] &&
    [[ ${QVOS_TEST_PRIVILEGED:-0} != "1" ]]; then
    echo "error: Permission denied"
    exit 1
  fi
  if [[ -e $QVOS_TEST_STATE/missing-files/$package ]]; then
    echo "$package: 2 total files, 1 missing file"
    exit 1
  fi
  echo "$package: 2 total files, 0 missing files"
  ;;
-Qkk)
  package=${2:?}
  if [[ -e $QVOS_TEST_STATE/unverified/$package ]] &&
    [[ ${QVOS_TEST_PRIVILEGED:-0} != "1" ]]; then
    echo "warning: $package: /root/private (failed to calculate SHA256 checksum)"
    echo "$package: 2 total files, 1 altered file"
    exit 1
  fi
  if [[ -e $QVOS_TEST_STATE/damaged/$package ]]; then
    damaged_file="$QVOS_TEST_STATE/damaged-file"
    touch "$damaged_file"
    echo "warning: $package: $damaged_file (SHA256 checksum mismatch)"
    echo "$package: 2 total files, 1 altered file"
    exit 1
  fi
  if [[ -e $QVOS_TEST_STATE/mutable-dirs/$package ]]; then
    mutable_dir="$QVOS_TEST_STATE/mutable-directory"
    mkdir -p "$mutable_dir"
    echo "warning: $package: $mutable_dir (GID mismatch)"
    echo "$package: 2 total files, 1 altered file"
    exit 1
  fi
  echo "$package: 2 total files, 0 altered files"
  ;;
-Qqo)
  echo "linux"
  ;;
-S)
  printf 'pacman\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  for argument in "$@"; do
    rm -f "$QVOS_TEST_STATE/damaged/$argument"
    rm -f "$QVOS_TEST_STATE/missing-files/$argument"
  done
  ;;
*)
  echo "unexpected pacman arguments: $*" >&2
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/git" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"status --porcelain=v1 --untracked-files=all"* ]] &&
  [[ -e $QVOS_TEST_STATE/git-status-bad ]]; then
  echo "unable to read worktree state" >&2
  exit 1
fi
if [[ $* == *"fsck --connectivity-only --no-dangling"* ]] &&
  [[ -e $QVOS_TEST_STATE/git-fsck-bad ]]; then
  echo "broken object connectivity" >&2
  exit 1
fi
exec /usr/bin/git "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
printf 'add\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
for package in "$@"; do
  if ! grep -Fqx "$package" "$QVOS_TEST_INSTALLED"; then
    printf '%s\n' "$package" >>"$QVOS_TEST_INSTALLED"
  fi
done
sort -u -o "$QVOS_TEST_INSTALLED" "$QVOS_TEST_INSTALLED"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == "-v" ]]; then
  printf 'sudo\tvalidate\n' >>"$QVOS_TEST_ACTION_LOG"
  exit
fi
exec env QVOS_TEST_PRIVILEGED=1 "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/snapper" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
if [[ $* == *" list "* ]]; then
  printf '1\n'
  [[ -e $QVOS_TEST_STATE/snapshot-created ]] && printf '2\n'
elif [[ $* == *" create "* ]]; then
  if [[ -e $QVOS_TEST_STATE/snapshot-fail ]]; then
    exit 1
  fi
  printf 'snapshot\tcreate\n' >>"$QVOS_TEST_ACTION_LOG"
  touch "$QVOS_TEST_STATE/snapshot-created"
  printf '2\n'
else
  exit 2
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/findmnt" <<'SCRIPT'
#!/bin/bash
if [[ $* == *"-o TARGET"* ]]; then
  echo "/boot"
else
  echo "rw,relatime"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/df" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
inode=0
[[ ${1:-} == "-Pi" ]] && inode=1
target=${2:-/}
if ((inode)); then
  printf 'Filesystem Inodes IUsed IFree IUse%% Mounted on\n'
  printf 'test 100000 1000 99000 1%% %s\n' "$target"
else
  available=10485760
  [[ $target == "/" ]] &&
    available=${QVOS_TEST_ROOT_AVAILABLE:-10485760}
  [[ $target == "$HOME" ]] &&
    available=${QVOS_TEST_HOME_AVAILABLE:-10485760}
  [[ $target == "/boot" ]] &&
    available=${QVOS_TEST_BOOT_AVAILABLE:-1048576}
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
  printf 'test 20000000 1 %s 1%% %s\n' "$available" "$target"
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
arguments=" $* "
if [[ $arguments == *" --user list-units "* ]]; then
  exit
elif [[ $arguments == *" --user show wayland-session-waitenv.service "* ]]; then
  echo "success"
elif [[ $arguments == *" is-failed "* ]]; then
  unit=${!#}
  [[ -e $QVOS_TEST_STATE/failed-$unit ]]
elif [[ $arguments == *" is-enabled "* ]]; then
  unit=${!#}
  [[ ! -e $QVOS_TEST_STATE/disabled-$unit ]]
elif [[ $arguments == *" --user is-active "* ]]; then
  unit=${!#}
  [[ ! -e $QVOS_TEST_STATE/broken-$unit ]]
elif [[ $arguments == *" --user restart "* ]]; then
  unit=${!#}
  printf 'restart\t%s\n' "$unit" >>"$QVOS_TEST_ACTION_LOG"
  rm -f "$QVOS_TEST_STATE/broken-$unit"
elif [[ $arguments == *" enable "* ]]; then
  unit=${!#}
  printf 'enable\t%s\n' "$unit" >>"$QVOS_TEST_ACTION_LOG"
  rm -f "$QVOS_TEST_STATE/disabled-$unit"
else
  exit 2
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/busctl" <<'SCRIPT'
#!/bin/bash
[[ ! -e $QVOS_TEST_STATE/portal-owner-missing ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/Hyprland" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--verify-config" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
instances) exit ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
choose) printf '%s\n' "${QVOS_TEST_GUM_SELECTION:-Cancel}" ;;
confirm) [[ ${QVOS_TEST_GUM_CONFIRM:-1} == "1" ]] ;;
*) exit 2 ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/ip" <<'SCRIPT'
#!/bin/bash
echo "default via 192.0.2.1"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/getent" <<'SCRIPT'
#!/bin/bash
echo "192.0.2.2 STREAM archlinux.org"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/timedatectl" <<'SCRIPT'
#!/bin/bash
echo "yes"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/uname" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "-r" ]] && echo "test-kernel"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/dkms" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/modinfo" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/journalctl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/coredumpctl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy" <<'SCRIPT'
#!/bin/bash
printf 'omarchy\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hw-nvidia-gsp" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/omarchy-hw-nvidia-without-gsp" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

run_repair() {
  HOME="$test_home" \
    XDG_CACHE_HOME="$state/cache" \
    OMARCHY_PATH="$source_root" \
    QVOS_PACMAN_DB_PATH="$pacman_db" \
    QVOS_PACMAN_LOG="$pacman_log" \
    QVOS_PROC_ROOT="$proc_root" \
    QVOS_SYS_ROOT="$sys_root" \
    QVOS_TEST_STATE="$state" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    "$source_root/qv/maintenance/qvos-repair" "$@"
}

run_health() {
  HOME="$test_home" \
    XDG_CACHE_HOME="$state/cache" \
    OMARCHY_PATH="$source_root" \
    QVOS_PACMAN_DB_PATH="$pacman_db" \
    QVOS_PACMAN_LOG="$pacman_log" \
    QVOS_PROC_ROOT="$proc_root" \
    QVOS_SYS_ROOT="$sys_root" \
    QVOS_TEST_STATE="$state" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    "$source_root/bin/omarchy-qvos-health" "$@"
}

touch "$state/unverified/sudo"
touch "$state/mutable-dirs/systemd"
healthy_output=$(run_health)
grep -Fq '[Informational] packages.defaults-removed' <<<"$healthy_output" ||
  fail "removed defaults are informational"
grep -Fq 'Unverified without sudo: sudo' <<<"$healthy_output" ||
  fail "permission-denied checksum is Unverified"
if grep -Fq '[Repairable   ] packages.essential-damaged' <<<"$healthy_output"; then
  fail "runtime-managed package directory is treated as file corruption"
fi
grep -Fq 'qvOS is ready; no changes were made.' <<<"$healthy_output" ||
  fail "informational findings do not make qvOS unhealthy"
run_health --check >/dev/null
[[ ! -s $action_log ]] || fail "read-only health mutates the fixture"
pass "status succeeds and check ignores informational recovery readiness"

grep -Fvx jq "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
grep -Fvx linux-firmware "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
touch "$state/damaged/hyprlock"
set +e
unhealthy_output=$(run_health --check 2>&1)
unhealthy_status=$?
set -e
((unhealthy_status == 1)) || fail "check accepts repairable findings"
grep -Fq '[Repairable   ] packages.essential-missing' <<<"$unhealthy_output" ||
  fail "missing essential classification"
grep -Fq '[Repairable   ] packages.essential-damaged' <<<"$unhealthy_output" ||
  fail "damaged essential classification"
grep -Fq '[Repairable   ] packages.hardware-missing' <<<"$unhealthy_output" ||
  fail "missing hardware classification"
[[ ! -s $action_log ]] || fail "package inspection performs repair"
pass "essential, hardware, corruption, and default classes stay distinct"

load_installed_defaults
rm -f "$state/damaged/hyprlock"
touch "$state/database-bad"
grep -Fq '[Blocked      ] pacman.database' < <(run_health) ||
  fail "Pacman database failure"
rm -f "$state/database-bad"

touch "$pacman_db/db.lck"
grep -Fq '[Blocked      ] pacman.lock-ownerless' < <(run_health) ||
  fail "ownerless Pacman lock"
install -d "$proc_root/222/fd"
ln -s "$pacman_db/db.lck" "$proc_root/222/fd/3"
grep -Fq '[Blocked      ] pacman.lock-active' < <(run_health) ||
  fail "active Pacman lock"
rm -f "$proc_root/222/fd/3" "$pacman_db/db.lck"

printf '[ALPM] transaction started\n' >"$pacman_log"
grep -Fq '[Blocked      ] pacman.transaction-incomplete' < <(run_health) ||
  fail "unmatched Pacman transaction"
printf '[ALPM] transaction completed\n' >>"$pacman_log"
pass "Pacman database, lock ownership, and transaction state are explicit"

touch "$source_root/untracked-recovery-test"
grep -Fq '[Blocked      ] source.worktree' < <(run_health) ||
  fail "untracked source state"
rm -f "$source_root/untracked-recovery-test"
touch "$state/git-status-bad"
status_failure_output=$(run_health)
grep -Fq '[Blocked      ] source.worktree' <<<"$status_failure_output" ||
  fail "unreadable worktree state"
grep -Fq 'complete worktree status could not be read' <<<"$status_failure_output" ||
  fail "worktree-status failure detail"
rm -f "$state/git-status-bad"
touch "$state/git-fsck-bad"
grep -Fq '[Blocked      ] source.connectivity' < <(run_health) ||
  fail "Git connectivity failure"
rm -f "$state/git-fsck-bad"
mv \
  "$source_root/qv/config/refresh" \
  "$source_root/qv/config/refresh.missing"
grep -Fq '[Blocked      ] source.required-paths' < <(run_health) ||
  fail "required tracked source deletion"
mv \
  "$source_root/qv/config/refresh.missing" \
  "$source_root/qv/config/refresh"
pass "dirty, disconnected, and missing Git source states block mutation"

storage_output=$(QVOS_TEST_ROOT_AVAILABLE=1048576 run_health)
grep -Fq '[Blocked      ] storage.root-blocked' <<<"$storage_output" ||
  fail "root storage hard threshold"
warning_output=$(QVOS_TEST_ROOT_AVAILABLE=3145728 run_health)
grep -Fq '[Informational] storage.root-warning' <<<"$warning_output" ||
  fail "root storage warning threshold"
boot_output=$(QVOS_TEST_BOOT_AVAILABLE=131072 run_health)
grep -Fq '[Blocked      ] storage.boot-blocked' <<<"$boot_output" ||
  fail "boot storage hard threshold"
pass "root, home, and boot storage thresholds gate persistent repair"

chmod 0600 "$test_home/.config/hypr/qv/windows.conf"
mode_output=$(run_health)
grep -Fq '[Repairable   ] config.mode-drift' <<<"$mode_output" ||
  fail "same-byte config mode drift"
printf '\n# user choice\n' \
  >>"$test_home/.config/hypr/qv/looknfeel.conf"
custom_output=$(run_health)
grep -Fq '[Informational] config.customized' <<<"$custom_output" ||
  fail "custom config preservation"
pass "same-byte mode drift repairs separately from customized config"

cp -a \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" \
  "$test_home/.config/hypr/qv/looknfeel.conf"
chmod 0644 "$test_home/.config/hypr/qv/windows.conf"
grep -Fvx jq "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
touch "$state/snapshot-fail"
: >"$action_log"
set +e
snapshot_output=$(run_repair --yes 2>&1)
snapshot_status=$?
set -e
((snapshot_status == 1)) || fail "failed snapshot allows repair"
grep -Fq 'snapshot creation failed' <<<"$snapshot_output" ||
  fail "failed snapshot explanation"
if grep -Eq $'^(add|pacman|restart|enable)\t' "$action_log"; then
  fail "failed snapshot permits persistent mutation"
fi
rm -f "$state/snapshot-fail"
load_installed_defaults
pass "persistent repair aborts when a newer root snapshot is not proven"

: >"$action_log"
set +e
reset_yes_output=$(run_repair --reset --yes 2>&1)
reset_yes_status=$?
set -e
((reset_yes_status == 2)) || fail "--reset --yes bypasses explicit Reset confirmation"
grep -Fq -- '--yes selects Safe Repair only' <<<"$reset_yes_output" ||
  fail "Reset explains the --yes boundary"
[[ ! -s $action_log ]] || fail "rejected --reset --yes mutates the fixture"
pass "--yes is limited to Safe Repair"

grep -Fvx jq "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
grep -Fvx linux-firmware "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
touch \
  "$state/damaged/hyprlock" \
  "$state/runtime-drift" \
  "$state/broken-xdg-desktop-portal-hyprland.service" \
  "$state/disabled-sddm.service"
rm -f "$test_home/.config/hypr/qv/looknfeel.conf"
chmod 0600 "$test_home/.config/hypr/qv/windows.conf"
: >"$action_log"
repair_output=$(run_repair --yes)
grep -Fq 'qvOS safe repair is complete.' <<<"$repair_output" ||
  fail "safe repair result"
grep -Fq $'add\tjq linux-firmware' "$action_log" ||
  fail "missing essential and hardware repair"
grep -Fq $'pacman\t-S --noconfirm --overwrite * hyprlock' "$action_log" ||
  fail "forced damaged-package reinstall"
grep -Fq $'restart\txdg-desktop-portal-hyprland.service' "$action_log" ||
  fail "targeted portal restart"
grep -Fq $'enable\tsddm.service' "$action_log" ||
  fail "SDDM enable without restart"
[[ ! -e $state/runtime-drift ]] || fail "runtime repair"
cmp -s \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" \
  "$test_home/.config/hypr/qv/looknfeel.conf" ||
  fail "missing config repair"
[[ $(stat -c '%a' "$test_home/.config/hypr/qv/windows.conf") == "644" ]] ||
  fail "config mode repair"
snapshot_line=$(grep -nF $'snapshot\tcreate' "$action_log" | head -n 1 | cut -d: -f1)
package_line=$(
  grep -nE $'^(add|pacman)\t' "$action_log" |
    head -n 1 |
    cut -d: -f1
)
((snapshot_line < package_line)) || fail "snapshot does not precede package mutation"
pass "Safe Repair follows package, runtime, config, and targeted-service order"

grep -Fvx chromium "$installed" >"$state/installed.next"
mv "$state/installed.next" "$installed"
printf '\n# reset me\n' \
  >>"$test_home/.config/hypr/qv/looknfeel.conf"
rm -f "$state/snapshot-created"
: >"$action_log"
reset_output=$(run_repair --reset)
grep -Fq 'qvOS reset is complete.' <<<"$reset_output" ||
  fail "reset result"
grep -Fq $'add\tchromium' "$action_log" ||
  fail "Reset default package restore"
cmp -s \
  "$source_root/qv/config/files/hypr/qv/looknfeel.conf" \
  "$test_home/.config/hypr/qv/looknfeel.conf" ||
  fail "Reset config restore"
compgen -G "$test_home/.config/hypr/qv/looknfeel.conf.bak.*" >/dev/null ||
  fail "Reset config backup"
pass "Reset remains explicit, snapshot-gated, and backup-backed"

install -m 0644 \
  "$source_root/qv/maintenance/essential-packages" \
  "$test_home/.local/share/qvos/maintenance/essential-packages"
install -m 0755 \
  "$source_root/qv/maintenance/qvos-repair" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair"
install -m 0755 \
  "$source_root/qv/maintenance/qv" \
  "$test_home/.local/bin/qv"
mv \
  "$test_home/.local/share/qvos/maintenance/qvos-repair" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair.missing"
set +e
missing_runtime_output=$(
  HOME="$test_home" PATH="$test_bin:/usr/bin" \
    "$test_home/.local/bin/qv" repair --status 2>&1
)
missing_runtime_status=$?
set -e
((missing_runtime_status == 1)) || fail "qv accepts a missing recovery runtime"
grep -Fq 'qvOS recovery runtime is unavailable' <<<"$missing_runtime_output" ||
  fail "qv missing-runtime explanation"
mv \
  "$test_home/.local/share/qvos/maintenance/qvos-repair.missing" \
  "$test_home/.local/share/qvos/maintenance/qvos-repair"
mv \
  "$source_root/qv/maintenance/qvos-repair" \
  "$source_root/qv/maintenance/qvos-repair.damaged"
runtime_output=$(
  HOME="$test_home" \
    XDG_CACHE_HOME="$state/cache" \
    OMARCHY_PATH="$source_root" \
    QVOS_PACMAN_DB_PATH="$pacman_db" \
    QVOS_PACMAN_LOG="$pacman_log" \
    QVOS_PROC_ROOT="$proc_root" \
    QVOS_SYS_ROOT="$sys_root" \
    QVOS_TEST_STATE="$state" \
    QVOS_TEST_INSTALLED="$installed" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    "$test_home/.local/bin/qv" repair --status
)
grep -Fq '[Blocked      ] source.required-paths' <<<"$runtime_output" ||
  fail "runtime engine cannot diagnose source-tree damage"
mv \
  "$source_root/qv/maintenance/qvos-repair.damaged" \
  "$source_root/qv/maintenance/qvos-repair"
: >"$action_log"
HOME="$test_home" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$test_home/.local/bin/qv" commands --json
grep -Fq $'omarchy\tcommands --json' "$action_log" ||
  fail "qv non-repair passthrough"
pass "qv repair survives source damage and other qv arguments pass through"

commands=$("$root/bin/omarchy" commands --json)
for binary in omarchy-qvos-health omarchy-qvos-repair; do
  jq -e --arg binary "$binary" \
    'any(.commands[]; .binary == $binary)' <<<"$commands" >/dev/null ||
    fail "$binary command discovery"
done
pass "health and repair remain discoverable Omarchy commands"
