return {
	{
		dir = vim.fn.expand("~/.config/omarchy/current/theme/neovim"),
		name = "yaqyn.nvim",
		lazy = false,
		priority = 1000,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "yaqyn",
		},
	},
}
