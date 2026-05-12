echo "Remove preinstalled Zoom webapp"

if [[ -f ~/.local/share/applications/Zoom.desktop ]]; then
  omarchy-webapp-remove Zoom
fi
