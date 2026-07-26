# qvOS package policy is owned separately from Omarchy's manifest.
qvos_owner="$OMARCHY_PATH/qv/install/packaging/base"
if [[ -f $qvos_owner ]]; then
  source "$qvos_owner"
  return
fi

# Install all base packages
mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base.packages" | grep -v '^$')
omarchy-pkg-add "${packages[@]}"
