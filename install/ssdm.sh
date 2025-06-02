sudo pacman -Sy --noconfirm --needed \
  sddm-kcm \
  qt6-base qt6-svg qt6-virtualkeyboard qt6-multimedia

sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF

sudo systemctl enable sddm.service
