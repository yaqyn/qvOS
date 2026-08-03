local home = os.getenv("HOME") or ""
local qvos_path = os.getenv("QVOS_PATH")
if not qvos_path or qvos_path == "" then
  qvos_path = os.getenv("OMARCHY_PATH")
end
if not qvos_path or qvos_path == "" then
  qvos_path = home .. "/.local/share/qvos"
end

dofile(qvos_path .. "/default/elephant/omarchy_unlocks.lua")

NamePretty = "qvOS Unlocks"

local omarchy_get_entries = GetEntries

function GetEntries()
  local entries = omarchy_get_entries()
  local preview = qvos_path .. "/qvcore/boot/plymouth/preview-unlock.png"

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
