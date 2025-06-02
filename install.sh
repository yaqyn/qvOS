# Exit immediately if a command exits with a non-zero status
set -e

# Give people a chance to retry running the installation
trap 'echo "Omarchy installation failed! You can retry by running: source ~/.local/share/omarchy/install.sh"' ERR

# Install everything
for f in ~/.local/share/omarchy/install/*.sh; do source "$f"; done

# Reboot
echo "Rebooting for all settings to apply..."
reboot
