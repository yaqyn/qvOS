vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.clipboard = "unnamedplus"
vim.opt.confirm = true
vim.opt.cursorline = true
vim.opt.expandtab = true
vim.opt.ignorecase = true
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.shiftwidth = 2
vim.opt.signcolumn = "yes"
vim.opt.smartcase = true
vim.opt.tabstop = 2
vim.opt.termguicolors = true
vim.opt.undofile = true
vim.opt.updatetime = 250

local theme = vim.fn.expand("~/.config/qvos/current/theme/qvos-neovim.lua")
if vim.fn.filereadable(theme) == 1 then
  local ok, error_message = pcall(dofile, theme)
  if not ok then
    vim.notify("Could not load the qvOS theme: " .. error_message, vim.log.levels.WARN)
  end
end

vim.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "Write file" })
vim.keymap.set("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })
