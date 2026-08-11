-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/

-- Use the native qvOS base. Do not edit these source-owned files directly.
require("~/.local/share/qvos/qvcore/config/base/hypr/runtime.lua")
require("~/.local/share/qvos/qvcore/config/base/hypr/envs.lua")
require("~/.local/share/qvos/qvcore/config/base/hypr/looknfeel.lua")
require("~/.local/share/qvos/qvcore/config/base/hypr/windows.lua")
require("~/.local/share/qvos/qvcore/config/base/hypr/autostart.lua")
require("~/.config/qvos/current/theme/hyprland.lua")

-- Change your own setup in these files. They override qvOS defaults.
require("~/.config/hypr/monitors.lua")
require("~/.config/hypr/input.lua")
require("~/.config/hypr/envs.lua")
require("~/.config/hypr/bindings.lua")
require("~/.config/hypr/looknfeel.lua")
require("~/.config/hypr/autostart.lua")

-- Load private qvOS toggle state, then start the complete autostart catalog.
qv.require_optional_wildcard("~/.local/state/qvos/toggles/hypr/*.lua")
qv.start_autostart()

-- Add any other personal Hyprland configuration below.
-- qv.window_rule("workspace 5", { class = "qemu" })
