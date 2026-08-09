if [[ -n ${QVOS_ONLINE_INSTALL:-} ]]; then
  provider_channel=${OMARCHY_MIRROR:-stable}
  provider_output=$(
    "$QVOS_PATH/qvcore/packages/provider-files" "$provider_channel"
  ) || return
  mapfile -t provider_files <<<"$provider_output"
  (( ${#provider_files[@]} == 2 )) || {
    echo "qvOS could not resolve the package provider files." >&2
    return 1
  }

  # Install build tools
  omarchy-pkg-add base-devel

  # Configure pacman
  sudo install -o root -g root -m 0644 -- "${provider_files[0]}" /etc/pacman.conf
  sudo install -o root -g root -m 0644 -- "${provider_files[1]}" /etc/pacman.d/mirrorlist

  sudo pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org
  sudo pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571

  sudo pacman -Sy
  omarchy-pkg-add omarchy-keyring

  # Refresh all repos
  sudo pacman -Syyuu --noconfirm
fi
