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
    $2 !~ /^(base|qvdev|proton)$/ { exit 1 }
    $4 !~ /^(codex|mise|github|uv-tool|npm|pass|proton-drive)$/ { exit 1 }
    seen[$1]++ { exit 1 }
    { count++ }
    END { if (count < 20) exit 1; print count }
  ' "$root/qv/direct/manifest.tsv"
) || fail "direct-tool manifest schema"
((manifest_count >= 20)) || fail "direct-tool manifest inventory"
[[ $("$root/qv/direct/tool" list-scope base) == "codex" ]] ||
  fail "Codex is the base direct tool"
[[ $("$root/qv/direct/tool" list-scope proton) == $'pass-cli\nproton-drive' ]] ||
  fail "Proton direct-tool inventory"
[[ $("$root/qv/direct/tool" list-scope qvdev | wc -l) == "17" ]] ||
  fail "qvDEV direct-tool inventory"

install -d "$runtime"
cp "$root/qv/direct/update" "$runtime/update"
install -m 0644 /dev/stdin "$runtime/manifest.tsv" <<'MANIFEST'
# id	scope	label	method	commands	source	asset-x86_64	asset-aarch64	asset-kind
codex	base	Codex	codex	codex	source	-	-	-
node	qvdev	Node	mise	node	source	-	-	-
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
grep -Fq 'Direct tools: 2 updated, 1 absent and skipped, 1 failed.' \
  <<<"$update_output" ||
  fail "truthful direct updater summary"
[[ $(<"$log") == \
  $'installed\tcodex\nupdate\tcodex\ninstalled\tnode\ninstalled\tpass-cli\nupdate\tpass-cli\ninstalled\tproton-drive\nupdate\tproton-drive' ]] ||
  fail "direct updater skips absence and continues after failure"
if grep -q $'^install\t' "$log"; then
  fail "direct updater installs a missing tool"
fi

for forbidden in \
  'auth login' \
  'omarchy-install-qvcore' \
  'omarchy-qvos-setup-dns' \
  'qv/core' \
  'health.sh'; do
  if rg -Fq "$forbidden" "$root/qv/direct/update" "$root/qv/direct/post-update-hook"; then
    fail "direct updater crosses its boundary: $forbidden"
  fi
done
grep -Fq 'timeout --foreground' "$root/qv/direct/tool" ||
  fail "bounded direct-tool operations"
grep -Fq 'sha256sum' "$root/qv/direct/tool" ||
  fail "GitHub release digest verification"
grep -Fq 'sha512sum --check --status' "$root/qv/direct/tool" ||
  fail "Proton Drive checksum verification"
grep -Fq 'mv -f -- "$pending"' "$root/qv/direct/tool" ||
  fail "atomic direct-tool replacement"

printf 'ok - one manifest updater skips absence and reports independent failures\n'
