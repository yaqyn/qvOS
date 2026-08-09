# Turn on bluetooth by default
chrootable_systemctl_enable bluetooth.service

source_file="$QVOS_PATH/qvcore/config/files/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf"
target_file="$HOME/.config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf"
[[ ! -L $target_file ]] || {
  echo "Refusing to install Bluetooth audio policy through a symbolic link." >&2
  return 1
}
if [[ ! -e $target_file ]]; then
  install -D -m 0644 "$source_file" "$target_file"
elif ! cmp -s "$source_file" "$target_file"; then
  echo "Preserving the existing Bluetooth audio policy."
fi
