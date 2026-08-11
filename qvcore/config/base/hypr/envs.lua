-- qvOS session environment.

local home = assert(os.getenv("HOME"), "HOME is unavailable")
local gum_env = io.open(home .. "/.config/qvos/current/theme/gum.env.conf", "r")
if gum_env then
  for line in gum_env:lines() do
    local name, value = line:match("^%s*env%s*=%s*([A-Z][A-Z0-9_]*)%s*,(.*)$")
    if name then
      hl.env(name, value)
    end
  end
  gum_env:close()
end

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Prefer native Wayland while retaining XWayland compatibility.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Identify the session correctly to Wayland screen-sharing portals.
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XCOMPOSEFILE", home .. "/.XCompose")

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },
  ecosystem = {
    no_update_news = true,
  },
})
