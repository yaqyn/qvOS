-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and resolutions: hyprctl monitors

-- Adaptive default for retina-class and standard-density displays.
hl.env("GDK_SCALE", "2")
hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = "auto",
})

-- Example fixed 1x setup for 1080p, 1440p, and ultrawide displays:
-- hl.env("GDK_SCALE", "1")
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Example portrait secondary monitor:
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- Example disabled output:
-- hl.monitor({ output = "DP-2", disabled = true })
