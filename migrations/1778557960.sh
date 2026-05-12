echo "Remove preinstalled web apps"

webapps=(
  "HEY"
  "Basecamp"
  "WhatsApp"
  "Google Photos"
  "Google Contacts"
  "Google Messages"
  "Google Maps"
  "ChatGPT"
  "YouTube"
  "GitHub"
  "X"
  "Figma"
  "Discord"
  "Zoom"
  "Fizzy"
)

omarchy-webapp-remove "${webapps[@]}"

for webapp in "${webapps[@]}"; do
  rm -f "$HOME/.local/share/icons/hicolor/48x48/apps/$webapp.png"
done

gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
