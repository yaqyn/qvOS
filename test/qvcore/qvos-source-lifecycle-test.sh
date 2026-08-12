#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_bin="$test_root/bin"
action_log="$test_root/actions.log"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

"$root/qvcore/install/check"
"$root/qvcore/update/check"

install -d "$test_bin"
: >"$action_log"

project="$test_root/project"
remote="$test_root/qvos.git"
install -d \
  "$project/qvcore/desktop/hyprland" \
  "$project/qvcore/update"
git -C "$project" init -q -b OS
install -m 0755 /dev/stdin "$project/install.sh" <<'SCRIPT'
#!/bin/bash
printf 'installed\n' >>"$QVOS_TEST_BOOT_LOG"
SCRIPT
printf 'one\n' >"$project/version"
install -m 0755 /dev/stdin "$project/qvcore/update/time-sync" <<'SCRIPT'
#!/bin/bash
printf 'time\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin \
  "$project/qvcore/desktop/hyprland/qvos-runtime-config" <<'SCRIPT'
#!/bin/bash
printf 'runtime-config:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 "$root/qvcore/update/source-check" \
  "$project/qvcore/update/source-check"
git -C "$project" add .
git -C "$project" \
  -c user.name='qvOS Test' \
  -c user.email='test@qvos.invalid' \
  commit -qm 'Initial qvOS fixture'
git clone -q --bare "$project" "$remote"

git_env=(
  GIT_ALLOW_PROTOCOL=file
  GIT_CONFIG_COUNT=1
  "GIT_CONFIG_KEY_0=url.file://$remote.insteadOf"
  GIT_CONFIG_VALUE_0=https://github.com/Yaqyn-qvOS/qvOS.git
)

reinstall_home="$test_root/reinstall-home"
live_source="$reinstall_home/.local/share/qvos"
install -d "${live_source%/*}"
git clone -q --branch OS "$remote" "$live_source"
ln -s qvos "$reinstall_home/.local/share/omarchy"
printf 'preserve me\n' >"$live_source/local-change"
env "${git_env[@]}" \
  HOME="$reinstall_home" \
  QVOS_PATH="$live_source" \
  "$root/qvcore/install/reinstall-source" >/dev/null
[[ -z $(git -C "$live_source" status --porcelain=v1 --untracked-files=all) ]] ||
  fail "reinstalled source cleanliness"
backup_source=$(find "${live_source%/*}" -mindepth 1 -maxdepth 1 \
  -type d -name '.qvos-source-backup.*' -print -quit)
[[ -n $backup_source && -f $backup_source/qvos/local-change ]] ||
  fail "complete prior source backup"
pass "source reinstall verifies the same official commit and preserves the old checkout"

printf 'two\n' >"$project/version"
git -C "$project" add version
git -C "$project" \
  -c user.name='qvOS Test' \
  -c user.email='test@qvos.invalid' \
  commit -qm 'Advance qvOS fixture'
git -C "$project" push -q "$remote" OS
installed_head=$(git -C "$live_source" rev-parse HEAD)
set +e
reinstall_mismatch_output=$(
  env "${git_env[@]}" \
    HOME="$reinstall_home" \
    QVOS_PATH="$live_source" \
    "$root/qvcore/install/reinstall-source" 2>&1
)
reinstall_mismatch_status=$?
set -e
((reinstall_mismatch_status == 1)) || fail "reinstall commit-mismatch status"
grep -Fq 'does not match the installed qvOS commit' <<<"$reinstall_mismatch_output" ||
  fail "reinstall commit-mismatch result"
[[ $(git -C "$live_source" rev-parse HEAD) == "$installed_head" ]] ||
  fail "reinstall commit-mismatch preservation"
pass "source reinstall never doubles as an unreviewed update"

install -m 0755 /dev/stdin "$test_bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf 'hyprctl:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

update_home="$test_root/update-home"
update_source="$update_home/.local/share/qvos"
install -d "${update_source%/*}"
git clone -q --branch OS "$remote" "$update_source"
ln -s qvos "$update_home/.local/share/omarchy"
git -C "$update_source" remote set-url origin \
  https://github.com/Yaqyn-qvOS/qvOS.git
printf 'three\n' >"$project/version"
git -C "$project" add version
git -C "$project" \
  -c user.name='qvOS Test' \
  -c user.email='test@qvos.invalid' \
  commit -qm 'Advance qvOS fixture again'
git -C "$project" push -q "$remote" OS
expected_head=$(git -C "$project" rev-parse HEAD)
: >"$action_log"
env "${git_env[@]}" \
  HOME="$update_home" \
  QVOS_PATH="$update_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/update/update-source" >/dev/null
[[ $(git -C "$update_source" rev-parse HEAD) == "$expected_head" ]] ||
  fail "fast-forward source update"
[[ $(<"$action_log") == "time" ]] ||
  fail "source update leaves active Hyprland state to the transaction owner"
printf 'dirty\n' >"$update_source/local-change"
: >"$action_log"
set +e
dirty_update_output=$(
  env "${git_env[@]}" \
    HOME="$update_home" \
    QVOS_PATH="$update_source" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    PATH="$test_bin:/usr/bin" \
    "$root/qvcore/update/update-source" 2>&1
)
dirty_update_status=$?
set -e
((dirty_update_status == 1)) || fail "dirty source update status"
grep -Fq 'source has local changes' <<<"$dirty_update_output" ||
  fail "dirty source update result"
[[ ! -s $action_log ]] || fail "dirty source update side effects"
pass "source update is official, fast-forward only, bounded, and cleanup safe"

boot_home="$test_root/boot-home"
boot_log="$test_root/boot.log"
sudo_log="$test_root/sudo.log"
install -d "$boot_home"
: >"$boot_log"
: >"$sudo_log"
install -m 0755 /dev/stdin "$test_bin/clear" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_SUDO_LOG"
if [[ ${1:-} == "tee" ]]; then
  /usr/bin/cat >/dev/null
fi
SCRIPT
env "${git_env[@]}" \
  HOME="$boot_home" \
  QVOS_TEST_BOOT_LOG="$boot_log" \
  QVOS_TEST_SUDO_LOG="$sudo_log" \
  PATH="$test_bin:/usr/bin" \
  bash "$root/boot.sh" >/dev/null
boot_source="$boot_home/.local/share/qvos"
[[ $(git -C "$boot_source" branch --show-current) == "OS" ]] ||
  fail "fresh install source branch"
[[ -L $boot_home/.local/share/omarchy &&
  $(readlink -- "$boot_home/.local/share/omarchy") == "qvos" ]] ||
  fail "fresh install compatibility link"
[[ $(<"$boot_log") == "installed" ]] || fail "fresh installer handoff"
: >"$sudo_log"
set +e
existing_boot_output=$(
  env "${git_env[@]}" \
    HOME="$boot_home" \
    QVOS_TEST_BOOT_LOG="$boot_log" \
    QVOS_TEST_SUDO_LOG="$sudo_log" \
    PATH="$test_bin:/usr/bin" \
    bash "$root/boot.sh" 2>&1
)
existing_boot_status=$?
set -e
((existing_boot_status == 1)) || fail "existing fresh-install target status"
grep -Fq 'source already exists' <<<"$existing_boot_output" ||
  fail "existing fresh-install target result"
[[ ! -s $sudo_log ]] || fail "existing fresh-install target privileged mutation"
pass "fresh install validates and stages source without deleting an existing checkout"

canonical_home="$test_root/canonical-home"
canonical_source="$canonical_home/.local/share/qvos"
install -d "${canonical_source%/*}"
git clone -q --branch OS "$remote" "$canonical_source"
HOME="$canonical_home" "$root/qvcore/install/source-root" >/dev/null
[[ -L $canonical_home/.local/share/omarchy &&
  $(readlink -- "$canonical_home/.local/share/omarchy") == "qvos" ]] ||
  fail "canonical source compatibility repair"
compatibility_inode=$(stat -c %i "$canonical_home/.local/share/omarchy")
HOME="$canonical_home" "$root/qvcore/install/source-root" >/dev/null
[[ $(stat -c %i "$canonical_home/.local/share/omarchy") == \
  "$compatibility_inode" ]] || fail "canonical source compatibility idempotence"
rm -- "$canonical_home/.local/share/omarchy"
source_root_pids=()
for _ in {1..8}; do
  HOME="$canonical_home" "$root/qvcore/install/source-root" &
  source_root_pids+=("$!")
done
for source_root_pid in "${source_root_pids[@]}"; do
  wait "$source_root_pid"
done
[[ -L $canonical_home/.local/share/omarchy &&
  $(readlink -- "$canonical_home/.local/share/omarchy") == "qvos" ]] ||
  fail "concurrent source compatibility reconciliation"

unsafe_home="$test_root/unsafe-home"
install -d "$unsafe_home/.local/share/qvos"
if HOME="$unsafe_home" "$root/qvcore/install/source-root" >/dev/null 2>&1; then
  fail "unsafe canonical source acceptance"
fi
[[ ! -e $unsafe_home/.local/share/omarchy &&
  ! -L $unsafe_home/.local/share/omarchy ]] ||
  fail "unsafe canonical source compatibility mutation"

conflict_home="$test_root/source-conflict-home"
conflict_source="$conflict_home/.local/share/qvos"
install -d "${conflict_source%/*}" "$conflict_home/.local/share/omarchy"
git clone -q --branch OS "$remote" "$conflict_source"
printf 'preserve conflict\n' >"$conflict_home/.local/share/omarchy/marker"
if HOME="$conflict_home" "$root/qvcore/install/source-root" >/dev/null 2>&1; then
  fail "conflicting compatibility source acceptance"
fi
[[ -d $conflict_source/.git &&
  $(<"$conflict_home/.local/share/omarchy/marker") == "preserve conflict" ]] ||
  fail "conflicting compatibility source was changed"

historical_home="$test_root/historical-home"
historical_source="$historical_home/.local/share/omarchy"
install -d "${historical_source%/*}"
git clone -q --branch OS "$remote" "$historical_source"
if HOME="$historical_home" "$root/qvcore/install/source-root" >/dev/null 2>&1; then
  fail "historical source layout adoption"
fi
[[ -d $historical_source/.git &&
  ! -e $historical_home/.local/share/qvos &&
  ! -L $historical_home/.local/share/qvos ]] ||
  fail "historical source layout changed"
pass "source reconciliation creates only the exact missing compatibility link"

config_source="$test_root/config-source"
config_home="$test_root/config-home"
install -d \
  "$config_source/qvcore/config" \
  "$config_source/qvcore/config/files/example" \
  "$config_source/qvcore/install/config" \
  "$config_source/qvcore/shell/files" \
  "$config_home"
printf 'configured\n' >"$config_source/qvcore/config/files/example/value"
printf 'bashrc\n' >"$config_source/qvcore/shell/files/bashrc"
install -m 0644 /dev/stdin "$config_source/qvcore/install/config/theme.sh" <<'SCRIPT'
printf 'theme\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
for command in \
  qv-refresh-hyprland \
  qv-refresh-limine \
  qv-refresh-plymouth; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${0##*/}" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
done
: >"$action_log"
set +e
HOME="$config_home" \
  QVOS_PATH="$root" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/install/reinstall" >/dev/null
cancelled_reinstall_status=$?
set -e
(( cancelled_reinstall_status == 130 )) || fail "full reinstall cancellation status"
[[ ! -s $action_log ]] || fail "full reinstall cancellation mutation"
set +e
HOME="$config_home" \
  QVOS_PATH="$config_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/install/reinstall-configs" >/dev/null
cancelled_config_status=$?
set -e
(( cancelled_config_status == 130 )) || fail "config reset cancellation status"
[[ ! -e $config_home/.config && ! -s $action_log ]] ||
  fail "config reset cancellation mutation"
HOME="$config_home" \
  QVOS_PATH="$config_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/install/reinstall-configs" --yes >/dev/null
[[ $(<"$config_home/.config/example/value") == "configured" ]] ||
  fail "config reset source"
[[ $(<"$action_log") == $'theme\nqv-refresh-hyprland\nqv-refresh-limine\nqv-refresh-plymouth' ]] ||
  fail "config reset owner order"
pass "config reset copies the native seed and reconciles native Hyprland config"

package_source="$test_root/package-source"
install -d "$package_source/qvcore/install/packaging"
install -m 0755 /dev/stdin "$test_bin/qv-refresh-pacman" <<'SCRIPT'
#!/bin/bash
printf 'refresh\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$package_source/qvcore/install/packaging/resolve" <<'SCRIPT'
#!/bin/bash
exit 9
SCRIPT
: >"$action_log"
set +e
QVOS_PATH="$package_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/install/reinstall-packages" --yes >/dev/null 2>&1
invalid_packages_status=$?
set -e
((invalid_packages_status == 9)) || fail "invalid package manifest status"
[[ ! -s $action_log ]] || fail "invalid package manifest mutation"
install -m 0755 /dev/stdin "$package_source/qvcore/install/packaging/resolve" <<'SCRIPT'
#!/bin/bash
printf '%s\n' alpha beta
SCRIPT
: >"$action_log"
set +e
QVOS_PATH="$package_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/install/reinstall-packages" >/dev/null
cancelled_packages_status=$?
set -e
(( cancelled_packages_status == 130 )) || fail "package reinstall cancellation status"
[[ ! -s $action_log ]] || fail "package reinstall cancellation mutation"
QVOS_PATH="$package_source" \
  QVOS_TEST_ACTION_LOG="$action_log" \
  PATH="$test_bin:/usr/bin" \
  "$root/qvcore/install/reinstall-packages" --yes >/dev/null
[[ $(<"$action_log") == $'refresh\nsudo:pacman -Suu --noconfirm\nsudo:pacman -Syu --noconfirm --needed alpha beta' ]] ||
  fail "validated package reinstall order"
pass "package reinstall validates the native manifest before any mutation"
