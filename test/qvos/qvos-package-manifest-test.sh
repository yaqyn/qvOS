#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
resolver="$root/qv/install/packaging/resolve"
base_manifest="$root/qv/install/packaging/base.packages"
other_manifest="$root/qv/install/packaging/other.packages"
test_root="$(mktemp -d)"
fixture="$test_root/qv/install/packaging"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

manifest_entries() {
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$1"
}

base=$("$resolver" base)
other=$("$resolver" other)
all=$("$resolver" all)
[[ $base == "$(manifest_entries "$base_manifest")" ]] ||
  fail "base resolver output differs from its native manifest"
[[ $other == "$(manifest_entries "$other_manifest")" ]] ||
  fail "hardware resolver output differs from its native manifest"
[[ $all == "$base"$'\n'"$other" ]] ||
  fail "combined resolver output differs from the two native manifests"
(( $(wc -l <<<"$base") > 100 )) || fail "base manifest is implausibly small"
(( $(wc -l <<<"$other") > 40 )) || fail "hardware manifest is implausibly small"

install -d "$fixture"
install -m 0755 "$resolver" "$fixture/resolve"
install -m 0644 "$base_manifest" "$fixture/base.packages"
install -m 0644 "$other_manifest" "$fixture/other.packages"

printf 'alacritty\nalacritty\n' >"$fixture/base.packages"
if "$fixture/resolve" base >/dev/null 2>&1; then
  fail "duplicate package within one manifest was accepted"
fi

install -m 0644 "$base_manifest" "$fixture/base.packages"
printf 'alacritty\n' >>"$fixture/other.packages"
if "$fixture/resolve" all >/dev/null 2>&1; then
  fail "package owned by both manifests was accepted"
fi

printf 'invalid package\n' >"$fixture/base.packages"
if "$fixture/resolve" base >/dev/null 2>&1; then
  fail "invalid package name was accepted"
fi

rm "$fixture/base.packages"
if "$fixture/resolve" base >/dev/null 2>&1; then
  fail "missing native package manifest was accepted"
fi

printf 'ok - qvOS package manifests are singular, validated, and complete\n'
