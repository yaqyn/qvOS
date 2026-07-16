echo "Add archive actions and media thumbnails to Thunar"

omarchy-pkg-add thunar-archive-plugin engrampa tumbler

xdg-mime default engrampa.desktop application/x-compressed-tar
xdg-mime default engrampa.desktop application/x-tar
xdg-mime default engrampa.desktop application/x-zip
xdg-mime default engrampa.desktop application/zip
