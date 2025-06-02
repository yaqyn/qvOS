yay -S --noconfirm \
  nvim luarocks tree-sitter-cli \
  mise github-cli \
  lazygit lazydocker

# Install LazyVim
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git

# Turn off relative line numbers in nvim
echo "vim.opt.relativenumber = false" >>~/.config/nvim/lua/config/options.lua
