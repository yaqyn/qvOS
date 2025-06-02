yay -S --noconfirm --needed \
  hyprland hyprpaper hyprshot hyprlock hypridle hyprpolkitagent hyprland-qtutils \
  waybar swaync \
  xdg-desktop-portal-hyprland

# Start Hyprland on first session
echo "[[ -z $DISPLAY && $(tty) == /dev/tty1 ]] && exec Hyprland" >~/.bash_profile
