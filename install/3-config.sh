# Copy over Omarchy configs
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default bashrc from Omarchy
echo "source ~/.local/share/omarchy/default/bash/rc" >~/.bashrc
