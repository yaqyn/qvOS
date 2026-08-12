#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
fixture="$test_root/source"
test_home="$test_root/home"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$fixture/bin" "$fixture/qvcore/software" "$test_bin"
for route in \
  omarchy-install-dropbox \
  omarchy-install-once \
  omarchy-install-tailscale \
  qv-install-dropbox \
  qv-install-once \
  qv-install-tailscale; do
  install -m 0755 "$root/bin/$route" "$fixture/bin/$route"
done
for owner in dropbox-install once-install tailscale-install; do
  install -m 0755 "$root/qvcore/software/$owner" \
    "$fixture/qvcore/software/$owner"
done

install -m 0755 /dev/stdin "$test_bin/qv-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg-add:<%s>\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo:' >>"$QVOS_TEST_ACTION_LOG"
printf '<%s>' "$@" >>"$QVOS_TEST_ACTION_LOG"
printf '\n' >>"$QVOS_TEST_ACTION_LOG"
STUB
install -m 0755 /dev/stdin "$test_bin/once" <<'STUB'
#!/bin/bash
printf 'once:<%s>\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
if [[ ${1:-} == "list" ]]; then
  [[ ${QVOS_TEST_ONCE_LIST_FAIL:-0} != "1" ]] || exit 7
  printf '%s' "${QVOS_TEST_ONCE_APPS:-}"
elif [[ ${QVOS_TEST_ONCE_TUI_FAIL:-0} == "1" ]]; then
  exit 8
fi
STUB
for unexpected in uwsm-app qv-webapp-install omarchy-webapp-install; do
  install -m 0755 /dev/stdin "$test_bin/$unexpected" <<'STUB'
#!/bin/bash
printf 'unexpected:%s:<%s>\n' "${0##*/}" "$*" >>"$QVOS_TEST_ACTION_LOG"
STUB
done

touch "$action_log"
run_installer() {
  HOME="$test_home" \
    QVOS_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$@"
}

for route in qv-install-dropbox omarchy-install-dropbox; do
  run_installer "$fixture/bin/$route" >/dev/null
done
(( $(grep -Fxc \
  'pkg-add:<dropbox-cli python-gpgme libayatana-appindicator>' \
  "$action_log") == 2 )) || fail "Dropbox minimal package owner"
if grep -Fq 'unexpected:' "$action_log"; then
  fail "Dropbox detached application or Web App launch"
fi

: >"$action_log"
for route in qv-install-tailscale omarchy-install-tailscale; do
  run_installer "$fixture/bin/$route" >/dev/null
done
(( $(grep -Fxc 'pkg-add:<tailscale>' "$action_log") == 2 )) ||
  fail "Tailscale package owner"
(( $(grep -Fxc 'sudo:<systemctl><enable><--now><tailscaled.service>' \
  "$action_log") == 2 )) || fail "Tailscale service owner"
(( $(grep -Fxc \
  'sudo:<tailscale><up><--accept-dns=false><--accept-routes=false>' \
  "$action_log") == 2 )) ||
  fail "Tailscale safe authentication boundary"
if rg -q 'accept-(dns|routes)=true|webapp|unexpected:' "$action_log"; then
  fail "Tailscale implicit route or Web App mutation"
fi

: >"$action_log"
for route in qv-install-once omarchy-install-once; do
  run_installer "$fixture/bin/$route" >/dev/null
done
(( $(grep -Fxc 'pkg-add:<once-bin>' "$action_log") == 2 )) ||
  fail "ONCE package owner"
(( $(grep -Fxc 'sudo:<systemctl><enable><--now><once-background.service>' \
  "$action_log") == 2 )) || fail "ONCE service owner"
(( $(grep -Fxc 'once:<>' "$action_log") == 2 )) || fail "ONCE TUI handoff"
(( $(grep -Fxc 'once:<list --namespace once>' "$action_log") == 2 )) ||
  fail "ONCE empty inventory verification"
(( $(grep -Fxc \
  'sudo:<systemctl><disable><--now><once-background.service>' \
  "$action_log") == 2 )) || fail "ONCE idle service cleanup"

: >"$action_log"
QVOS_TEST_ONCE_APPS='deployed-app' \
  run_installer "$fixture/bin/qv-install-once" >/dev/null
if grep -Fq 'sudo:<systemctl><disable>' "$action_log"; then
  fail "ONCE stopped a service with a deployed application"
fi

: >"$action_log"
set +e
QVOS_TEST_ONCE_TUI_FAIL=1 \
  run_installer "$fixture/bin/qv-install-once" >/dev/null
once_failure_status=$?
set -e
((once_failure_status == 8)) || fail "ONCE TUI failure status preservation"
grep -Fqx 'sudo:<systemctl><disable><--now><once-background.service>' \
  "$action_log" || fail "ONCE failed TUI idle service cleanup"

: >"$action_log"
set +e
QVOS_TEST_ONCE_TUI_FAIL=1 QVOS_TEST_ONCE_LIST_FAIL=1 \
  run_installer "$fixture/bin/qv-install-once" >/dev/null
once_failure_status=$?
set -e
((once_failure_status == 8)) || fail "ONCE inventory failure status preservation"
if grep -Fq 'sudo:<systemctl><disable>' "$action_log"; then
  fail "ONCE disabled its service without proving an empty inventory"
fi

: >"$action_log"
for route in qv-install-dropbox qv-install-tailscale qv-install-once; do
  if run_installer "$fixture/bin/$route" unexpected >/dev/null 2>&1; then
    fail "$route accepted unexpected arguments"
  fi
done
[[ ! -s $action_log ]] || fail "invalid optional-service input reached mutation"

for route in dropbox once tailscale; do
  grep -Fq "|qv-install-$route" "$root/qvcore/menu/software-installers.psv" ||
    fail "$route native menu route"
done
if rg -n 'omarchy-install-(dropbox|once|tailscale)' \
  "$root/qvcore/menu/software-installers.psv"; then
  fail "optional-service menu compatibility route"
fi

"$root/qvcore/software/check"
printf 'ok - optional services are native, minimal, and explicit\n'
