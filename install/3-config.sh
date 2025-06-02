# Copy over Omarchy configs
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default bashrc from Omarchy
echo "source ~/.local/share/omarchy/default/bash/rc" >~/.bashrc

# Set common git aliases
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global pull.rebase true
