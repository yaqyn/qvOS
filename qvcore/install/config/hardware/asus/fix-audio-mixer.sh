# Fix audio volume on Asus ROG laptops by using a soft mixer.

if qv-hw-asus-rog; then
  source_file="$QVOS_PATH/qvcore/config/files/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"
  target_file="$HOME/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"
  [[ ! -L $target_file ]] || {
    echo "Refusing to install the ASUS audio policy through a symbolic link." >&2
    return 1
  }
  if [[ ! -e $target_file ]]; then
    install -D -m 0644 "$source_file" "$target_file"
  elif ! cmp -s "$source_file" "$target_file"; then
    echo "Preserving the existing ASUS audio policy."
  fi
  rm -rf ~/.local/state/wireplumber/default-routes

  # Unmute the Master control on the ALC285 card (often muted by default)
  card=$(aplay -l 2>/dev/null | grep -i "ALC285" | head -1 |
    sed 's/card \([0-9]*\).*/\1/' || true)
  if [[ -n $card ]]; then
    amixer -c "$card" set Master 80% unmute 2>/dev/null
  fi
fi
