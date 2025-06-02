sudo pacman -Sy --noconfirm --needed \
  sddm \
  sddm-kcm \
  qt6-base qt6-svg qt6-virtualkeyboard qt6-multimedia \
  qt6-wayland qt5-wayland

sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF

sudo tee /etc/sddm.conf >/dev/null <<EOF
[General]
DefaultSession=hyprland

[Theme]
Current=breeze

[Wayland]
SessionCommand=/usr/share/sddm/scripts/wayland-session
SessionLogFile=.cache/wayland-session.log
EOF

sudo systemctl enable sddm.service
