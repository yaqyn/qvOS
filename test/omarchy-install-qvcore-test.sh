#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command_path="$root/bin/omarchy-install-qvcore"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
test_omarchy_path="$test_root/omarchy"
action_log="$test_root/actions"

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

install -d "$test_bin" "$test_omarchy_path/qv/core"
ln -s "$root/qv/core/warp.sh" "$test_omarchy_path/qv/core/warp.sh"
ln -s "$root/qv/core/brave-origin.sh" "$test_omarchy_path/qv/core/brave-origin.sh"
ln -s "$root/qv/core/codex.sh" "$test_omarchy_path/qv/core/codex.sh"
ln -s "$root/qv/core/steam.sh" "$test_omarchy_path/qv/core/steam.sh"

install -m 0755 /dev/stdin "$test_omarchy_path/qv/core/dev.sh" <<'SCRIPT'
#!/bin/bash
if [[ ${QVOS_TEST_DEV_CANCEL:-0} == "1" ]]; then
  printf 'cancel-dev\n' >>"$QVOS_TEST_ACTION_LOG"
  echo "Devel changes canceled; no components were modified."
  exit 130
fi
printf 'install-dev\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_omarchy_path/qv/core/proton.sh" <<'SCRIPT'
#!/bin/bash
printf 'install-proton\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_omarchy_path/qv/core/media.sh" <<'SCRIPT'
#!/bin/bash
printf 'install-media\n' >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-install-browser" <<'SCRIPT'
#!/bin/bash
printf 'install-browser\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-default-browser" <<'SCRIPT'
#!/bin/bash
printf 'default-browser\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-setup-dns" <<'SCRIPT'
#!/bin/bash
printf 'setup-dns\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-install-gaming-steam" <<'SCRIPT'
#!/bin/bash
printf 'install-gaming-steam\n' >>"$QVOS_TEST_ACTION_LOG"
if [[ ${QVOS_TEST_STEAM_FAIL:-0} == "1" ]]; then
  exit 1
fi
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ $1 == "gh" && ${QVOS_TEST_GH_AUTH:-0} == "1" ]]
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'package\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
case ${QVOS_TEST_AUDIO_STACK:-pipewire} in
pipewire)
  [[ $1 == "pipewire-jack" ]]
  ;;
jack2)
  [[ $1 == "jack2" ]]
  ;;
*)
  exit 1
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/curl" <<'SCRIPT'
#!/bin/bash
printf 'curl\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"

if [[ $* == *"https://api.github.com/"* ]]; then
  printf '{"tag_name":"rust-v0.145.0"}\n'
  exit 0
fi

printf '%s\n' \
  '#!/bin/bash' \
  'curl -fsSL https://api.github.com/repos/openai/codex/releases/latest >/dev/null' \
  'printf "standalone\t%s\t%s\n" "$CODEX_NON_INTERACTIVE" "$CODEX_INSTALL_DIR" >>"$QVOS_TEST_ACTION_LOG"' \
  'install -d "$CODEX_INSTALL_DIR"' \
  'printf "#!/bin/bash\nprintf \"codex-cli test\\n\"\n" >"$CODEX_INSTALL_DIR/codex"' \
  'chmod 0755 "$CODEX_INSTALL_DIR/codex"'
SCRIPT

install -m 0755 /dev/stdin "$test_bin/gh" <<'SCRIPT'
#!/bin/bash
case $1 in
auth)
  [[ ${QVOS_TEST_GH_AUTH:-0} == "1" ]]
  ;;
api)
  printf 'gh\t%s\n' "$*" >>"$QVOS_TEST_ACTION_LOG"
  printf '{"tag_name":"rust-v0.145.0"}\n'
  ;;
esac
SCRIPT

run_qvcore() {
  QVOS_TEST_ACTION_LOG="$action_log" \
    QVOS_TEST_AUDIO_STACK="${QVOS_TEST_AUDIO_STACK:-pipewire}" \
    QVOS_TEST_DEV_CANCEL="${QVOS_TEST_DEV_CANCEL:-0}" \
    QVOS_TEST_GH_AUTH="${QVOS_TEST_GH_AUTH:-0}" \
    QVOS_TEST_STEAM_FAIL="${QVOS_TEST_STEAM_FAIL:-0}" \
    HOME="$test_root" \
    OMARCHY_PATH="$test_omarchy_path" \
    PATH="$test_bin:/usr/bin" \
    "$command_path" "$@"
}

: >"$action_log"
run_qvcore >/dev/null
expected_steam_packages="dbus git gnutls lib32-gnutls base-devel gtk3 lib32-gtk3 python-google-auth python-protobuf"
expected_steam_packages+=" libpulse lib32-libpulse alsa-lib lib32-alsa-lib alsa-utils alsa-plugins lib32-alsa-plugins"
expected_steam_packages+=" giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap openal lib32-openal"
expected_steam_packages+=" libxcomposite lib32-libxcomposite libxinerama lib32-libxinerama libgcrypt lib32-libgcrypt"
expected_steam_packages+=" libgpg-error lib32-libgpg-error ncurses lib32-ncurses mpg123 lib32-mpg123"
expected_steam_packages+=" libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite libva lib32-libva"
expected_steam_packages+=" gst-plugins-base-libs sdl2-compat lib32-sdl2-compat v4l-utils lib32-v4l-utils"
expected_steam_packages+=" vulkan-icd-loader lib32-vulkan-icd-loader ocl-icd lib32-ocl-icd libxslt lib32-libxslt"
expected_steam_packages+=" cups samba lib32-mesa gamescope mangohud lib32-mangohud gamemode lib32-gamemode"
expected_steam_packages+=" wine goverlay lib32-pipewire-jack"
expected_steam_actions=$'install-gaming-steam\npackage\t'"$expected_steam_packages"
expected_actions=$'setup-dns\tWARP\ninstall-browser\tbrave-origin\ndefault-browser\tbrave-origin\ninstall-dev\ncurl\t-fsSL https://chatgpt.com/codex/install.sh\ncurl\t-fsSL https://api.github.com/repos/openai/codex/releases/latest\nstandalone\t1\t'"$test_root/.local/bin"$'\ninstall-proton\n'"$expected_steam_actions"$'\ninstall-media'
[[ $(<"$action_log") == "$expected_actions" ]] || fail "complete qvCORE route order"
[[ $("$test_root/.local/bin/codex" --version) == "codex-cli test" ]] || fail "standalone Codex command"
pass "qvCORE installs WARP, Brave, Devel, standalone Codex, Proton, Steam, and Media"

declare -A expected_component_actions=(
  [warp]=$'setup-dns\tWARP'
  [brave-origin]=$'install-browser\tbrave-origin\ndefault-browser\tbrave-origin'
  [dev]=$'install-dev'
  [codex]=$'curl\t-fsSL https://chatgpt.com/codex/install.sh\ncurl\t-fsSL https://api.github.com/repos/openai/codex/releases/latest\nstandalone\t1\t'"$test_root/.local/bin"
  [proton]=$'install-proton'
  [steam]="$expected_steam_actions"
  [media]=$'install-media'
)

for component in warp brave-origin dev codex proton steam media; do
  : >"$action_log"
  run_qvcore "$component" >/dev/null
  [[ $(<"$action_log") == "${expected_component_actions[$component]}" ]] || fail "$component component route"
done
pass "qvCORE components are independently rerunnable"

: >"$action_log"
QVOS_TEST_AUDIO_STACK=jack2 run_qvcore steam >/dev/null
expected_jack2_actions=${expected_steam_actions/%lib32-pipewire-jack/lib32-jack2}
[[ $(<"$action_log") == "$expected_jack2_actions" ]] || fail "Steam JACK2 dependency"

: >"$action_log"
QVOS_TEST_AUDIO_STACK=none run_qvcore steam >/dev/null
expected_no_jack_actions=${expected_steam_actions% lib32-pipewire-jack}
[[ $(<"$action_log") == "$expected_no_jack_actions" ]] || fail "Steam without a JACK provider"
pass "Steam adds only the matching 32-bit JACK dependency"

: >"$action_log"
set +e
QVOS_TEST_STEAM_FAIL=1 run_qvcore steam >/dev/null 2>&1
steam_failure_status=$?
set -e
((steam_failure_status != 0)) || fail "failed Steam installer succeeds"
[[ $(<"$action_log") == "install-gaming-steam" ]] || fail "dependencies run after Steam failure"
pass "Steam failure stops before gaming dependency installation"

: >"$action_log"
set +e
cancel_output=$(QVOS_TEST_DEV_CANCEL=1 run_qvcore 2>&1)
cancel_status=$?
set -e
((cancel_status == 130)) || fail "Devel cancellation status propagation"
expected_cancel_actions=$'setup-dns\tWARP\ninstall-browser\tbrave-origin\ndefault-browser\tbrave-origin\ncancel-dev'
[[ $(<"$action_log") == "$expected_cancel_actions" ]] ||
  fail "complete profile stops after Devel cancellation"
if grep -Fq 'qvCORE is ready.' <<<"$cancel_output"; then
  fail "canceled complete profile reports ready"
fi
pass "Devel cancellation stops the complete qvCORE profile cleanly"

: >"$action_log"
QVOS_TEST_GH_AUTH=1 run_qvcore codex >/dev/null
expected_authenticated_actions=$'curl\t-fsSL https://chatgpt.com/codex/install.sh\ngh\tapi repos/openai/codex/releases/latest\nstandalone\t1\t'"$test_root/.local/bin"
[[ $(<"$action_log") == "$expected_authenticated_actions" ]] || fail "authenticated Codex release metadata route"
pass "Codex release metadata reuses gh authentication without exposing its token"

: >"$action_log"
if run_qvcore unknown >/dev/null 2>&1; then
  fail "unknown qvCORE component succeeds"
fi
[[ ! -s $action_log ]] || fail "unknown qvCORE component performs actions"
pass "unknown qvCORE components fail without side effects"

if grep -RqsF '@openai/codex' "$root/install"; then
  fail "Codex remains in the base installation"
fi
grep -Fq 'https://chatgpt.com/codex/install.sh' "$root/qv/core/codex.sh" || fail "official Codex installer"
if grep -Eq 'gh auth token|Authorization:' "$root/qv/core/codex.sh"; then
  fail "Codex installer exposes GitHub credentials"
fi
if grep -Fq '.local/bin/codex' "$root/bin/omarchy-remove-preinstalls"; then
  fail "preinstall cleanup removes optional Codex"
fi
pass "Codex is owned only by qvCORE and uses OpenAI's standalone installer"

[[ -x $root/qv/core/steam.sh ]] || fail "qvCORE Steam component"
grep -Fqx 'omarchy-install-gaming-steam' "$root/qv/core/steam.sh" || fail "Omarchy Steam delegation"
if grep -Eq '^[[:space:]]+(lib32-gst-plugins-base-libs|(lib32-)?sdl2|(lib32-)?opencl-icd-loader|(lib32-)?vulkan-radeon)$' "$root/qv/core/steam.sh"; then
  fail "qvCORE Steam contains an uncurated Linutil package"
fi
pass "Steam delegates first, then installs the curated gaming dependencies"
