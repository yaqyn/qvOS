#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
media_script="$root/qv/core/media.sh"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
installed_dir="$test_root/installed"
action_log="$test_root/actions"
gum_args_log="$test_root/gum-args"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

reset_test_state() {
  find "$installed_dir" -mindepth 1 -maxdepth 1 -type f -delete
  : >"$action_log"
  : >"$gum_args_log"
}

mark_installed() {
  install -m 0644 /dev/null "$installed_dir/$1"
}

install -d "$test_bin" "$installed_dir"

install -m 0755 /dev/stdin "$test_bin/gum" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_GUM_ARGS_LOG"

if [[ ${QVOS_TEST_GUM_CANCEL:-0} == "1" ]]; then
  exit "${QVOS_TEST_GUM_STATUS:-130}"
fi

printf '%s' "${QVOS_TEST_MEDIA_SELECTION:-}"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
[[ -f $QVOS_TEST_INSTALLED_DIR/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-missing" <<'SCRIPT'
#!/bin/bash
[[ ! -f $QVOS_TEST_INSTALLED_DIR/$1 ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"

if [[ $1 == "${QVOS_TEST_PACKAGE_FAIL:-}" ]]; then
  exit "${QVOS_TEST_PACKAGE_FAIL_STATUS:-1}"
fi

if [[ $1 != "${QVOS_TEST_PACKAGE_NO_REGISTER:-}" ]]; then
  install -m 0644 /dev/null "$QVOS_TEST_INSTALLED_DIR/$1"
fi
SCRIPT

run_media() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_GUM_ARGS_LOG="$gum_args_log" \
    QVOS_TEST_GUM_CANCEL="${QVOS_TEST_GUM_CANCEL:-0}" \
    QVOS_TEST_GUM_STATUS="${QVOS_TEST_GUM_STATUS:-130}" \
    QVOS_TEST_INSTALLED_DIR="$installed_dir" \
    QVOS_TEST_MEDIA_SELECTION="${QVOS_TEST_MEDIA_SELECTION:-}" \
    QVOS_TEST_PACKAGE_FAIL="${QVOS_TEST_PACKAGE_FAIL:-}" \
    QVOS_TEST_PACKAGE_FAIL_STATUS="${QVOS_TEST_PACKAGE_FAIL_STATUS:-1}" \
    QVOS_TEST_PACKAGE_NO_REGISTER="${QVOS_TEST_PACKAGE_NO_REGISTER:-}" \
    HOME="$test_root" \
    PATH="$test_bin:/usr/bin" \
    "$media_script"
}

all_selection=$'gimp\ninkscape\nkrita\nkdenlive\nobs-studio\naudacity\nblender'
all_missing_options=$'GIMP — Raster image editing [missing]:gimp\nInkscape — Vector graphics [missing]:inkscape\nKrita — Digital painting [missing]:krita\nKdenlive — Video editing [missing]:kdenlive\nOBS Studio — Recording and streaming [missing]:obs-studio\nAudacity — Audio editing [missing]:audacity\nBlender — 3D creation [missing]:blender'
expected_gum_args=$'choose\n--no-limit\n--height\n10\n--label-delimiter\n:\n--header\nSpace: select • Enter: install • Esc: cancel\n'"$all_missing_options"

reset_test_state
all_output=$(QVOS_TEST_MEDIA_SELECTION="$all_selection" run_media)
expected_all_actions=$'sudo\t-v\npackage\tgimp\npackage\tinkscape\npackage\tkrita\npackage\tkdenlive\npackage\tobs-studio\npackage\taudacity\npackage\tblender'
[[ $(<"$action_log") == "$expected_all_actions" ]] ||
  fail "complete curated Media install steps"
[[ $(<"$gum_args_log") == "$expected_gum_args" ]] || fail "Media multi-select presentation"
grep -Fq 'qvCORE Media inventory: 0/7 ready' <<<"$all_output" ||
  fail "initial missing Media inventory"
grep -Fq '[1/7] Installing GIMP...' <<<"$all_output" ||
  fail "Media install step output"
grep -Fq 'qvCORE Media inventory: 7/7 ready' <<<"$all_output" ||
  fail "final ready Media inventory"
grep -Fq 'qvCORE Media selection is ready: 7/7 selected.' <<<"$all_output" ||
  fail "complete Media selection summary"
pass "Media inventories, installs, and verifies the complete curated list"

reset_test_state
mark_installed gimp
installed_output=$(QVOS_TEST_MEDIA_SELECTION="gimp" run_media)
[[ ! -s $action_log ]] || fail "already-ready Media selection changes packages"
grep -Fq 'GIMP — Raster image editing [ready]:gimp' "$gum_args_log" ||
  fail "ready Media status in selector"
grep -Fq 'Inkscape — Vector graphics [missing]:inkscape' "$gum_args_log" ||
  fail "missing Media status in selector"
grep -Fq '[1/1] GIMP is already ready; keeping it.' <<<"$installed_output" ||
  fail "already-ready Media step"
grep -Fq 'qvCORE Media selection is ready: 1/1 selected.' <<<"$installed_output" ||
  fail "already-ready Media summary"
pass "Media keeps an already-installed selected application without sudo"

reset_test_state
mark_installed gimp
mixed_selection=$'gimp\nkrita\nobs-studio'
mixed_output=$(QVOS_TEST_MEDIA_SELECTION="$mixed_selection" run_media)
expected_mixed_actions=$'sudo\t-v\npackage\tkrita\npackage\tobs-studio'
[[ $(<"$action_log") == "$expected_mixed_actions" ]] ||
  fail "mixed ready and missing Media actions"
grep -Fq '[1/3] GIMP is already ready; keeping it.' <<<"$mixed_output" ||
  fail "mixed Media ready step"
grep -Fq '[2/3] Installing Krita...' <<<"$mixed_output" ||
  fail "mixed Media missing step"
grep -Fq 'qvCORE Media inventory: 3/7 ready' <<<"$mixed_output" ||
  fail "mixed Media final inventory"
grep -Fq 'qvCORE Media selection is ready: 3/3 selected.' <<<"$mixed_output" ||
  fail "mixed Media summary"
pass "Media skips installed selections and installs only new selections"

reset_test_state
interrupted_selection=$'gimp\ninkscape\nkrita'
set +e
interrupted_output=$(
  QVOS_TEST_MEDIA_SELECTION="$interrupted_selection" \
    QVOS_TEST_PACKAGE_FAIL=inkscape \
    QVOS_TEST_PACKAGE_FAIL_STATUS=130 \
    run_media 2>&1
)
interrupted_status=$?
set -e
((interrupted_status == 130)) || fail "interrupted Media status propagation"
expected_interrupted_actions=$'sudo\t-v\npackage\tgimp\npackage\tinkscape'
[[ $(<"$action_log") == "$expected_interrupted_actions" ]] ||
  fail "interrupted Media install boundary"
[[ -f $installed_dir/gimp ]] || fail "completed Media install was not preserved"
[[ ! -f $installed_dir/inkscape ]] || fail "failed Media install was registered"
[[ ! -f $installed_dir/krita ]] || fail "Media continued after interruption"
grep -Fq 'qvCORE Media stopped during Inkscape installation.' <<<"$interrupted_output" ||
  fail "interrupted Media context"
grep -Fq 'Completed application installs and Pacman downloads were preserved.' <<<"$interrupted_output" ||
  fail "interrupted Media preservation guidance"
grep -Fq 'qvCORE Media inventory: 1/7 ready' <<<"$interrupted_output" ||
  fail "interrupted Media inventory"
pass "Media preserves completed work and reports resumable state after interruption"

: >"$action_log"
resumed_output=$(QVOS_TEST_MEDIA_SELECTION="$interrupted_selection" run_media)
expected_resumed_actions=$'sudo\t-v\npackage\tinkscape\npackage\tkrita'
[[ $(<"$action_log") == "$expected_resumed_actions" ]] ||
  fail "resumed Media install actions"
grep -Fq '[1/3] GIMP is already ready; keeping it.' <<<"$resumed_output" ||
  fail "resumed Media ready step"
grep -Fq 'qvCORE Media selection is ready: 3/3 selected.' <<<"$resumed_output" ||
  fail "resumed Media summary"
pass "Media reruns resume from the remaining selected applications"

reset_test_state
set +e
cancel_output=$(QVOS_TEST_GUM_CANCEL=1 run_media 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) || fail "Media selection cancellation status propagation"
[[ ! -s $action_log ]] || fail "canceled Media selection performs actions"
grep -Fq 'qvCORE Media selection canceled; no package changes were started.' <<<"$cancel_output" ||
  fail "Media selection cancellation message"
pass "canceling the selector exits before authorization or package changes"

reset_test_state
empty_output=$(QVOS_TEST_MEDIA_SELECTION="" run_media)
[[ ! -s $action_log ]] || fail "empty Media selection performs actions"
grep -Fq 'No qvCORE Media applications selected; nothing was installed.' <<<"$empty_output" ||
  fail "empty Media selection message"
pass "an empty Media selection skips installation cleanly"

reset_test_state
set +e
unknown_output=$(QVOS_TEST_MEDIA_SELECTION="unexpected" run_media 2>&1)
unknown_status=$?
set -e
((unknown_status != 0)) || fail "unknown Media selection succeeds"
[[ ! -s $action_log ]] || fail "unknown Media selection performs actions"
grep -Fq 'Unknown qvCORE Media selection: unexpected' <<<"$unknown_output" ||
  fail "unknown Media selection message"
pass "Media rejects selections outside the curated list"

reset_test_state
set +e
verification_output=$(
  QVOS_TEST_MEDIA_SELECTION="audacity" \
    QVOS_TEST_PACKAGE_NO_REGISTER=audacity \
    run_media 2>&1
)
verification_status=$?
set -e
((verification_status != 0)) || fail "unregistered Media install succeeds"
[[ $(<"$action_log") == $'sudo\t-v\npackage\taudacity' ]] ||
  fail "Media verification action boundary"
grep -Fq 'Audacity verification failed after installation.' <<<"$verification_output" ||
  fail "Media verification failure"
grep -Fq 'qvCORE Media inventory: 0/7 ready' <<<"$verification_output" ||
  fail "Media verification failure inventory"
pass "Media requires package registration after every install step"

grep -Fq 'sudo pacman -S --noconfirm --needed "$@"' "$root/bin/omarchy-pkg-add" ||
  fail "package helper does not preserve Pacman needed/cache behavior"
if grep -Eq '(/var/cache/pacman|sudo[[:space:]]+pacman|curl|wget)' "$media_script"; then
  fail "Media bypasses the qvOS package lifecycle owner"
fi
pass "Media delegates cached and partial downloads to the qvOS package helper"

[[ -x $media_script ]] || fail "qvCORE Media component is not executable"
if grep -Eq '^[[:space:]]*(gimp|inkscape|krita|kdenlive|obs-studio|audacity|blender)([[:space:]]|$)' "$root/install/omarchy-base.packages"; then
  fail "Media application remains in the base package list"
fi
if grep -Eq '^[[:space:]]+(gimp|inkscape|krita|kdenlive|obs-studio|audacity|blender)([[:space:]\\]|$)' "$root/bin/omarchy-remove-preinstalls"; then
  fail "preinstall cleanup removes a qvCORE Media application"
fi
pass "qvCORE exclusively owns the curated Media application lifecycle"
