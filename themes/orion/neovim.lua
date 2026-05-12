return {
	{
		dir = vim.fn.expand("~/.config/omarchy/current/theme/neovim"),
		name = "orion.nvim",
		lazy = false,
		priority = 1000,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "orion",
		},
	},
}
