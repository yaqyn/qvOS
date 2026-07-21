Name = "omarchythemes"
NamePretty = "Omarchy Themes"
HideFromProviderlist = true

function GetEntries()
  local omarchy_path = os.getenv("OMARCHY_PATH") or ""

  return {
    {
      Text = "Orion  ",
      Preview = omarchy_path .. "/themes/orion/preview.png",
      PreviewType = "file",
      Actions = {
        activate = "omarchy-theme-set orion",
      },
    },
  }
end
