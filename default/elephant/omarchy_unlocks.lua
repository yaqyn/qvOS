Name = "omarchyunlocks"
NamePretty = "Omarchy Unlocks"
HideFromProviderlist = true
FixedOrder = true

function GetEntries()
  local omarchy_path = os.getenv("OMARCHY_PATH") or ""

  return {
    {
      Text = "Default  ",
      Preview = omarchy_path .. "/default/plymouth/preview-unlock.png",
      PreviewType = "file",
      Actions = {
        activate = "omarchy-launch-floating-terminal-with-presentation 'omarchy-plymouth-reset'",
      },
    },
  }
end
