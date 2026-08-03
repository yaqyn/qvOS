local home = os.getenv("HOME") or ""
local omarchy_path = os.getenv("OMARCHY_PATH")
if not omarchy_path or omarchy_path == "" then
  omarchy_path = home .. "/.local/share/omarchy"
end

dofile(omarchy_path .. "/default/elephant/omarchy_unlocks.lua")

NamePretty = "qvOS Unlocks"

local omarchy_get_entries = GetEntries

function GetEntries()
  local entries = omarchy_get_entries()
  local preview = omarchy_path .. "/qvcore/boot/plymouth/preview-unlock.png"

  for _, entry in ipairs(entries) do
    if entry.Text == "Default  " then
      entry.Text = "Yaqyn  "
      local preview_file = io.open(preview, "r")
      if preview_file then
        preview_file:close()
        entry.Preview = preview
        entry.PreviewType = "file"
      else
        entry.Preview = nil
        entry.PreviewType = nil
      end
      break
    end
  end

  return entries
end
