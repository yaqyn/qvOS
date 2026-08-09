#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$root/qvcore/desktop/applications/install"
test_root=$(mktemp -d)
test_bin="$test_root/bin"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

run_owner() {
  local home=$1
  shift

  HOME="$home" \
    QVOS_PATH="$root" \
    XDG_STATE_HOME="$home/.local/state" \
    PATH="${QVOS_TEST_PATH:-/usr/bin}" \
    "$owner" "$@"
}

write_legacy_typora() {
  install -m 0644 /dev/stdin "$1" <<'DESKTOP'
[Desktop Entry]
Name=Typora
GenericName=Markdown Editor
Exec=typora --enable-wayland-ime %U
Icon=typora
Type=Application
StartupNotify=true
Categories=Office;WordProcessor;
MimeType=text/markdown;text/x-markdown;

DESKTOP
}

[[ -x $owner ]] || fail "fixed application owner mode"
[[ ! -e $root/applications && ! -L $root/applications ]] ||
  fail "inherited application tree remains"
[[ $(find "$root/qvcore/desktop/applications/hidden" -maxdepth 1 \
  -type f -name '*.desktop' | wc -l) == 34 ]] ||
  fail "hidden application inventory"
if rg -ni '(typora|https?://|--app=|(omarchy|qv)-(launch-webapp|webapp-handler))' \
  "$root/qvcore/desktop/applications" \
  --glob '*.desktop' --glob '*.png'; then
  fail "fixed payload contains bloat or a Web App"
fi

fresh_home="$test_root/fresh-home"
application_dir="$fresh_home/.local/share/applications"
duplicate_icon_dir="$application_dir/icons"
install -d "$duplicate_icon_dir"
write_legacy_typora "$application_dir/typora.desktop"
install -m 0644 "$root/qvcore/desktop/applications/icons/imv.png" \
  "$duplicate_icon_dir/imv.png"
run_owner "$fresh_home"

for desktop in Alacritty imv mpv; do
  cmp -s "$root/qvcore/desktop/applications/$desktop.desktop" \
    "$application_dir/$desktop.desktop" ||
    fail "$desktop desktop publication"
done
while IFS= read -r source; do
  cmp -s "$source" "$application_dir/${source##*/}" ||
    fail "hidden desktop publication: ${source##*/}"
done < <(find "$root/qvcore/desktop/applications/hidden" -maxdepth 1 \
  -type f -name '*.desktop' -print | sort)
cmp -s "$root/qvcore/desktop/applications/icons/imv.png" \
  "$fresh_home/.local/share/icons/hicolor/48x48/apps/imv.png" ||
  fail "hicolor imv icon publication"
managed_state="$fresh_home/.local/state/qvos/desktop/applications.psv"
[[ -f $managed_state && ! -L $managed_state &&
  $(stat -c '%a' -- "$managed_state") == "600" &&
  $(wc -l <"$managed_state") == 39 ]] ||
  fail "private fixed-payload state"
for source in \
  "$root/qvcore/desktop/applications/Alacritty.desktop" \
  "$root/qvcore/desktop/applications/imv.desktop" \
  "$root/qvcore/desktop/applications/mpv.desktop"; do
  grep -Fqx \
    "applications/${source##*/}|$(sha256sum -- "$source" | cut -d' ' -f1)" \
    "$managed_state" || fail "managed application state: ${source##*/}"
done
grep -Fqx \
  "icons/imv.png|$(sha256sum -- "$root/qvcore/desktop/applications/icons/imv.png" | cut -d' ' -f1)" \
  "$managed_state" || fail "managed icon state"
[[ ! -e $application_dir/typora.desktop &&
  ! -e $duplicate_icon_dir/imv.png ]] ||
  fail "exact stale application cleanup"
[[ $(find "$application_dir" -maxdepth 1 -type f -name '*.desktop' | wc -l) == 37 ]] ||
  fail "installed desktop inventory"
[[ $(find "$application_dir" "$fresh_home/.local/share/icons" -type f \
  ! -perm 0644 -print -quit) == "" ]] || fail "installed payload modes"
first_hashes=$(find "$application_dir" "$fresh_home/.local/share/icons" \
  -type f -exec sha256sum {} + | sort)
first_inodes=$(find "$application_dir" "$fresh_home/.local/share/icons" \
  -type f -exec stat -c '%i %n' {} + | sort)
first_state_inode=$(stat -c '%i' -- "$managed_state")
run_owner "$fresh_home"
second_hashes=$(find "$application_dir" "$fresh_home/.local/share/icons" \
  -type f -exec sha256sum {} + | sort)
[[ $second_hashes == "$first_hashes" ]] || fail "idempotent application refresh"
[[ $(find "$application_dir" "$fresh_home/.local/share/icons" \
  -type f -exec stat -c '%i %n' {} + | sort) == "$first_inodes" &&
  $(stat -c '%i' -- "$managed_state") == "$first_state_inode" ]] ||
  fail "idempotent application publication"

legacy_home="$test_root/legacy-home"
legacy_apps="$legacy_home/.local/share/applications"
install -d "$legacy_apps"
printf '[Desktop Entry]\nHidden=true\n' >"$legacy_apps/avahi-discover.desktop"
run_owner "$legacy_home"
cmp -s \
  "$root/qvcore/desktop/applications/hidden/avahi-discover.desktop" \
  "$legacy_apps/avahi-discover.desktop" ||
  fail "legacy managed suppressor upgrade"

modified_home="$test_root/modified-home"
install -d "$modified_home"
run_owner "$modified_home"
modified_apps="$modified_home/.local/share/applications"
modified_state="$modified_home/.local/state/qvos/desktop/applications.psv"
printf 'personal application override\n' >"$modified_apps/Alacritty.desktop"
modified_before=$(find "$modified_apps" "$modified_home/.local/share/icons" \
  -type f -exec sha256sum {} + | sort)
modified_state_before=$(sha256sum -- "$modified_state")
if run_owner "$modified_home" >/dev/null 2>&1; then
  fail "modified managed application accepted"
fi
[[ $(find "$modified_apps" "$modified_home/.local/share/icons" \
  -type f -exec sha256sum {} + | sort) == "$modified_before" &&
  $(sha256sum -- "$modified_state") == "$modified_state_before" ]] ||
  fail "modified managed application preservation"

custom_home="$test_root/custom-home"
custom_apps="$custom_home/.local/share/applications"
install -d "$custom_apps/icons"
printf 'custom Typora\n' >"$custom_apps/typora.desktop"
printf 'custom icon\n' >"$custom_apps/icons/imv.png"
run_owner "$custom_home"
[[ $(<"$custom_apps/typora.desktop") == "custom Typora" &&
  $(<"$custom_apps/icons/imv.png") == "custom icon" ]] ||
  fail "modified stale application preservation"

malformed_state_home="$test_root/malformed-state-home"
malformed_state="$malformed_state_home/.local/state/qvos/desktop/applications.psv"
install -D -m 0600 /dev/stdin "$malformed_state" <<'STATE'
applications/Alacritty.desktop|invalid
STATE
if run_owner "$malformed_state_home" >/dev/null 2>&1; then
  fail "malformed managed application state accepted"
fi
if find "$malformed_state_home/.local/share" -type f -print -quit 2>/dev/null |
  grep -q .; then
  fail "malformed managed application state changed payload"
fi

linked_state_home="$test_root/linked-state-home"
linked_state_target="$test_root/linked-state-target"
install -d "$linked_state_home/.local/state/qvos/desktop"
printf 'external state\n' >"$linked_state_target"
ln -s "$linked_state_target" \
  "$linked_state_home/.local/state/qvos/desktop/applications.psv"
if run_owner "$linked_state_home" >/dev/null 2>&1; then
  fail "linked managed application state accepted"
fi
[[ $(<"$linked_state_target") == "external state" ]] ||
  fail "linked managed application state target changed"

unsafe_home="$test_root/unsafe-home"
outside="$test_root/outside"
install -d "$unsafe_home/.local/share" "$outside"
printf 'preserve\n' >"$outside/value"
ln -s "$outside" "$unsafe_home/.local/share/applications"
if run_owner "$unsafe_home" >/dev/null 2>&1; then
  fail "linked application directory accepted"
fi
[[ $(<"$outside/value") == "preserve" && ! -e $unsafe_home/.local/state ]] ||
  fail "unsafe directory preflight mutated state"

linked_home="$test_root/linked-home"
linked_target="$test_root/linked-target"
install -d "$linked_home/.local/share/applications"
printf 'preserve\n' >"$linked_target"
ln -s "$linked_target" \
  "$linked_home/.local/share/applications/Alacritty.desktop"
if run_owner "$linked_home" >/dev/null 2>&1; then
  fail "linked application destination accepted"
fi
[[ $(<"$linked_target") == "preserve" && ! -e $linked_home/.local/state ]] ||
  fail "unsafe destination preflight mutated state"

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/mv" <<'SCRIPT'
#!/bin/bash
destination=${!#}
if [[ $destination == "$QVOS_TEST_FAIL_DESTINATION" &&
  ! -e $QVOS_TEST_FAILURE_MARKER ]]; then
  touch "$QVOS_TEST_FAILURE_MARKER"
  exit 1
fi
exec /usr/bin/mv "$@"
SCRIPT
rollback_home="$test_root/rollback-home"
rollback_apps="$rollback_home/.local/share/applications"
install -d "$rollback_home"
export QVOS_TEST_PATH="$test_bin:/usr/bin"
export QVOS_TEST_FAIL_DESTINATION="$rollback_apps/imv.desktop"
export QVOS_TEST_FAILURE_MARKER="$test_root/failure-used"
if run_owner "$rollback_home" >/dev/null 2>&1; then
  fail "injected publication failure accepted"
fi
[[ ! -e $rollback_apps/Alacritty.desktop &&
  ! -e $rollback_apps/imv.desktop &&
  ! -e $rollback_apps/mpv.desktop &&
  ! -e $rollback_home/.local/state/qvos/desktop/applications.psv ]] ||
  fail "application publication rollback"

state_failure_home="$test_root/state-failure-home"
install -d "$state_failure_home"
export QVOS_TEST_FAIL_DESTINATION="$state_failure_home/.local/state/qvos/desktop/applications.psv"
export QVOS_TEST_FAILURE_MARKER="$test_root/state-failure-used"
if run_owner "$state_failure_home" >/dev/null 2>&1; then
  fail "injected state publication failure accepted"
fi
if find "$state_failure_home/.local/share" -type f -print -quit | grep -q . ||
  [[ -e $state_failure_home/.local/state/qvos/desktop/applications.psv ]]; then
  fail "state publication failure rollback"
fi
unset QVOS_TEST_PATH QVOS_TEST_FAIL_DESTINATION QVOS_TEST_FAILURE_MARKER

if run_owner "$fresh_home" unexpected >/dev/null 2>&1; then
  fail "unexpected application-owner argument accepted"
fi

printf 'ok - qvOS fixed applications are native, atomic, slim, and Web App free\n'
