--
-- Dynamic qvOS Theme Menu for Elephant/Walker
--
Name = "qvosThemes"
NamePretty = "qvOS Themes"
HideFromProviderlist = true

-- Check if file exists using Lua (no subprocess)
local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function shell_escape(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Get the first background supplied by the theme.
local function first_image_in_dir(dir)
  local handle = io.popen(
    "/usr/bin/find " .. shell_escape(dir)
      .. " -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' -o -name '*.bmp' -o -name '*.webp' \\) -print 2>/dev/null | /usr/bin/sort | /usr/bin/head -n 1"
  )
  if handle then
    local file = handle:read("*l")
    handle:close()
    if file and file ~= "" then
      return file
    end
  end
  return nil
end

-- Find preview.png, preview.jpg, or first backgrounds/ image in a theme dir
local function find_preview_path(dir)
  local png = dir .. "/preview.png"
  local jpg = dir .. "/preview.jpg"
  if file_exists(png) then return png end
  if file_exists(jpg) then return jpg end
  return first_image_in_dir(dir .. "/backgrounds")
end

-- The main function elephant will call
function GetEntries()
  local entries = {}
  local home = os.getenv("HOME")
  if not home or home == "" then return entries end
  local user_theme_dir = home .. "/.config/omarchy/themes"
  local handle = io.popen(
    "/usr/bin/find -L " .. shell_escape(user_theme_dir)
      .. " -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | /usr/bin/sort"
  )
  if not handle then return entries end

  for theme_path in handle:lines() do
    local theme_name = theme_path:match(".*/(.+)$")
    local preview_path = find_preview_path(theme_path)

    if theme_name and preview_path and preview_path ~= "" then
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
          activate = "qv-theme-set " .. shell_escape(theme_name),
        },
      })
    end
  end

  handle:close()

  return entries
end
