--
-- Dynamic qvOS Unlocks Menu for Elephant/Walker
--
-- A "Yaqyn" entry restores the shipped qvOS Plymouth via
-- qv-plymouth-reset. After that, every theme that has a preview-unlock.png
-- appears as a customised unlock; picking one runs qv-plymouth-set-by-theme
-- <theme>. Both run in a floating terminal so sudo can prompt.
--
Name = "qvosUnlocks"
NamePretty = "qvOS Unlocks"
HideFromProviderlist = true
FixedOrder = true

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function GetEntries()
  local entries = {}
  local home = os.getenv("HOME")
  if not home or home == "" then return entries end
  local user_themes_dir = home .. "/.config/qvos/themes"
  local qvos_path = os.getenv("QVOS_PATH")
  if not qvos_path or qvos_path == "" then
    qvos_path = home .. "/.local/share/qvos"
  end
  local default_preview = qvos_path .. "/qvcore/boot/plymouth/preview-unlock.png"

  local handle = io.popen(
    "/usr/bin/find -L " .. shell_escape(user_themes_dir)
      .. " -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | /usr/bin/sort"
  )
  if handle then
    for theme_path in handle:lines() do
      local theme_name = theme_path:match(".*/(.+)$")
      local preview_path = theme_path .. "/preview-unlock.png"

      if theme_name and theme_name:lower() ~= "yaqyn" and file_exists(preview_path) then
        local display_name = theme_name:gsub("_", " "):gsub("%-", " ")
        display_name = display_name:gsub("(%a)([%w_']*)", function(first, rest)
          return first:upper() .. rest:lower()
        end)
        display_name = display_name .. "  "

        table.insert(entries, {
          Text = display_name,
          Preview = preview_path,
          PreviewType = "file",
          Actions = {
            activate = "qv-launch-floating-terminal-with-presentation "
              .. "qv-plymouth-set-by-theme " .. shell_escape(theme_name),
          },
        })
      end
    end

    handle:close()
  end

  -- Yaqyn is the shipped Plymouth and remains distinct from custom themes.
  local default_entry = {
    Text = "Yaqyn  ",
    Actions = {
      activate = "qv-launch-floating-terminal-with-presentation qv-plymouth-reset",
    },
  }
  if file_exists(default_preview) then
    default_entry.Preview = default_preview
    default_entry.PreviewType = "file"
  end
  table.insert(entries, default_entry)

  return entries
end
