-- Generated from the active validated qvOS palette.
local active_border = "rgb({{ accent_strip }})"
local inactive_border = "rgb({{ color0_strip }})"
local text = "rgb({{ foreground_strip }})"
local muted_text = "rgb({{ color8_strip }})"

hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    float_gaps = 0,
    border_size = 0,
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
      nogroup_border = inactive_border,
      nogroup_border_active = active_border,
    },
    resize_on_border = false,
    extend_border_grab_area = 0,
    hover_icon_on_border = false,
    allow_tearing = false,
  },
  decoration = {
    rounding = 0,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    fullscreen_opacity = 1.0,
    shadow = {
      enabled = false,
    },
    blur = {
      enabled = false,
    },
    dim_inactive = true,
    dim_strength = 0.08,
  },
  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
      border_locked_active = active_border,
      border_locked_inactive = inactive_border,
    },
    groupbar = {
      font_family = "monospace",
      font_weight_active = "bold",
      font_weight_inactive = "normal",
      font_size = 12,
      gradients = false,
      height = 20,
      indicator_gap = 0,
      indicator_height = 0,
      gradient_rounding = 0,
      gradient_round_only_edges = false,
      text_color = text,
      text_color_inactive = muted_text,
      text_color_locked_active = text,
      text_color_locked_inactive = muted_text,
      col = {
        active = "rgba(00000000)",
        inactive = "rgba(00000000)",
        locked_active = "rgba(00000000)",
        locked_inactive = "rgba(00000000)",
      },
      gaps_out = 0,
      gaps_in = 0,
      text_padding = 6,
      blur = false,
    },
  },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    disable_scale_notification = true,
    font_family = "monospace",
  },
})

-- Solid, sharp qvOS presentation.
for _, tag in ipairs({ "default-opacity", "terminal", "chromium-based-browser", "firefox-based-browser", "floating-window", "pip" }) do
  qv.window_rule("opacity 1 1", { tag = tag })
end
qv.window_rule("rounding 0", { class = [[.*]] })
qv.window_rule("border_size 0", { class = [[.*]] })
for _, tag in ipairs({ "floating-window", "pop", "pip" }) do
  qv.window_rule("rounding 0", { tag = tag })
  qv.window_rule("border_size 0", { tag = tag })
end
qv.layer_rule("no_anim on", { namespace = [[selection]] })
qv.layer_rule("no_anim on", { namespace = [[walker]] })
