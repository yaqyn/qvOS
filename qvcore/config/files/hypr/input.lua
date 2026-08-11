-- qvOS input defaults.
hl.config({
  input = {
    -- Caps Lock is handled as a pure language switch in qv bindings.
    kb_layout = "us,ara",
    kb_options = "caps:none",
    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      clickfinger_behavior = true,
      scroll_factor = 0.4,
      -- natural_scroll = true,
      -- disable_while_typing = false,
      -- drag_3fg = true,
    },
  },
  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Scroll naturally in supported terminals.
qv.window_rule("scroll_touchpad 1.5", { class = "(Alacritty|kitty|foot)" })
qv.window_rule("scroll_touchpad 0.2", { class = "com.mitchellh.ghostty" })

-- Example workspace gesture:
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
