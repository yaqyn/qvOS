#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
software="$root/qv/maintenance/personal-software"
baseline_owner="$root/qv/maintenance/personal-software-baseline"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
user_bin="$test_home/.local/bin"
applications="$test_home/Applications"
system_bin="$test_root/usr-local-bin"
restricted_bin="$test_root/restricted-bin"
qvcore_owner_dir="$test_root/qvcore-owners"
state_home="$test_home/.local/state"
explicit_packages="$test_root/explicit-packages"
foreign_packages="$test_root/foreign-packages"
npm_packages="$test_root/npm-packages"
action_log="$test_root/actions.log"
sentinel="$test_home/.config/qvos-personal-sentinel"

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
  "$applications" \
  "$state_home" \
  "$system_bin" \
  "$restricted_bin" \
  "$qvcore_owner_dir" \
  "$test_bin" \
  "$test_home/.config" \
  "$test_home/.bun/install/global" \
  "$test_home/.local/share/qvos/bin" \
  "$user_bin"
touch "$action_log" "$foreign_packages"
printf '%s\n' alacritty sudo >"$explicit_packages"
printf '%s\n' npm corepack >"$npm_packages"
printf '{"dependencies":{}}\n' \
  >"$test_home/.bun/install/global/package.json"
printf 'preserve me\n' >"$sentinel"

install -m 0755 /dev/stdin "$test_bin/pacman" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
-Qqe)
  cat "$QVOS_TEST_EXPLICIT_PACKAGES"
  ;;
-Qqm)
  cat "$QVOS_TEST_FOREIGN_PACKAGES"
  ;;
-Qo)
  [[ ${2##*/} == "package-owned" ]]
  ;;
-Q)
  grep -Fxq "$2" "$QVOS_TEST_EXPLICIT_PACKAGES"
  ;;
-Rs)
  [[ ${2:-} == "--print" ]] || exit 2
  shift 2
  for package in "$@"; do
    grep -Fxq "$package" "$QVOS_TEST_EXPLICIT_PACKAGES" || exit 1
  done
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/expac" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "-Q" && -n ${3:-} ]] || exit 2
case ${2:-} in
%N)
  [[ $3 == "shared-lib" ]] && printf 'personal-parent\n'
  ;;
%d)
  printf 'Description for %s\n' "$3"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/npm" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
ls)
  jq -Rn '
    [inputs | select(length > 0)]
    | {
        dependencies: (
          map({key: ., value: {version: "1.0.0"}})
          | from_entries
        )
      }
  ' <"$QVOS_TEST_NPM_PACKAGES"
  ;;
uninstall)
  [[ ${2:-} == "--global" && -n ${3:-} ]] || exit 2
  printf 'npm\t%s\n' "$3" >>"$QVOS_TEST_ACTION_LOG"
  grep -Fvx "$3" "$QVOS_TEST_NPM_PACKAGES" \
    >"$QVOS_TEST_NPM_PACKAGES.pending" || true
  mv "$QVOS_TEST_NPM_PACKAGES.pending" "$QVOS_TEST_NPM_PACKAGES"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/bun" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "remove" && ${2:-} == "--global" && -n ${3:-} ]] || exit 2
printf 'bun\t%s\n' "$3" >>"$QVOS_TEST_ACTION_LOG"
jq --arg package "$3" '
  del(
    .dependencies[$package],
    .devDependencies[$package],
    .optionalDependencies[$package]
  )
' "$HOME/.bun/install/global/package.json" \
  >"$HOME/.bun/install/global/package.json.pending"
mv \
  "$HOME/.bun/install/global/package.json.pending" \
  "$HOME/.bun/install/global/package.json"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
for package in "$@"; do
  printf 'pacman\t%s\n' "$package" >>"$QVOS_TEST_ACTION_LOG"
  grep -Fvx "$package" "$QVOS_TEST_EXPLICIT_PACKAGES" \
    >"$QVOS_TEST_EXPLICIT_PACKAGES.pending" || true
  mv \
    "$QVOS_TEST_EXPLICIT_PACKAGES.pending" \
    "$QVOS_TEST_EXPLICIT_PACKAGES"
done
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gio" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "trash" && -n ${2:-} ]] || exit 2
printf 'trash\t%s\n' "$2" >>"$QVOS_TEST_ACTION_LOG"
rm -- "$2"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
exec "$@"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
case ${1:-} in
choose)
  IFS=',' read -r -a names <<<"${QVOS_TEST_SELECTIONS:-}"
  for argument in "$@"; do
    for name in "${names[@]}"; do
      [[ -n $name ]] || continue
      if [[ $argument == *"  $name —"* ]]; then
        printf '%s\n' "${argument##*:}"
      fi
    done
  done
  ;;
confirm)
  [[ ${QVOS_TEST_CONFIRM:-1} == "1" ]]
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

for component in warp codex; do
  install -m 0755 /dev/stdin "$qvcore_owner_dir/$component.sh" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--prepare-remove" ]] || exit 2
component=$(basename "$0" .sh)
printf 'cleanup\t%s\n' "$component" >>"$QVOS_TEST_ACTION_LOG"
rm -f "$HOME/.local/state/qvos/qvcore/$component"
SCRIPT
done

install -m 0755 /dev/stdin "$qvcore_owner_dir/proton.sh" <<'SCRIPT'
#!/bin/bash
case $* in
"--remove --check")
  exit
  ;;
"--remove --yes")
  printf 'cleanup\tproton\n' >>"$QVOS_TEST_ACTION_LOG"
  for package in protonmail-bridge-core proton-vpn-cli; do
    grep -Fvx "$package" "$QVOS_TEST_EXPLICIT_PACKAGES" \
      >"$QVOS_TEST_EXPLICIT_PACKAGES.pending" || true
    mv \
      "$QVOS_TEST_EXPLICIT_PACKAGES.pending" \
      "$QVOS_TEST_EXPLICIT_PACKAGES"
  done
  rm -f \
    "$HOME/.local/bin/pass-cli" \
    "$HOME/.local/bin/proton-drive" \
    "$HOME/.local/state/qvos/qvcore/proton"
  ;;
*)
  exit 2
  ;;
esac
SCRIPT

install -m 0755 /dev/null "$user_bin/existing-tool"
install -m 0755 /dev/null "$applications/Existing.AppImage"
install -m 0755 /dev/null "$system_bin/existing-system-tool"

run_software() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_CONFIRM="${QVOS_TEST_CONFIRM:-1}" \
    QVOS_TEST_EXPLICIT_PACKAGES="$explicit_packages" \
    QVOS_TEST_FOREIGN_PACKAGES="$foreign_packages" \
    QVOS_TEST_NPM_PACKAGES="$npm_packages" \
    QVOS_TEST_SELECTIONS="${QVOS_TEST_SELECTIONS:-}" \
    HOME="$test_home" \
    XDG_STATE_HOME="$state_home" \
    OMARCHY_PATH="$root" \
    QVOS_PERSONAL_APPLICATIONS_DIR="$applications" \
    QVOS_PERSONAL_QVCORE_OWNER_DIR="$qvcore_owner_dir" \
    QVOS_PERSONAL_SYSTEM_BIN_DIR="$system_bin" \
    QVOS_PERSONAL_USER_BIN_DIR="$user_bin" \
    PATH="${QVOS_TEST_PATH:-$test_bin:$root/bin:/usr/bin}" \
    "$software" "$@"
}

missing_output=$(run_software --status)
grep -Fq "predates personal-software tracking" <<<"$missing_output" ||
  fail "missing baseline explanation"
grep -Fq 'software --initialize' <<<"$missing_output" ||
  fail "missing baseline initialization route"
[[ ! -e $state_home/qvos/software/baseline.tsv ]] ||
  fail "read-only status initializes tracking"
[[ ! -s $action_log ]] || fail "missing-baseline status mutates software"
pass "existing installations are never assigned guessed software ownership"

run_software --initialize --yes >/dev/null
baseline="$state_home/qvos/software/baseline.tsv"
[[ -f $baseline ]] || fail "personal-software baseline creation"
[[ $(stat -c '%a' "$baseline") == "600" ]] ||
  fail "personal-software baseline permissions"
for expected in \
  $'pacman\talacritty' \
  $'pacman\tsudo' \
  $'npm\tnpm' \
  $'npm\tcorepack'; do
  grep -Fqx "$expected" "$baseline" ||
    fail "baseline entry: $expected"
done
pass "explicit initialization records immutable package-manager ownership"

baseline_before=$(sha256sum "$baseline")
QVOS_TEST_EXPLICIT_PACKAGES="$explicit_packages" \
  QVOS_TEST_FOREIGN_PACKAGES="$foreign_packages" \
  QVOS_TEST_NPM_PACKAGES="$npm_packages" \
  HOME="$test_home" \
  XDG_STATE_HOME="$state_home" \
  QVOS_PERSONAL_APPLICATIONS_DIR="$applications" \
  QVOS_PERSONAL_SYSTEM_BIN_DIR="$system_bin" \
  QVOS_PERSONAL_USER_BIN_DIR="$user_bin" \
  PATH="$test_bin:/usr/bin" \
  "$baseline_owner" --capture >/dev/null
[[ $(sha256sum "$baseline") == "$baseline_before" ]] ||
  fail "existing personal-software baseline was overwritten"
pass "personal-software baseline is never recaptured over user history"

printf '%s\n' \
  alacritty \
  sudo \
  aur-app \
  cloudflare-warp-nox-bin \
  kdenlive \
  protonmail-bridge-core \
  proton-vpn-cli \
  shared-lib \
  >"$explicit_packages"
printf '%s\n' aur-app >"$foreign_packages"
printf '%s\n' npm corepack serve >"$npm_packages"
jq '.dependencies.cowsay = "1.0.0"' \
  "$test_home/.bun/install/global/package.json" \
  >"$test_home/.bun/install/global/package.json.pending"
mv \
  "$test_home/.bun/install/global/package.json.pending" \
  "$test_home/.bun/install/global/package.json"

install -m 0755 /dev/stdin "$user_bin/gemini" <<'SCRIPT'
#!/bin/bash
package="@google/gemini-cli"
command="gemini"
npx_bin="$HOME/.cache/npx"
SCRIPT
install -m 0755 /dev/stdin "$user_bin/pi" <<'SCRIPT'
#!/bin/bash
package="@earendil-works/pi-coding-agent"
command="pi"
npx_bin="$HOME/.cache/npx"
SCRIPT
install -m 0755 /dev/null "$user_bin/personal-tool"
install -m 0755 /dev/null "$user_bin/codex"
install -m 0755 /dev/null "$user_bin/pass-cli"
install -m 0755 /dev/null "$user_bin/proton-drive"
install -m 0755 /dev/null "$user_bin/qv"
install -m 0755 /dev/null "$test_home/.local/share/qvos/bin/qvos-owned"
ln -s \
  "$test_home/.local/share/qvos/bin/qvos-owned" \
  "$user_bin/qvos-owned"
install -m 0755 /dev/null "$applications/Editor.AppImage"
install -m 0755 /dev/null "$system_bin/package-owned"
install -m 0755 /dev/null "$system_bin/system-tool"
install -d "$state_home/qvos/qvcore"
touch "$state_home/qvos/qvcore/warp" "$state_home/qvos/qvcore/codex"
touch "$state_home/qvos/qvcore/proton"
printf '%s\n' \
  $'pacman\tcloudflare-warp-nox-bin' \
  $'user-bin\tcodex' \
  >>"$baseline"

: >"$action_log"
status_output=$(run_software --status)
grep -Fq 'Detected 12 personal software item(s)' <<<"$status_output" ||
  fail "complete personal-software inventory count"
grep -Fq 'AUR/foreign        aur-app' <<<"$status_output" ||
  fail "AUR inventory"
grep -Eq 'qvCORE · Pacman[[:space:]]+kdenlive' <<<"$status_output" ||
  fail "qvCORE Media package inventory"
grep -Fq 'Description for kdenlive' <<<"$status_output" ||
  fail "Pacman package description"
if ! grep -Eq 'qvCORE · Pacman[[:space:]]+cloudflare-warp-nox-bin' <<<"$status_output" ||
  ! grep -Fq 'WARP; Description for cloudflare-warp-nox-bin; integration cleanup included' \
    <<<"$status_output"; then
  fail "qvCORE WARP personal-software ownership"
fi
if ! grep -Eq 'qvCORE · Direct[[:space:]]+codex' <<<"$status_output" ||
  ! grep -Fq 'Codex; '"$user_bin/codex"'; integration cleanup included' \
    <<<"$status_output"; then
  fail "qvCORE Codex personal-software ownership"
fi
if ! grep -Eq 'qvCORE · Setup[[:space:]]+Proton' <<<"$status_output" ||
  ! grep -Fq '4 local components installed; removes together; cloud data and saved authentication are preserved' \
    <<<"$status_output"; then
  fail "qvCORE Proton grouped personal-software ownership"
fi
if grep -Eq 'qvCORE · (Pacman|Direct)[[:space:]]+(protonmail-bridge-core|proton-vpn-cli|pass-cli|proton-drive)' \
  <<<"$status_output"; then
  fail "qvCORE Proton components are exposed individually"
fi
if ! grep -Fq 'shared-lib' <<<"$status_output" ||
  ! grep -Fq 'required by personal-parent [protected]' <<<"$status_output"; then
  fail "required package protection"
fi
grep -Fq 'Bun global         cowsay' <<<"$status_output" ||
  fail "Bun global inventory"
grep -Fq 'npm global         serve' <<<"$status_output" ||
  fail "npm global inventory"
grep -Fq 'npx wrapper        gemini' <<<"$status_output" ||
  fail "persistent npx wrapper inventory"
grep -Fq 'Standalone         personal-tool' <<<"$status_output" ||
  fail "user standalone inventory"
grep -Fq 'AppImage           Editor.AppImage' <<<"$status_output" ||
  fail "AppImage inventory"
grep -Fq 'System standalone  system-tool' <<<"$status_output" ||
  fail "system standalone inventory"
if grep -Eq 'existing-tool|Existing.AppImage|existing-system-tool|qvos-owned|[[:space:]]pi[[:space:]]|package-owned|[[:space:]]qv[[:space:]]|[[:space:]]sudo[[:space:]]' \
  <<<"$status_output"; then
  fail "baseline or qvOS-owned software appears as personal"
fi
grep -Fq '11 item(s) can be selected for removal' <<<"$status_output" ||
  fail "personal-software removal count"
[[ ! -s $action_log ]] || fail "personal-software status mutates software"
[[ $(<"$sentinel") == "preserve me" ]] ||
  fail "personal-software inventory changes config"
pass "inventory covers package managers and standard standalone locations"

for command in cat find grep head jq readlink sed sort; do
  ln -s "$(command -v "$command")" "$restricted_bin/$command"
done
for command in bun expac gum npm omarchy-pkg-drop pacman sudo; do
  ln -s "$test_bin/$command" "$restricted_bin/$command"
done
: >"$action_log"
set +e
preflight_output=$(
  QVOS_TEST_PATH="$restricted_bin" \
    QVOS_TEST_SELECTIONS="kdenlive,personal-tool" \
    run_software --remove 2>&1
)
preflight_status=$?
set -e
((preflight_status == 1)) || fail "missing removal owner is accepted"
grep -Fq 'Personal software removal requires: gio' <<<"$preflight_output" ||
  fail "missing removal owner explanation"
grep -Fqx kdenlive "$explicit_packages" ||
  fail "package changed before removal-owner preflight"
[[ -e $user_bin/personal-tool ]] ||
  fail "standalone changed before removal-owner preflight"
[[ ! -s $action_log ]] ||
  fail "removal starts before every selected owner is available"
pass "mixed removal preflights every owner before the first mutation"

ln -s "$test_bin/gio" "$restricted_bin/gio"
unlink "$restricted_bin/omarchy-pkg-drop"
: >"$action_log"
set +e
package_preflight_output=$(
  QVOS_TEST_PATH="$restricted_bin" \
    QVOS_TEST_SELECTIONS="kdenlive" \
    run_software --remove 2>&1
)
package_preflight_status=$?
set -e
((package_preflight_status == 1)) ||
  fail "missing package removal owner is accepted"
grep -Fq 'Personal software removal requires: omarchy-pkg-drop' \
  <<<"$package_preflight_output" ||
  fail "missing package removal owner explanation"
grep -Fqx kdenlive "$explicit_packages" ||
  fail "package changed before package-owner preflight"
[[ ! -s $action_log ]] ||
  fail "package removal starts before its owner is available"
ln -s "$test_bin/omarchy-pkg-drop" "$restricted_bin/omarchy-pkg-drop"
pass "Pacman removal preflights its exact qvOS owner"

QVOS_TEST_SELECTIONS="kdenlive,cowsay,serve,gemini,personal-tool,Editor.AppImage,system-tool" \
  run_software --remove >/dev/null
for expected in \
  $'pacman\tkdenlive' \
  $'bun\tcowsay' \
  $'npm\tserve' \
  "trash"$'\t'"$user_bin/gemini" \
  "trash"$'\t'"$user_bin/personal-tool" \
  "trash"$'\t'"$applications/Editor.AppImage" \
  "sudo"$'\t'"rm -- $system_bin/system-tool"; do
  grep -Fqx "$expected" "$action_log" ||
    fail "selected removal action: $expected"
done
grep -Fqx aur-app "$explicit_packages" ||
  fail "unselected AUR package was removed"
grep -Fqx cloudflare-warp-nox-bin "$explicit_packages" ||
  fail "unselected qvCORE package was removed"
grep -Fqx shared-lib "$explicit_packages" ||
  fail "protected required package was removed"
[[ -e $user_bin/codex ]] ||
  fail "unselected qvCORE standalone was removed"
[[ $(<"$sentinel") == "preserve me" ]] ||
  fail "personal-software removal changes config"
pass "removal delegates only exact selections to their real owners"

remaining_output=$(run_software --status)
grep -Fq 'Detected 5 personal software item(s)' <<<"$remaining_output" ||
  fail "post-removal personal-software inventory"
grep -Fq 'aur-app' <<<"$remaining_output" ||
  fail "post-removal AUR state"
grep -Fq 'shared-lib' <<<"$remaining_output" ||
  fail "post-removal protected state"
pass "post-removal inventory truthfully preserves unselected software"

: >"$action_log"
QVOS_TEST_SELECTIONS="cloudflare-warp-nox-bin,codex" \
  run_software --remove >/dev/null
expected_qvcore_removal=$'cleanup\twarp\ncleanup\tcodex\npacman\tcloudflare-warp-nox-bin\ntrash\t'"$user_bin/codex"
[[ $(<"$action_log") == "$expected_qvcore_removal" ]] ||
  fail "qvCORE software cleanup and removal order"
[[ ! -e $state_home/qvos/qvcore/warp ]] ||
  fail "WARP integration state remains after software removal"
[[ ! -e $state_home/qvos/qvcore/codex ]] ||
  fail "Codex integration state remains after software removal"
[[ ! -e $user_bin/codex ]] ||
  fail "selected qvCORE standalone remains"
if grep -Fxq cloudflare-warp-nox-bin "$explicit_packages"; then
  fail "selected qvCORE package remains"
fi
proton_remaining_output=$(run_software --status)
grep -Fq 'Detected 3 personal software item(s)' <<<"$proton_remaining_output" ||
  fail "grouped Proton setup remains after unrelated removals"
pass "qvCORE apps are removable personal software with integration-aware cleanup"

: >"$action_log"
QVOS_TEST_SELECTIONS="Proton" run_software --remove >/dev/null
[[ $(<"$action_log") == $'cleanup\tproton' ]] ||
  fail "grouped Proton removal owner"
for proton_item in \
  protonmail-bridge-core \
  proton-vpn-cli; do
  if grep -Fxq "$proton_item" "$explicit_packages"; then
    fail "grouped Proton package remains: $proton_item"
  fi
done
for proton_path in "$user_bin/pass-cli" "$user_bin/proton-drive"; do
  [[ ! -e $proton_path ]] || fail "grouped Proton command remains: $proton_path"
done
[[ -e $user_bin/qv ]] || fail "protected qvOS recovery command was removed"
final_output=$(run_software --status)
grep -Fq 'Detected 2 personal software item(s)' <<<"$final_output" ||
  fail "final personal-software inventory"
pass "multi-artifact qvCORE setups delegate one coordinated removal"

for ownership in \
  $'brave-origin\tpacman\tbrave-origin-beta-bin' \
  $'warp\tpacman\tcloudflare-warp-nox-bin' \
  $'share\tpacman\tlocalsend' \
  $'dev\tuser-bin\tsupabase' \
  $'codex\tuser-bin\tcodex' \
  $'proton\tpacman\tprotonmail-bridge-core' \
  $'proton\tpacman\tproton-vpn-cli' \
  $'proton\tuser-bin\tpass-cli' \
  $'proton\tuser-bin\tproton-drive' \
  $'steam\tpacman\tsteam' \
  $'media\tpacman\tkdenlive'; do
  grep -Fqx "$ownership" "$root/qv/core/software-ownership.tsv" ||
    fail "qvCORE software ownership: $ownership"
done
pass "qvCORE curation has explicit cross-installer software ownership"

grep -Fq \
  "\"\$OMARCHY_PATH/qv/maintenance/personal-software-baseline\" --capture" \
  "$root/qv/install/post-install/finished" ||
  fail "fresh-install baseline capture"
pass "fresh qvOS installation records the personal-software baseline once"
