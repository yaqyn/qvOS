# Install LazyVim
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git

# Copy over Omarchy configs
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Turn off relative line numbers in nvim
echo "vim.opt.relativenumber = false" >>~/.config/nvim/lua/config/options.lua
