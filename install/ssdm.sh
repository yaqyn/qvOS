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

# sudo tee /etc/ssdm.conf >/dev/null <<EOF
# [Theme]
# Current=This
# EOF

sudo tee /etc/ssdm.conf.d/virtualkbd.conf >/dev/null <<EOF
[General]
InputMethod=qtvirtualkeyboard
EOF

sudo systemctl enable sddm.service
