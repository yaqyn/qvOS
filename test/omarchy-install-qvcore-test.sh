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

install -m 0755 /dev/stdin "$test_omarchy_path/qv/core/proton.sh" <<'SCRIPT'
#!/bin/bash
printf 'install-proton\n' >>"$QVOS_TEST_ACTION_LOG"
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
    QVOS_TEST_GH_AUTH="${QVOS_TEST_GH_AUTH:-0}" \
    HOME="$test_root" \
    OMARCHY_PATH="$test_omarchy_path" \
    PATH="$test_bin:/usr/bin" \
    "$command_path" "$@"
}

: >"$action_log"
run_qvcore >/dev/null
expected_actions=$'setup-dns\tWARP\ninstall-browser\tbrave-origin\ndefault-browser\tbrave-origin\ncurl\t-fsSL https://chatgpt.com/codex/install.sh\ncurl\t-fsSL https://api.github.com/repos/openai/codex/releases/latest\nstandalone\t1\t'"$test_root/.local/bin"$'\ninstall-proton\ninstall-gaming-steam'
[[ $(<"$action_log") == "$expected_actions" ]] || fail "complete qvCORE route order"
[[ $("$test_root/.local/bin/codex" --version) == "codex-cli test" ]] || fail "standalone Codex command"
pass "qvCORE installs WARP, Brave Origin, standalone Codex, Proton, and Steam"

declare -A expected_component_actions=(
  [warp]=$'setup-dns\tWARP'
  [brave-origin]=$'install-browser\tbrave-origin\ndefault-browser\tbrave-origin'
  [codex]=$'curl\t-fsSL https://chatgpt.com/codex/install.sh\ncurl\t-fsSL https://api.github.com/repos/openai/codex/releases/latest\nstandalone\t1\t'"$test_root/.local/bin"
  [proton]=$'install-proton'
)

for component in warp brave-origin codex proton; do
  : >"$action_log"
  run_qvcore "$component" >/dev/null
  [[ $(<"$action_log") == "${expected_component_actions[$component]}" ]] || fail "$component component route"
done
pass "qvCORE components are independently rerunnable"

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

[[ ! -e $root/qv/core/steam.sh ]] || fail "redundant qvCORE Steam wrapper"
grep -Fqx '  omarchy-install-gaming-steam' "$command_path" || fail "complete profile Steam route"
pass "Steam reuses its complete gaming installer without a wrapper"
