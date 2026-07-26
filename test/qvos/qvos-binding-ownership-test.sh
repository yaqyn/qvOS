#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bindings="$root/qv/config/files/hypr/qv/bindings.conf"
application_bindings="$root/qv/config/files/hypr/bindings.conf"
upstream_sources=(
  "$root/default/hypr/bindings/media.conf"
  "$root/default/hypr/bindings/clipboard.conf"
  "$root/default/hypr/bindings/tiling-v2.conf"
  "$root/default/hypr/bindings/utilities.conf"
  "$application_bindings"
)

if grep -Eq '^bind[a-z]* =' "$application_bindings"; then
  printf 'not ok - optional Omarchy application binding remains enabled\n' >&2
  exit 1
fi
printf 'ok - optional Omarchy application bindings stay disabled\n'

awk -F ',[[:space:]]*' '
function canonical_modifiers(modifiers, normalized) {
  normalized = ""
  if (modifiers ~ /SUPER/) normalized = "SUPER"
  if (modifiers ~ /SHIFT/) normalized = normalized (normalized ? " " : "") "SHIFT"
  if (modifiers ~ /CTRL/) normalized = normalized (normalized ? " " : "") "CTRL"
  if (modifiers ~ /ALT/) normalized = normalized (normalized ? " " : "") "ALT"
  return normalized
}

function binding_key(first_field, second_field, modifiers, key) {
  modifiers = first_field
  sub(/^[^=]+=[[:space:]]*/, "", modifiers)
  key = toupper(second_field)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
  return canonical_modifiers(modifiers) " + " key
}

FNR == NR {
  if ($0 ~ /^unbind =/) {
    key = binding_key($1, $2)
    unbind_count[key]++
  } else if ($0 ~ /^bind[a-z]* =/) {
    qvos_bind[binding_key($1, $2)] = 1
  }
  next
}

$0 ~ /^bind[a-z]* =/ {
  upstream_bind[binding_key($1, $2)] = 1
}

END {
  failed = 0

  for (key in unbind_count) {
    if (unbind_count[key] != 1) {
      printf "not ok - duplicate qvOS unbind: %s\n", key >"/dev/stderr"
      failed = 1
    }
    if (!(key in qvos_bind)) {
      printf "not ok - qvOS unbind without replacement: %s\n", key >"/dev/stderr"
      failed = 1
    }
    if (!(key in upstream_bind)) {
      printf "not ok - qvOS unbind without upstream collision: %s\n", key >"/dev/stderr"
      failed = 1
    }
  }

  for (key in qvos_bind) {
    if ((key in upstream_bind) && !(key in unbind_count)) {
      printf "not ok - qvOS collision without explicit unbind: %s\n", key >"/dev/stderr"
      failed = 1
    }
  }

  if (failed) exit 1
}
' "$bindings" "${upstream_sources[@]}"

printf 'ok - qvOS unbinds only exact upstream collisions it replaces\n'
