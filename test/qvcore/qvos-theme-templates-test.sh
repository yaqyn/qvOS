#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

prepare_home() {
  local home=$1

  mkdir -p \
    "$home/.config/qvos/current/next-theme" \
    "$home/.config/qvos/themed"
  cp -- "$root/qvcore/theme/yaqyn/colors.toml" \
    "$home/.config/qvos/current/next-theme/colors.toml"
}

render_templates() {
  local home=$1

  HOME="$home" QVOS_PATH="$root" "$root/qvcore/theme/set-templates"
}

valid_home="$test_root/valid"
prepare_home "$valid_home"
printf 'override={{ accent }}\n' \
  >"$valid_home/.config/qvos/themed/kitty.conf.tpl"
printf 'palette={{ background }}\n' \
  >"$valid_home/.config/qvos/themed/colors.sed.tpl"
render_templates "$valid_home"
next_theme="$valid_home/.config/qvos/current/next-theme"
expected_accent=$(
  "$root/qvcore/theme/validate" --colors \
    "$root/qvcore/theme/yaqyn/colors.toml" |
    awk -F '\t' '$1 == "accent" { print $2 }'
)
expected_background=$(
  "$root/qvcore/theme/validate" --colors \
    "$root/qvcore/theme/yaqyn/colors.toml" |
    awk -F '\t' '$1 == "background" { print $2 }'
)
[[ $(<"$next_theme/kitty.conf") == "override=$expected_accent" ]] ||
  fail "user template precedence"
grep -Fqx "palette=$expected_background" "$next_theme/colors.sed" ||
  fail "user output name collided with private renderer state"
[[ -f $next_theme/waybar.css && ! -L $next_theme/waybar.css ]] ||
  fail "built-in template rendering"
[[ -z $(find "$next_theme" -maxdepth 1 -name '.qvos-*' -print -quit) ]] ||
  fail "successful render left staging data"
before_hash=$(sha256sum "$next_theme/kitty.conf" "$next_theme/waybar.css")
render_templates "$valid_home"
[[ $(sha256sum "$next_theme/kitty.conf" "$next_theme/waybar.css") == "$before_hash" ]] ||
  fail "template rendering idempotence"

invalid_name_home="$test_root/invalid-name"
prepare_home "$invalid_name_home"
printf 'invalid\n' >"$invalid_name_home/.config/qvos/themed/Upper.tpl"
if render_templates "$invalid_name_home" >/dev/null 2>&1; then
  fail "invalid output name acceptance"
fi
[[ $(find "$invalid_name_home/.config/qvos/current/next-theme" \
  -maxdepth 1 -type f ! -name colors.toml -print -quit) == "" ]] ||
  fail "invalid output name caused partial rendering"

unresolved_home="$test_root/unresolved"
prepare_home "$unresolved_home"
printf 'valid={{ accent }}\n' \
  >"$unresolved_home/.config/qvos/themed/a-valid.tpl"
printf 'invalid={{ missing }}\n' \
  >"$unresolved_home/.config/qvos/themed/z-invalid.tpl"
if render_templates "$unresolved_home" >/dev/null 2>&1; then
  fail "unresolved placeholder acceptance"
fi
[[ ! -e $unresolved_home/.config/qvos/current/next-theme/a-valid ]] ||
  fail "failed render published an earlier output"
[[ -z $(find "$unresolved_home/.config/qvos/current/next-theme" \
  -maxdepth 1 -name '.qvos-*' -print -quit) ]] ||
  fail "failed render left staging data"

linked_home="$test_root/linked"
outside_templates="$test_root/outside-templates"
prepare_home "$linked_home"
rmdir -- "$linked_home/.config/qvos/themed"
mkdir -p "$outside_templates"
printf 'outside={{ accent }}\n' >"$outside_templates/outside.tpl"
ln -s "$outside_templates" "$linked_home/.config/qvos/themed"
if render_templates "$linked_home" >/dev/null 2>&1; then
  fail "linked user template directory acceptance"
fi
[[ $(<"$outside_templates/outside.tpl") == 'outside={{ accent }}' ]] ||
  fail "linked user template source mutation"

linked_output_home="$test_root/linked-output"
outside_output="$test_root/outside-output"
prepare_home "$linked_output_home"
printf 'outside output\n' >"$outside_output"
ln -s "$outside_output" \
  "$linked_output_home/.config/qvos/current/next-theme/kitty.conf"
if render_templates "$linked_output_home" >/dev/null 2>&1; then
  fail "linked template output acceptance"
fi
[[ $(<"$outside_output") == "outside output" ]] ||
  fail "linked template output mutation"

printf 'ok - qvOS renders native and compatible theme templates transactionally\n'
