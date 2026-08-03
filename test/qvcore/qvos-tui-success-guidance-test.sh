#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
guidance="$root/qvcore/tui/success-guidance.psv"
software_actions="$root/qvcore/menu/software-actions.psv"
software_installers="$root/qvcore/menu/software-installers.psv"
tasks="$root/qvcore/tui/task/actions.psv"
post_actions="$root/qvcore/tui/action/post-actions.psv"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

awk -F '|' '
  $1 ~ /^#/ { next }
  NF != 3 { exit 1 }
  $1 == "" || $3 == "" { exit 1 }
  $2 != "install" && $2 != "uninstall" && $2 != "task" { exit 1 }
  length($3) > 96 { exit 1 }
  seen[$1 SUBSEP $2]++ { exit 1 }
  { count++ }
  END { exit !(count > 0) }
' "$guidance" ||
  fail "success guidance schema, uniqueness, or concise-copy contract"

while IFS='|' read -r slug operation _next_step; do
  [[ -n $slug && $slug != "#"* ]] || continue

  case $operation in
  install)
    if awk -F '|' -v wanted="$slug" '
      $1 == wanted && $4 == "tui" { found = 1 }
      END { exit !found }
    ' "$software_actions"; then
      continue
    fi
    awk -F '|' -v wanted="$slug" '
      $1 == wanted && $6 == "tui" { found = 1 }
      END { exit !found }
    ' "$software_installers" ||
      fail "install guidance does not resolve to a captured route: $slug"
    ;;
  uninstall)
    awk -F '|' -v wanted="$slug" '
      $1 == wanted && $6 == "tui" { found = 1 }
      END { exit !found }
    ' "$software_actions" ||
      fail "uninstall guidance does not resolve to a captured route: $slug"
    ;;
  task)
    awk -F '|' -v wanted="$slug" '
      $1 == wanted && $5 == "mutation" && $6 == "tui" { found = 1 }
      END { exit !found }
    ' "$tasks" ||
      fail "task guidance does not resolve to a captured mutation: $slug"
    ;;
  esac
done <"$guidance"

awk -F '|' '
  $1 ~ /^#/ { next }
  NF != 4 || $1 == "" || $2 != "install" || $3 == "" ||
    $4 != "owner-v1" || length($3) > 24 { exit 1 }
  seen[$1 SUBSEP $2]++ { exit 1 }
  { count++ }
  END { exit !(count > 0) }
' "$post_actions" ||
  fail "post-success action schema, uniqueness, or owner protocol"

while IFS='|' read -r slug operation _label _protocol; do
  [[ -n $slug && $slug != "#"* ]] || continue
  awk -F '|' -v wanted="$slug" '
    $1 == wanted && $4 == "tui" { found = 1 }
    END { exit !found }
  ' "$software_actions" ||
    fail "post-success action has no state-aware captured owner: $slug"
  awk -F '|' -v wanted="$slug" -v wanted_operation="$operation" '
    $1 == wanted && $2 == wanted_operation { found = 1 }
    END { exit !found }
  ' "$guidance" ||
    fail "post-success action has no completion guidance: $slug"
done <"$post_actions"

while IFS= read -r slug; do
  awk -F '|' -v wanted="$slug" '
    $1 == wanted && $2 == "install" { found = 1 }
    END { exit !found }
  ' "$guidance" ||
    fail "captured install has no useful next step: $slug"
done < <(
  awk -F '|' '$1 !~ /^#/ && $4 == "tui" { print $1 }' "$software_actions"
  awk -F '|' '$1 !~ /^#/ && $6 == "tui" { print $1 }' "$software_installers"
)

printf 'ok - every captured install ends with concise route-owned next-step guidance\n'
