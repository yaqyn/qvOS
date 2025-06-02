# Install everything
for f in ~/.local/share/omarchy/install/*.sh; do source "$f"; done

echo "Reboot for all settings to apply..."
gum confirm "Reboot to apply all settings?" && reboot
