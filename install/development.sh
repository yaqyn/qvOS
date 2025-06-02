yay -S --noconfirm \
  nvim luarocks tree-sitter-cli \
  mise github-cli \
  lazygit lazydocker

# Install LazyVim
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git

# Turn off relative line numbers in nvim
echo "vim.opt.relativenumber = false" >>~/.config/nvim/lua/config/options.lua

# Set common git aliases
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global pull.rebase true
