# shellcheck shell=bash
# Set the default XCompose that is triggered with CapsLock. Preserve every
# existing custom file and install only a missing native qvOS seed.
xcompose_target="$HOME/.XCompose"
[[ ! -L $xcompose_target ]] || {
  echo "Refusing to configure XCompose through a symbolic link." >&2
  return 1
}
if [[ -e $xcompose_target && (! -f $xcompose_target || ! -O $xcompose_target) ]]; then
  echo "Refusing to replace a non-regular or foreign XCompose configuration." >&2
  return 1
fi

qvos_user_name=${QVOS_USER_NAME:-}
qvos_user_email=${QVOS_USER_EMAIL:-}
if [[ $qvos_user_name == *$'\n'* || $qvos_user_name == *$'\r'* ||
  $qvos_user_email == *$'\n'* || $qvos_user_email == *$'\r'* ]]; then
  echo "XCompose identity values may not contain line breaks." >&2
  return 1
fi
qvos_user_name=${qvos_user_name//\\/\\\\}
qvos_user_name=${qvos_user_name//\"/\\\"}
qvos_user_email=${qvos_user_email//\\/\\\\}
qvos_user_email=${qvos_user_email//\"/\\\"}

xcompose_candidate=$(mktemp "$HOME/.XCompose.qvos.XXXXXX")
chmod 0644 "$xcompose_candidate"
if ! printf '%s\n' \
  '# Run qv-restart-xcompose to apply changes' \
  '' \
  '# Include fast emoji access' \
  'include "%H/.local/share/qvos/qvcore/config/files/xcompose"' \
  '' \
  '# Identification' \
  "<Multi_key> <space> <n> : \"$qvos_user_name\"" \
  "<Multi_key> <space> <e> : \"$qvos_user_email\"" \
  >"$xcompose_candidate"; then
  rm -f -- "$xcompose_candidate"
  return 1
fi

if [[ ! -e $xcompose_target ]]; then
  if ! mv -T -- "$xcompose_candidate" "$xcompose_target"; then
    rm -f -- "$xcompose_candidate"
    return 1
  fi
elif cmp -s "$xcompose_candidate" "$xcompose_target"; then
  :
else
  echo "Preserving the existing XCompose configuration."
fi
rm -f -- "$xcompose_candidate"
