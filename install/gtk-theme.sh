yay -S --noconfirm yaru-theme-gnome-shell-git yaru-theme-gtk-git yaru-theme-icon-git yaru-colors-theme-git

mkdir -p ~/.config/gtk-3.0
cat >~/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=Yaru-purple-dark
gtk-icon-theme-name=Yaru-purple
EOF

mkdir -p ~/.config/gtk-4.0
cat >~/.config/gtk-4.0/settings.ini <<EOF
[Settings]
gtk-theme-name=Yaru-purple-dark
gtk-icon-theme-name=Yaru-purple
EOF
