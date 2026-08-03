#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
runtime="$test_root/direct"
log="$test_root/actions.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

manifest_count=$(
  awk -F '\t' '
    /^#/ || NF == 0 { next }
    NF != 9 { exit 1 }
    $2 !~ /^(devel|proton)$/ { exit 1 }
    $4 !~ /^(mise|github|uv-tool|npm|pass|proton-drive)$/ { exit 1 }
    seen[$1]++ { exit 1 }
    { count++ }
    END { if (count < 20) exit 1; print count }
  ' "$root/qvcore/direct/manifest.tsv"
) || fail "direct-tool manifest schema"
((manifest_count >= 20)) || fail "direct-tool manifest inventory"
[[ $("$root/qvcore/direct/tool" list-scope proton) == $'pass-cli\nproton-drive' ]] ||
  fail "Proton direct-tool inventory"
expected_devel=$'node\nbun\nuv\ngo\nmkcert\nhurl\nsupabase\ninfisical\ncloudflared\nsentry-cli\nact\nsops\nage\ngitleaks\nosv-scanner\nsemgrep\ndevcontainer\nplaywright-cli'
[[ $("$root/qvcore/direct/tool" list-scope devel) == "$expected_devel" ]] ||
  fail "Devel direct-tool inventory"
grep -Fqx $'playwright-cli\tdevel\tPlaywright CLI\tnpm\tplaywright-cli\t@playwright/cli\t-\t-\t-' \
  "$root/qvcore/direct/manifest.tsv" ||
  fail "Playwright CLI direct-tool ownership"
grep -Fqx $'pass-cli\tproton\tProton Pass CLI\tpass\tpass-cli\thttps://proton.me/download/pass-cli/versions.json\t-\t-\t-' \
  "$root/qvcore/direct/manifest.tsv" ||
  fail "Proton Pass manifest update source"

npm_runtime="$test_root/npm-direct"
npm_prefix="$test_root/npm-prefix"
npm_bin="$test_root/npm-bin"
install -d "$npm_runtime" "$npm_prefix/bin" "$npm_bin"
cp "$root/qvcore/direct/tool" "$npm_runtime/tool"
install -m 0644 /dev/stdin "$npm_runtime/manifest.tsv" <<'MANIFEST'
# id	scope	label	method	commands	source	asset-x86_64	asset-aarch64	asset-kind
playwright-cli	devel	Playwright CLI	npm	playwright-cli	@playwright/cli	-	-	-
MANIFEST
install -m 0755 /dev/stdin "$npm_bin/npm" <<'SCRIPT'
#!/bin/bash
case $1 in
list)
  [[ $2 == "--global" && $3 == "--depth=0" && $4 == "@playwright/cli" ]]
  ;;
prefix)
  [[ $2 == "--global" ]] && printf '%s\n' "$QVOS_TEST_NPM_PREFIX"
  ;;
*)
  exit 1
  ;;
esac
SCRIPT
install -m 0755 /dev/stdin "$npm_prefix/bin/playwright-cli" <<'SCRIPT'
#!/bin/bash
[[ $1 == "--version" ]] && printf '0.1.17\n'
SCRIPT
HOME="$test_root/home" \
  PATH="$npm_bin:/usr/bin" \
  QVOS_TEST_NPM_PREFIX="$npm_prefix" \
  "$npm_runtime/tool" installed playwright-cli ||
  fail "generic npm direct-tool detection"

pass_runtime="$test_root/pass-direct"
pass_home="$test_root/pass-home"
pass_bin="$test_root/pass-bin"
pass_candidate="$test_root/pass-candidate"
pass_metadata="$test_root/pass-versions.json"
pass_log="$test_root/pass-actions.log"
pass_version="9.8.7"
pass_url="https://proton.me/download/pass-cli/$pass_version/pass-cli-linux-x86_64"
install -d "$pass_runtime" "$pass_home/.local/bin" "$pass_bin"
cp "$root/qvcore/direct/tool" "$pass_runtime/tool"
install -m 0644 /dev/stdin "$pass_runtime/manifest.tsv" <<'MANIFEST'
# id	scope	label	method	commands	source	asset-x86_64	asset-aarch64	asset-kind
pass-cli	proton	Proton Pass CLI	pass	pass-cli	https://proton.me/download/pass-cli/versions.json	-	-	-
MANIFEST
install -m 0755 /dev/stdin "$pass_home/.local/bin/pass-cli" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_PASS_LOG"
[[ ${1:-} == "--version" ]] && {
  echo "Proton Pass CLI 1.0.0"
  exit 0
}
exit 91
SCRIPT
install -m 0755 /dev/stdin "$pass_candidate" <<'SCRIPT'
#!/bin/bash
[[ ${1:-} == "--version" ]] && {
  echo "Proton Pass CLI 9.8.7"
  exit 0
}
exit 92
SCRIPT
pass_checksum=$(sha256sum "$pass_candidate" | awk '{print $1}')
jq -n \
  --arg version "$pass_version" \
  --arg url "$pass_url" \
  --arg hash "$pass_checksum" \
  '{
    formatVersion: 1,
    passCliVersions: {
      version: $version,
      urls: {linux: {x86_64: {url: $url, hash: $hash}}}
    }
  }' >"$pass_metadata"
install -m 0755 /dev/stdin "$pass_bin/curl" <<'SCRIPT'
#!/bin/bash
output=""
url=""
while (($#)); do
  case $1 in
  -o)
    output=$2
    shift 2
    ;;
  http*)
    url=$1
    shift
    ;;
  *) shift ;;
  esac
done
case $url in
https://proton.me/download/pass-cli/versions.json)
  cp "$QVOS_TEST_PASS_METADATA" "$output"
  ;;
https://proton.me/download/pass-cli/9.8.7/pass-cli-linux-x86_64)
  cp "$QVOS_TEST_PASS_CANDIDATE" "$output"
  ;;
*) exit 93 ;;
esac
SCRIPT
HOME="$pass_home" \
  PATH="$pass_bin:/usr/bin" \
  QVOS_TEST_PASS_CANDIDATE="$pass_candidate" \
  QVOS_TEST_PASS_LOG="$pass_log" \
  QVOS_TEST_PASS_METADATA="$pass_metadata" \
  "$pass_runtime/tool" update pass-cli ||
  fail "Proton Pass manifest update"
[[ $("$pass_home/.local/bin/pass-cli" --version) == "Proton Pass CLI $pass_version" ]] ||
  fail "Proton Pass candidate replacement"
if grep -Fq 'update' "$pass_log"; then
  fail "Proton Pass update initialized credential-aware CLI state"
fi

install -d "$runtime"
cp "$root/qvcore/direct/update" "$runtime/update"
install -m 0644 /dev/stdin "$runtime/manifest.tsv" <<'MANIFEST'
# id	scope	label	method	commands	source	asset-x86_64	asset-aarch64	asset-kind
node	devel	Node	mise	node	source	-	-	-
pass-cli	proton	Pass	pass	pass-cli	source	-	-	-
proton-drive	proton	Drive	proton-drive	proton-drive	source	-	-	-
MANIFEST
install -m 0755 /dev/stdin "$runtime/tool" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
action=$1
tool_id=$2
printf '%s\t%s\n' "$action" "$tool_id" >>"$QVOS_TEST_LOG"
case $action in
installed)
  [[ $tool_id != "node" ]]
  ;;
update)
  [[ $tool_id != "pass-cli" ]]
  ;;
*)
  echo "unexpected action: $action" >&2
  exit 2
  ;;
esac
SCRIPT

set +e
update_output=$(QVOS_TEST_LOG="$log" "$runtime/update" 2>&1)
update_status=$?
set -e
((update_status != 0)) || fail "direct updater hides an independent failure"
grep -Fq 'Direct tools: 1 updated, 1 absent and skipped, 1 failed.' \
  <<<"$update_output" ||
  fail "truthful direct updater summary"
[[ $(<"$log") == \
  $'installed\tnode\ninstalled\tpass-cli\nupdate\tpass-cli\ninstalled\tproton-drive\nupdate\tproton-drive' ]] ||
  fail "direct updater skips absence and continues after failure"
if grep -q $'^install\t' "$log"; then
  fail "direct updater installs a missing tool"
fi

for forbidden in \
  'auth login' \
  'omarchy-install-qvcore' \
  'omarchy-qvos-setup-dns' \
  'qvcore/core' \
  'health.sh'; do
  if rg -Fq "$forbidden" "$root/qvcore/direct/update" "$root/qvcore/direct/post-update-hook"; then
    fail "direct updater crosses its boundary: $forbidden"
  fi
done
grep -Fq 'timeout --foreground' "$root/qvcore/direct/tool" ||
  fail "bounded direct-tool operations"
grep -Fq 'sha256sum' "$root/qvcore/direct/tool" ||
  fail "GitHub release digest verification"
grep -Fq 'sha512sum --check --status' "$root/qvcore/direct/tool" ||
  fail "Proton Drive checksum verification"
grep -Fq "mv -f -- \"\$pending\"" "$root/qvcore/direct/tool" ||
  fail "atomic direct-tool replacement"

printf 'ok - one manifest updater skips absence and reports independent failures\n'
