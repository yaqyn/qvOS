# Copy over the keyboard layout that's been set in Arch during install to Hyprland
conf="/etc/vconsole.conf"
hyprconf="$HOME/.config/hypr/input.lua"

if grep -q '^XKBLAYOUT=' "$conf"; then
  layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')
  [[ $layout =~ ^[[:alnum:]_+,-]+$ ]] || {
    echo "Unsupported XKB layout: $layout" >&2
    exit 1
  }
  sed -i -E \
    "s|^([[:space:]]*kb_layout[[:space:]]*=[[:space:]]*)\"[^\"]*\",|\\1\"$layout\",|" \
    "$hyprconf"
fi

if grep -q '^XKBVARIANT=' "$conf"; then
  variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')
  [[ $variant =~ ^[[:alnum:]_+,-]+$ ]] || {
    echo "Unsupported XKB variant: $variant" >&2
    exit 1
  }
  if grep -Eq '^[[:space:]]*kb_variant[[:space:]]*=' "$hyprconf"; then
    sed -i -E \
      "s|^([[:space:]]*kb_variant[[:space:]]*=[[:space:]]*)\"[^\"]*\",|\\1\"$variant\",|" \
      "$hyprconf"
  else
    sed -i "/^[[:space:]]*kb_options[[:space:]]*=/i\\    kb_variant = \"$variant\"," \
      "$hyprconf"
  fi
fi
