vim.o.background = "dark"
vim.g.colors_name = "orion"

local colors = {
	bg = "#080808",
	bg_alt = "#101010",
	bg_soft = "#181818",
	bg_lift = "#1a1a1a",
	bg_select = "#242424",
	fg = "#d0d0d0",
	fg_bright = "#e0e0e0",
	fg_peak = "#e6e6e6",
	muted = "#707070",
	muted_soft = "#505050",
	muted_alt = "#909090",
	border = "#101010",
	border_lift = "#242424",
	red = "#b01616",
	red_bright = "#c73535",
	red_dark = "#4a0808",
	red_bg = "#180505",
	red_select = "#2a1515",
	red_mid = "#6f0d0d",
}

local function hl(group, spec)
	vim.api.nvim_set_hl(0, group, spec)
end

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

hl("Normal", { fg = colors.fg, bg = colors.bg })
hl("NormalNC", { fg = colors.fg, bg = colors.bg })
hl("NormalFloat", { fg = colors.fg, bg = colors.bg_alt })
hl("FloatBorder", { fg = colors.border, bg = colors.bg_alt })
hl("FloatTitle", { fg = colors.fg_bright, bg = colors.bg_alt, bold = true })
hl("Cursor", { fg = colors.bg, bg = colors.fg_peak })
hl("lCursor", { fg = colors.bg, bg = colors.fg_peak })
hl("TermCursor", { fg = colors.bg, bg = colors.fg_peak })
hl("TermCursorNC", { fg = colors.bg, bg = colors.muted_alt })
hl("CursorLine", { bg = colors.bg_alt })
hl("CursorLineNr", { fg = colors.red, bg = colors.bg_alt, bold = true })
hl("LineNr", { fg = colors.muted_soft })
hl("SignColumn", { fg = colors.muted, bg = colors.bg })
hl("ColorColumn", { bg = colors.bg_alt })
hl("Visual", { bg = colors.bg_select })
hl("VisualNOS", { bg = colors.bg_soft })
hl("Search", { fg = colors.fg_peak, bg = colors.red_mid })
hl("IncSearch", { fg = colors.fg_peak, bg = colors.red })
hl("CurSearch", { fg = colors.fg_peak, bg = colors.red })
hl("MatchParen", { fg = colors.fg_peak, bg = colors.bg_soft, bold = true })
hl("WinSeparator", { fg = colors.border })
hl("VertSplit", { fg = colors.border })
hl("Pmenu", { fg = colors.fg, bg = colors.bg_alt })
hl("PmenuSel", { fg = colors.fg_bright, bg = colors.bg_lift })
hl("PmenuSbar", { bg = colors.bg_soft })
hl("PmenuThumb", { bg = colors.muted })

hl("Comment", { fg = colors.muted, italic = true })
hl("Constant", { fg = colors.muted_alt })
hl("String", { fg = "#c8c8c8" })
hl("Character", { fg = "#c8c8c8" })
hl("Number", { fg = "#b0b0b0" })
hl("Boolean", { fg = "#b0b0b0" })
hl("Float", { fg = "#b0b0b0" })
hl("Identifier", { fg = colors.fg })
hl("Function", { fg = colors.fg_bright })
hl("Statement", { fg = colors.red })
hl("Conditional", { fg = colors.red })
hl("Repeat", { fg = colors.red })
hl("Label", { fg = colors.red })
hl("Operator", { fg = colors.muted_alt })
hl("Keyword", { fg = colors.red })
hl("Exception", { fg = colors.red })
hl("PreProc", { fg = "#b8b8b8" })
hl("Include", { fg = "#b8b8b8" })
hl("Define", { fg = "#b8b8b8" })
hl("Macro", { fg = "#b8b8b8" })
hl("Type", { fg = "#b8b8b8" })
hl("StorageClass", { fg = colors.red })
hl("Structure", { fg = "#b8b8b8" })
hl("Special", { fg = "#a8a8a8" })
hl("SpecialChar", { fg = "#a8a8a8" })
hl("Delimiter", { fg = colors.muted_alt })
hl("Underlined", { fg = colors.red, underline = true })
hl("Error", { fg = colors.red, bg = colors.bg })
hl("Todo", { fg = colors.fg_peak, bg = colors.red_dark, bold = true })

hl("DiagnosticError", { fg = colors.red })
hl("DiagnosticWarn", { fg = "#b0b0b0" })
hl("DiagnosticInfo", { fg = "#a8a8a8" })
hl("DiagnosticHint", { fg = colors.muted_alt })
hl("DiagnosticUnderlineError", { sp = colors.red, underline = true })
hl("DiagnosticUnderlineWarn", { sp = "#b0b0b0", underline = true })
hl("DiagnosticUnderlineInfo", { sp = "#a8a8a8", underline = true })
hl("DiagnosticUnderlineHint", { sp = colors.muted_alt, underline = true })

hl("DiffAdd", { fg = "#9a9a9a", bg = colors.bg_alt })
hl("DiffChange", { fg = "#b0b0b0", bg = colors.bg_alt })
hl("DiffDelete", { fg = "#991313", bg = colors.red_bg })
hl("DiffText", { fg = colors.fg_peak, bg = colors.red_dark })
hl("Added", { fg = "#9a9a9a" })
hl("Changed", { fg = "#b0b0b0" })
hl("Removed", { fg = "#991313" })

hl("GitSignsAdd", { fg = "#9a9a9a" })
hl("GitSignsChange", { fg = "#b0b0b0" })
hl("GitSignsDelete", { fg = "#991313" })

hl("StatusLine", { fg = colors.fg, bg = colors.bg_alt })
hl("StatusLineNC", { fg = colors.muted, bg = colors.bg })
hl("TabLine", { fg = colors.muted, bg = colors.bg })
hl("TabLineSel", { fg = colors.fg_bright, bg = colors.bg_alt })
hl("TabLineFill", { bg = colors.bg })

hl("TelescopeNormal", { fg = colors.fg, bg = colors.bg })
hl("TelescopeBorder", { fg = colors.border, bg = colors.bg })
hl("TelescopeSelection", { fg = colors.fg_bright, bg = colors.bg_lift })
hl("TelescopeMatching", { fg = colors.red, bold = true })

hl("NeoTreeNormal", { fg = colors.fg, bg = colors.bg })
hl("NeoTreeNormalNC", { fg = colors.fg, bg = colors.bg })
hl("NeoTreeDirectoryName", { fg = colors.fg })
hl("NeoTreeGitModified", { fg = "#b0b0b0" })
hl("NeoTreeGitAdded", { fg = "#9a9a9a" })
hl("NeoTreeGitDeleted", { fg = colors.red })

hl("Directory", { fg = "#c8c8c8" })
hl("Folded", { fg = colors.muted_alt, bg = colors.bg_alt })
hl("FoldColumn", { fg = colors.muted_soft, bg = colors.bg })
hl("NonText", { fg = colors.muted_soft })
hl("EndOfBuffer", { fg = colors.bg })
hl("Whitespace", { fg = "#202020" })
hl("SpecialKey", { fg = colors.muted_soft })
hl("Question", { fg = colors.fg_bright })
hl("MoreMsg", { fg = colors.fg_bright })
hl("ModeMsg", { fg = colors.fg })
hl("WarningMsg", { fg = colors.fg_bright })
hl("ErrorMsg", { fg = colors.red })
hl("MsgArea", { fg = colors.fg, bg = colors.bg })
hl("MsgSeparator", { fg = colors.border, bg = colors.bg })
hl("QuickFixLine", { fg = colors.fg_bright, bg = colors.bg_lift })
hl("SpellBad", { sp = colors.red, underline = true })
hl("SpellCap", { sp = colors.muted_alt, underline = true })
hl("SpellLocal", { sp = colors.muted_alt, underline = true })
hl("SpellRare", { sp = colors.muted_alt, underline = true })

hl("Boolean", { fg = colors.red_bright })
hl("Constant", { fg = colors.red_bright })
hl("Tag", { fg = colors.fg })
hl("markdownH1", { fg = colors.fg_bright, bold = true })
hl("markdownH2", { fg = colors.fg_bright, bold = true })
hl("markdownLinkText", { fg = colors.red })
hl("markdownUrl", { fg = colors.muted_alt })

vim.g.terminal_color_0 = "#121212"
vim.g.terminal_color_1 = "#991313"
vim.g.terminal_color_2 = "#707070"
vim.g.terminal_color_3 = "#8a8a8a"
vim.g.terminal_color_4 = "#a0a0a0"
vim.g.terminal_color_5 = "#b8b8b8"
vim.g.terminal_color_6 = "#909090"
vim.g.terminal_color_7 = "#c8c8c8"
vim.g.terminal_color_8 = "#404040"
vim.g.terminal_color_9 = "#bd2a2a"
vim.g.terminal_color_10 = "#9a9a9a"
vim.g.terminal_color_11 = "#b0b0b0"
vim.g.terminal_color_12 = "#c6c6c6"
vim.g.terminal_color_13 = "#dddddd"
vim.g.terminal_color_14 = "#a8a8a8"
vim.g.terminal_color_15 = "#e6e6e6"
