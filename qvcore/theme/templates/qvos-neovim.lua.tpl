local colors = {
  accent = "{{ accent }}",
  background = "{{ background }}",
  cursor = "{{ cursor }}",
  foreground = "{{ foreground }}",
  selection_background = "{{ selection_background }}",
  selection_foreground = "{{ selection_foreground }}",
  color0 = "{{ color0 }}",
  color1 = "{{ color1 }}",
  color2 = "{{ color2 }}",
  color3 = "{{ color3 }}",
  color4 = "{{ color4 }}",
  color5 = "{{ color5 }}",
  color6 = "{{ color6 }}",
  color7 = "{{ color7 }}",
  color8 = "{{ color8 }}",
  color9 = "{{ color9 }}",
  color10 = "{{ color10 }}",
  color11 = "{{ color11 }}",
  color12 = "{{ color12 }}",
  color13 = "{{ color13 }}",
  color14 = "{{ color14 }}",
  color15 = "{{ color15 }}",
}

local function luminance(hex)
  local red = tonumber(hex:sub(2, 3), 16) or 0
  local green = tonumber(hex:sub(4, 5), 16) or 0
  local blue = tonumber(hex:sub(6, 7), 16) or 0
  return (red * 299 + green * 587 + blue * 114) / 255000
end

local function highlight(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

vim.o.background = luminance(colors.background) > 0.5 and "light" or "dark"
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end

highlight("Normal", { fg = colors.foreground, bg = colors.background })
highlight("NormalNC", { fg = colors.foreground, bg = colors.background })
highlight("NormalFloat", { fg = colors.foreground, bg = colors.color0 })
highlight("FloatBorder", { fg = colors.color8, bg = colors.color0 })
highlight("Cursor", { fg = colors.background, bg = colors.cursor })
highlight("CursorLine", { bg = colors.color0 })
highlight("CursorLineNr", { fg = colors.accent, bold = true })
highlight("LineNr", { fg = colors.color8 })
highlight("SignColumn", { fg = colors.color8, bg = colors.background })
highlight("ColorColumn", { bg = colors.color0 })
highlight("Visual", { fg = colors.selection_foreground, bg = colors.selection_background })
highlight("Search", { fg = colors.background, bg = colors.color3 })
highlight("IncSearch", { fg = colors.background, bg = colors.accent })
highlight("MatchParen", { fg = colors.accent, bold = true })
highlight("WinSeparator", { fg = colors.color8 })
highlight("Pmenu", { fg = colors.foreground, bg = colors.color0 })
highlight("PmenuSel", { fg = colors.selection_foreground, bg = colors.selection_background })
highlight("PmenuSbar", { bg = colors.color0 })
highlight("PmenuThumb", { bg = colors.color8 })

highlight("Comment", { fg = colors.color8, italic = true })
highlight("Constant", { fg = colors.color5 })
highlight("String", { fg = colors.color2 })
highlight("Number", { fg = colors.color3 })
highlight("Boolean", { fg = colors.color3 })
highlight("Identifier", { fg = colors.color4 })
highlight("Function", { fg = colors.color6 })
highlight("Statement", { fg = colors.accent })
highlight("Operator", { fg = colors.color7 })
highlight("PreProc", { fg = colors.color5 })
highlight("Type", { fg = colors.color4 })
highlight("Special", { fg = colors.color6 })
highlight("Underlined", { fg = colors.color4, underline = true })
highlight("Error", { fg = colors.color1, bg = colors.background })
highlight("Todo", { fg = colors.background, bg = colors.color3, bold = true })

highlight("DiagnosticError", { fg = colors.color1 })
highlight("DiagnosticWarn", { fg = colors.color3 })
highlight("DiagnosticInfo", { fg = colors.color4 })
highlight("DiagnosticHint", { fg = colors.color6 })
highlight("DiffAdd", { fg = colors.color2, bg = colors.background })
highlight("DiffChange", { fg = colors.color3, bg = colors.background })
highlight("DiffDelete", { fg = colors.color1, bg = colors.background })
highlight("DiffText", { fg = colors.foreground, bg = colors.color0 })
highlight("StatusLine", { fg = colors.foreground, bg = colors.color0 })
highlight("StatusLineNC", { fg = colors.color8, bg = colors.background })
highlight("Directory", { fg = colors.color4 })
highlight("NonText", { fg = colors.color8 })
highlight("ErrorMsg", { fg = colors.color1 })
highlight("WarningMsg", { fg = colors.color3 })

for index = 0, 15 do
  vim.g["terminal_color_" .. index] = colors["color" .. index]
end
vim.g.colors_name = "qvos"
