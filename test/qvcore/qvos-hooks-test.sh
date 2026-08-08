#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
test_home="$test_root/home"
legacy="$test_home/.config/omarchy/hooks"
canonical="$test_home/.config/qvos/hooks"
autostart="$test_home/.config/hypr/autostart.conf"
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

install -d "$legacy/font-set.d" "$legacy/post-update.d" "${autostart%/*}"
install -m 0700 /dev/stdin "$legacy/font-set" <<'SCRIPT'
#!/bin/bash
printf 'main:%s\n' "$*" >>"$QVOS_HOOK_TEST_LOG"
SCRIPT
install -m 0700 /dev/stdin "$legacy/font-set.d/20-second" <<'SCRIPT'
#!/bin/bash
printf 'second:%s\n' "$*" >>"$QVOS_HOOK_TEST_LOG"
SCRIPT
install -m 0700 /dev/stdin "$legacy/font-set.d/10-first" <<'SCRIPT'
#!/bin/bash
printf 'first:%s\n' "$*" >>"$QVOS_HOOK_TEST_LOG"
SCRIPT
install -m 0600 /dev/stdin "$legacy/font-set.d/ignored.sample" <<'SCRIPT'
#!/bin/bash
exit 99
SCRIPT
install -m 0700 /dev/stdin "$legacy/post-update" <<'SCRIPT'
#!/bin/bash
printf 'custom-update\n' >>"$QVOS_HOOK_TEST_LOG"
SCRIPT
install -m 0644 "$root/qvcore/install/post-update-hook" \
  "$legacy/post-update.d/qvos-base"
install -m 0644 "$root/qvcore/direct/post-update-hook" \
  "$legacy/post-update.d/qvos-direct-tools"
install -m 0644 "$root/qvcore/waybar/post-update-hook" \
  "$legacy/post-update.d/qvos-waybar-overrides"
printf '%s\n' \
  'exec-once = sleep 2 && omarchy-hook post-boot' \
  'exec-once = qv-first-run' >"$autostart"

run_reconcile >/dev/null
[[ -d $canonical && ! -L $canonical && ! -e $legacy ]] ||
  fail "legacy hook tree was not adopted atomically"
[[ $(stat -c '%a' "$canonical") == "700" ]] || fail "canonical hook root mode"
for retired in qvos-base qvos-direct-tools qvos-waybar-overrides; do
  [[ ! -e $canonical/post-update.d/$retired ]] ||
    fail "former managed hook remains: $retired"
done
[[ -x $canonical/font-set && -x $canonical/post-update ]] ||
  fail "custom hooks were not preserved"
grep -Fqx 'exec-once = sleep 2 && qv-hook post-boot' "$autostart" ||
  fail "post-boot route was not promoted"
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
printf 'ok - legacy custom hooks migrate without retaining qvOS system-job copies\n'

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

dual_home="$test_root/dual-home"
install -d "$dual_home/.config/qvos/hooks" "$dual_home/.config/omarchy/hooks"
if HOME="$dual_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" >/dev/null 2>&1; then
  fail "ambiguous dual hook roots were merged"
fi
[[ -d $dual_home/.config/qvos/hooks && -d $dual_home/.config/omarchy/hooks ]] ||
  fail "ambiguous roots were changed"

modified_home="$test_root/modified-home"
modified_legacy="$modified_home/.config/omarchy/hooks"
install -d "$modified_legacy/post-update.d"
printf '%s\n' '# user modified' >"$modified_legacy/post-update.d/qvos-base"
if HOME="$modified_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" >/dev/null 2>&1; then
  fail "modified former managed hook was deleted"
fi
[[ -f $modified_legacy/post-update.d/qvos-base &&
  ! -e $modified_home/.config/qvos/hooks ]] ||
  fail "modified former managed hook was not preserved before migration"

link_home="$test_root/link-home"
install -d "$link_home/.config/qvos"
ln -s "$test_root/unsafe" "$link_home/.config/qvos/hooks"
if HOME="$link_home" QVOS_PATH="$root" \
  "$root/qvcore/hooks/reconcile" >/dev/null 2>&1; then
  fail "symbolic-link hook root was accepted"
fi
[[ ! -e $test_root/unsafe ]] || fail "symbolic-link hook root was followed"
printf 'ok - reconciliation fails closed on ambiguous, modified, and linked state\n'
