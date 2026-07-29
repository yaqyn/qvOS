#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
doctor="$root/qv/codex/doctor"
registry="$root/qv/codex/capabilities.tsv"
qvdev_packages="$root/qv/core/qvdev/packages.tsv"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
capability_bin="$test_root/capability-bin"
runtime="$test_home/.local/share/qvos/codex"
standalone="$test_home/.codex/packages/standalone/releases/test/bin/codex"
base_packages="$test_root/base.packages"

cleanup() {
  [[ -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

"$root/qv/install/packaging/resolve" base >"$base_packages"

registry_rows=$(
  awk -F '\t' '
    /^#/ || NF == 0 { next }
    NF != 4 { exit 1 }
    $2 !~ /^(base|qvdev|project|avoid)$/ { exit 1 }
    seen[$1]++ { exit 1 }
    { count++ }
    END {
      if (count < 80) {
        exit 1
      }
      print count
    }
  ' "$registry"
) || fail "capability registry schema"
((registry_rows >= 80)) || fail "capability registry size"

while IFS=$'\t' read -r command_name layer owner action extra; do
  [[ -n $command_name && $command_name != "#"* ]] || continue
  [[ -z ${extra:-} && -n $action ]] || fail "capability action route"

  if [[ $layer == "base" && $owner == "package:"* ]]; then
    package=${owner#package:}
    grep -Fqx "$package" "$base_packages" ||
      fail "base capability is not manifested: $command_name"
  elif [[ $layer == "base" ]]; then
    [[ $command_name == "codex" && $owner == "direct:openai" ]] ||
      fail "non-package base capability owner: $command_name"
  fi

  if [[ $layer == "qvdev" && $owner == "package:"* ]]; then
    package=${owner#package:}
    awk -F '\t' -v package="$package" '
      $2 == package { found = 1 }
      END { exit !found }
    ' "$qvdev_packages" ||
      fail "qvDEV package capability has no owner: $command_name"
  fi
done <"$registry"

if grep -Eq '^(wrangler|convex|playwright|playwright-cli|ydotool)$' \
  "$base_packages" "$qvdev_packages"; then
  fail "project or avoid capability leaked into qvOS ownership"
fi
qvdev_packages=(
  7zip
  clang
  cmake
  dos2unix
  gdb
  git-lfs
  go-yq
  hyperfine
  just
  lldb
  llvm
  lsof
  ninja
  pacman-contrib
  postgresql-libs
  ruby
  rust
  shellcheck
  shfmt
  strace
  time
  tinyxxd
  valgrind
  zip
)
for package in "${qvdev_packages[@]}"; do
  awk -F '\t' -v package="$package" '$2 == package { found = 1 } END { exit !found }' \
    "$root/qv/core/qvdev/packages.tsv" ||
    fail "qvDEV package boundary: $package"
  if grep -Fqx "$package" "$base_packages"; then
    fail "qvDEV package leaked into base: $package"
  fi
done
if awk -F '\t' '$1 == "aur" { found = 1 } END { exit !found }' \
  "$root/qv/core/qvdev/packages.tsv"; then
  fail "qvDEV requires an AUR package owner"
fi
grep -Fq $'devcontainer\tqvdev\tDev Container CLI\tnpm' \
  "$root/qv/direct/manifest.tsv" ||
  fail "official Dev Container CLI install owner"
grep -Fq $'playwright-cli\tqvdev\tPlaywright CLI\tnpm' \
  "$root/qv/direct/manifest.tsv" ||
  fail "official Playwright CLI install owner"
if rg -q 'omarchy-npx-install playwright' "$root/qv/install/packaging/npx"; then
  fail "Playwright CLI remains in qvOS base packaging"
fi
if grep -Fq 'python@latest' "$root/qv/direct/manifest.tsv"; then
  fail "qvDEV configures a redundant global Python runtime"
fi
pass "capabilities have one layer, owner, and exact route"

install -d \
  "$test_bin" \
  "$capability_bin" \
  "$runtime" \
  "$(dirname -- "$standalone")" \
  "$test_home/.local/bin" \
  "$test_home/.codex/skills/example" \
  "$test_home/.codex/sessions/2026/01/01"
install -m 0755 "$doctor" "$runtime/doctor"
install -m 0644 "$registry" "$runtime/capabilities.tsv"
install -m 0755 "$root/qv/codex/qv" "$test_home/.local/bin/qv"
ln -s /usr/bin/jq "$capability_bin/jq"
printf '[mcp_servers.one]\n[mcp_servers.two]\n' \
  >"$test_home/.codex/config.toml"
printf '# test skill\n' >"$test_home/.codex/skills/example/SKILL.md"
printf '{"test":true}\n' \
  >"$test_home/.codex/sessions/2026/01/01/rollout-test.jsonl"

install -m 0755 /dev/stdin "$standalone" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case ${1:-} in
--version)
  printf 'codex-cli 9.9.9\n'
  ;;
doctor)
  [[ -z ${CODEX_MANAGED_BY_NPM:-} ]]
  [[ -z ${CODEX_MANAGED_PACKAGE_ROOT:-} ]]
  [[ ${2:-} == "--json" ]]
  printf '%s\n' \
    '{"schemaVersion":1,"overallStatus":"ok","checks":{"auth.credentials":{"id":"auth.credentials","status":"ok","summary":"auth is configured"},"mcp.config":{"id":"mcp.config","status":"ok","summary":"MCP configuration is locally consistent"}}}'
  ;;
sandbox)
  [[ -z ${CODEX_MANAGED_BY_NPM:-} ]]
  [[ -z ${CODEX_MANAGED_PACKAGE_ROOT:-} ]]
  [[ ${2:-} == "/usr/bin/true" ]]
  ;;
*)
  exit 1
  ;;
esac
SCRIPT
ln -s "$standalone" "$test_home/.local/bin/codex"

while IFS=$'\t' read -r command_name layer _ _; do
  [[ $layer == "base" ]] || continue
  [[ $command_name != /* ]] || continue
  [[ $command_name != "gh" ]] || continue
  [[ $command_name != "jq" ]] || continue
  [[ $command_name != "codex" ]] || continue
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
done <"$registry"
install -m 0755 /dev/stdin "$capability_bin/git" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

while IFS=$'\t' read -r command_name layer _ _; do
  [[ $layer == "qvdev" ]] || continue
  [[ $command_name != /* ]] || continue
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
done <"$registry"

install -m 0755 /dev/stdin "$test_bin/gh" <<'SCRIPT'
#!/bin/bash
[[ $1 == "auth" ]]
[[ $2 == "status" ]]
[[ $3 == "--hostname" ]]
[[ $4 == "github.com" ]]
SCRIPT

run_doctor() {
  CODEX_MANAGED_BY_NPM=1 \
    CODEX_MANAGED_PACKAGE_ROOT="/private/test/package" \
    HOME="$test_home" \
    CODEX_HOME="$test_home/.codex" \
    WAYLAND_DISPLAY=wayland-test \
    HYPRLAND_INSTANCE_SIGNATURE=hyprland-test \
    QVOS_CODEX_COMMAND_PATH="$test_home/.local/bin:$test_bin:$capability_bin" \
    PATH="$test_home/.local/bin:$test_bin:/usr/bin" \
    "$test_home/.local/bin/qv" codex doctor "$@"
}

report=$(run_doctor --json)
base_total=$(awk -F '\t' '$1 !~ /^#/ && $2 == "base" { count++ } END { print count + 0 }' "$registry")
qvdev_total=$(awk -F '\t' '$1 !~ /^#/ && $2 == "qvdev" { count++ } END { print count + 0 }' "$registry")
foundation_total=$((base_total + 3))
jq -e \
  --argjson base_total "$base_total" \
  --argjson qvdev_total "$qvdev_total" \
  --argjson foundation_total "$foundation_total" '
  .schema_version == 1
  and .status == "ready"
  and .foundation.ready == true
  and .foundation.ready_count == $foundation_total
  and .foundation.total == $foundation_total
  and .foundation.base_capabilities.ready == $base_total
  and .foundation.base_capabilities.total == $base_total
  and .installation.owner == "openai-standalone"
  and .installation.version == "9.9.9"
  and .codex_doctor.status == "ok"
  and .sandbox.ready == true
  and .qvdev.status == "ready"
  and .qvdev.ready == $qvdev_total
  and .qvdev.total == $qvdev_total
  and (has("profiles") | not)
  and .wayland.session == true
  and .wayland.hyprland_session == true
  and .credentials.github == true
  and .extensions.mcp_configured_count == 2
  and .extensions.skill_count == 1
  and .session_storage.rollout_files == 1
  and .session_storage.retention == "informational-only"
  and any(
    .shadowed_commands[];
    .command == "git" and (.paths | length) == 2
  )
' <<<"$report" >/dev/null ||
  fail "ready doctor JSON contract"
if grep -Fq '/private/test/package' <<<"$report"; then
  fail "doctor exposed inherited package provenance"
fi
run_doctor --check >/dev/null ||
  fail "ready doctor check status"
pass "doctor keeps shadowed command paths informational"

mv "$test_bin/dig" "$test_bin/dig.missing"
missing_report=$(run_doctor --json)
jq -e '
  .status == "missing"
  and .foundation.ready == false
  and any(
    .foundation.base_capabilities.missing[];
    .command == "dig" and .action == "omarchy pkg add bind"
  )
' <<<"$missing_report" >/dev/null ||
  fail "missing base action route"
set +e
run_doctor --check >/dev/null
check_status=$?
set -e
((check_status == 1)) || fail "missing-capability doctor check status"
pass "doctor reports the exact action for a missing capability without mutating state"

mv "$runtime/doctor" "$runtime/doctor.missing"
set +e
missing_output=$(run_doctor --json 2>&1)
missing_status=$?
set -e
((missing_status == 1)) || fail "missing Codex runtime status"
grep -Fq 'qvOS Codex doctor runtime is unavailable' <<<"$missing_output" ||
  fail "missing Codex runtime explanation"
pass "qv codex doctor uses the installed source-independent runtime"
