#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
canonical="$test_home/.config/qvos/hooks"
events="$test_root/events"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_reconcile() {
  HOME="$test_home" QVOS_PATH="$root" "$root/qvcore/hooks/reconcile" "$@"
}

install -d "$canonical/font-set.d" "$canonical/post-update.d"
install -m 0700 /dev/stdin "$canonical/font-set" <<'SCRIPT'
#!/bin/bash
printf 'main:%s\n' "$*" >>"$QVOS_HOOK_TEST_LOG"
SCRIPT
install -m 0700 /dev/stdin "$canonical/font-set.d/20-second" <<'SCRIPT'
#!/bin/bash
printf 'second:%s\n' "$*" >>"$QVOS_HOOK_TEST_LOG"
SCRIPT
install -m 0700 /dev/stdin "$canonical/font-set.d/10-first" <<'SCRIPT'
#!/bin/bash
printf 'first:%s\n' "$*" >>"$QVOS_HOOK_TEST_LOG"
SCRIPT
install -m 0600 /dev/stdin "$canonical/font-set.d/ignored.sample" <<'SCRIPT'
#!/bin/bash
exit 99
SCRIPT
install -m 0700 /dev/stdin "$canonical/post-update" <<'SCRIPT'
#!/bin/bash
printf 'custom-update\n' >>"$QVOS_HOOK_TEST_LOG"
SCRIPT

run_reconcile >/dev/null
[[ -d $canonical && ! -L $canonical ]] || fail "native hook root"
[[ $(stat -c '%a' "$canonical") == "700" ]] || fail "canonical hook root mode"
[[ -x $canonical/font-set && -x $canonical/post-update ]] ||
  fail "custom hooks were not preserved"
for sample in \
  battery-low.d/play-warning-sound.sample \
  font-set.d/show-font-notification.sample \
  post-boot.d/weather.sample \
  post-update.d/show-update-notification.sample \
  theme-set.d/show-theme-notification.sample; do
  cmp -s "$root/qvcore/hooks/defaults/$sample" "$canonical/$sample" ||
    fail "native hook sample was not installed: $sample"
done
run_reconcile --check >/dev/null
printf 'ok - native custom hooks preserve user automation and seed missing samples\n'

modified_sample_home="$test_root/modified-sample-home"
modified_sample_root="$modified_sample_home/.config/qvos/hooks"
install -d "$modified_sample_root/battery-low.d"
printf 'custom nested sample\n' \
  >"$modified_sample_root/battery-low.d/play-warning-sound.sample"
printf 'custom retired sample\n' >"$modified_sample_root/post-update.sample"
HOME="$modified_sample_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" >/dev/null
grep -Fqx 'custom nested sample' \
  "$modified_sample_root/battery-low.d/play-warning-sound.sample" ||
  fail "modified nested hook sample preservation"
grep -Fqx 'custom retired sample' "$modified_sample_root/post-update.sample" ||
  fail "modified retired hook sample preservation"
HOME="$modified_sample_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" --check >/dev/null
printf 'ok - modified hook samples remain user-owned and inert\n'

: >"$events"
HOME="$test_home" QVOS_PATH="$root" QVOS_HOOK_TEST_LOG="$events" \
  "$root/bin/qv-hook" font-set "MesloLGL Nerd Font"
expected=$'main:MesloLGL Nerd Font\nfirst:MesloLGL Nerd Font\nsecond:MesloLGL Nerd Font'
[[ $(<"$events") == "$expected" ]] ||
  fail "hook arguments or deterministic execution order"
: >"$events"
HOME="$test_home" QVOS_PATH="$root" QVOS_HOOK_TEST_LOG="$events" \
  "$root/bin/omarchy-hook" post-update
[[ $(<"$events") == "custom-update" ]] || fail "compatibility hook adapter"
printf 'ok - native and compatibility routes share deterministic custom execution\n'

install -m 0700 /dev/stdin "$canonical/font-set.d/15-failure" <<'SCRIPT'
#!/bin/bash
printf 'failure:%s\n' "$*" >>"$QVOS_HOOK_TEST_LOG"
exit 9
SCRIPT
: >"$events"
set +e
HOME="$test_home" QVOS_PATH="$root" QVOS_HOOK_TEST_LOG="$events" \
  "$root/bin/qv-hook" font-set exact argument >/dev/null 2>&1
hook_status=$?
set -e
((hook_status == 1)) || fail "hook failure aggregate status"
expected=$'main:exact argument\nfirst:exact argument\nfailure:exact argument\nsecond:exact argument'
[[ $(<"$events") == "$expected" ]] || fail "hook failure stopped remaining hooks"
rm -f -- "$canonical/font-set.d/15-failure"
printf 'ok - hook failures are truthful without suppressing later custom hooks\n'

source_hook="$test_home/my-hook"
printf '%s\n' '#!/bin/bash' 'exit 0' >"$source_hook"
chmod 0600 "$source_hook"
HOME="$test_home" QVOS_PATH="$root" \
  "$root/bin/qv-hook-install" theme-set "$source_hook" >/dev/null
installed="$canonical/theme-set.d/my-hook"
[[ -f $installed && ! -L $installed && $(stat -c '%a' "$installed") == "700" ]] ||
  fail "private installed hook"
HOME="$test_home" QVOS_PATH="$root" \
  "$root/bin/omarchy-hook-install" theme-set "$source_hook" >/dev/null
printf '%s\n' '#!/bin/bash' 'exit 7' >"$source_hook"
if HOME="$test_home" QVOS_PATH="$root" \
  "$root/bin/qv-hook-install" theme-set "$source_hook" >/dev/null 2>&1; then
  fail "different installed hook was overwritten"
fi
grep -Fqx 'exit 0' "$installed" || fail "hook collision changed existing content"
printf 'ok - hook installation is private, atomic, idempotent, and collision-safe\n'

historical_home="$test_root/historical-home"
historical_root="$historical_home/.config/omarchy/hooks"
historical_hook="$historical_root/post-update.d/personal"
install -d "${historical_hook%/*}"
printf '%s\n' '# personal historical hook' >"$historical_hook"
if HOME="$historical_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" --check >/dev/null 2>&1; then
  fail "historical root satisfied native reconciliation check"
fi
HOME="$historical_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" >/dev/null
grep -Fqx '# personal historical hook' "$historical_hook" ||
  fail "historical hook root was modified"
[[ -d $historical_home/.config/qvos/hooks ]] ||
  fail "native root was not created independently"

link_home="$test_root/link-home"
install -d "$link_home/.config/qvos"
ln -s "$test_root/unsafe" "$link_home/.config/qvos/hooks"
if HOME="$link_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" >/dev/null 2>&1; then
  fail "symbolic-link hook root was accepted"
fi
[[ ! -e $test_root/unsafe ]] || fail "symbolic-link hook root was followed"
printf 'ok - reconciliation ignores historical roots and rejects linked native state\n'
