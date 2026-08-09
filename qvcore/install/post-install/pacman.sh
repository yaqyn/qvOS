# Configure pacman
provider_channel=${OMARCHY_MIRROR:-stable}
provider_output=$(
  "$QVOS_PATH/qvcore/packages/provider-files" "$provider_channel"
) || return
mapfile -t provider_files <<<"$provider_output"
(( ${#provider_files[@]} == 2 )) || {
  echo "qvOS could not resolve the package provider files." >&2
  return 1
}
sudo install -o root -g root -m 0644 -- "${provider_files[0]}" /etc/pacman.conf
sudo install -o root -g root -m 0644 -- "${provider_files[1]}" /etc/pacman.d/mirrorlist

if lspci -nn | grep -q "106b:180[12]"; then
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi
