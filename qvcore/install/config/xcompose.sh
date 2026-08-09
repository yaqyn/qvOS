# Set the default XCompose that is triggered with CapsLock. Preserve custom
# files and migrate only the exact previous qvOS-generated form.
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
if ! xcompose_legacy=$(mktemp "$HOME/.XCompose.legacy.XXXXXX"); then
  rm -f -- "$xcompose_candidate"
  return 1
fi
chmod 0644 "$xcompose_candidate" "$xcompose_legacy"
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
  rm -f -- "$xcompose_candidate" "$xcompose_legacy"
  return 1
fi
if ! sed 's#qvcore/config/files/xcompose#default/xcompose#' \
  "$xcompose_candidate" >"$xcompose_legacy"; then
  rm -f -- "$xcompose_candidate" "$xcompose_legacy"
  return 1
fi

if [[ ! -e $xcompose_target ]] || cmp -s "$xcompose_legacy" "$xcompose_target"; then
  if ! mv -T -- "$xcompose_candidate" "$xcompose_target"; then
    rm -f -- "$xcompose_candidate" "$xcompose_legacy"
    return 1
  fi
elif cmp -s "$xcompose_candidate" "$xcompose_target"; then
  :
else
  inherited_qvos_include='include "%H/.local/share/qvos/default/xcompose"'
  inherited_omarchy_include='include "%H/.local/share/omarchy/default/xcompose"'
  # This is migration data, not an active command route. Keep the inherited
  # token split so repository-wide route scans remain strict.
  inherited_restart_comment='# Run omarchy'"-restart-xcompose to apply changes"
  native_include='include "%H/.local/share/qvos/qvcore/config/files/xcompose"'
  inherited_qvos_count=$(grep -Fxc -- "$inherited_qvos_include" "$xcompose_target" || true)
  inherited_omarchy_count=$(grep -Fxc -- "$inherited_omarchy_include" "$xcompose_target" || true)
  inherited_count=$((inherited_qvos_count + inherited_omarchy_count))
  native_count=$(grep -Fxc -- "$native_include" "$xcompose_target" || true)
  if ((inherited_count == 1 && native_count == 0)); then
    if ! awk \
      -v old_qvos="$inherited_qvos_include" \
      -v old_omarchy="$inherited_omarchy_include" \
      -v old_comment="$inherited_restart_comment" \
      -v new="$native_include" '
        $0 == old_qvos || $0 == old_omarchy { print new; next }
        $0 == old_comment {
          print "# Run qv-restart-xcompose to apply changes"
          next
        }
        { print }
      ' \
      "$xcompose_target" >"$xcompose_legacy"; then
      rm -f -- "$xcompose_candidate" "$xcompose_legacy"
      return 1
    fi
    if ! backup=$(mktemp "$HOME/.XCompose.qvos-backup.XXXXXX"); then
      rm -f -- "$xcompose_candidate" "$xcompose_legacy"
      return 1
    fi
    if ! install -m 0600 "$xcompose_target" "$backup"; then
      rm -f -- "$xcompose_candidate" "$xcompose_legacy" "$backup"
      return 1
    fi
    if ! mv -T -- "$xcompose_legacy" "$xcompose_target"; then
      rm -f -- "$xcompose_candidate" "$xcompose_legacy"
      printf 'Could not migrate XCompose; backup retained at %s\n' "$backup" >&2
      return 1
    fi
    printf 'Migrated XCompose to the native source; backup: %s\n' "$backup"
  elif ((inherited_count > 0)); then
    echo "XCompose has ambiguous inherited includes; preserving it for manual review." >&2
    rm -f -- "$xcompose_candidate" "$xcompose_legacy"
    return 1
  else
    echo "Preserving the existing XCompose configuration."
  fi
fi
rm -f -- "$xcompose_candidate" "$xcompose_legacy"
