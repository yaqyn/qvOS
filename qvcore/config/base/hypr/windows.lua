-- qvOS window and layer rules.
qv.window_rule("suppress_event maximize", { class = [[.*]] })
qv.window_rule("tag +default-opacity", { class = [[.*]] })
qv.window_rule("no_focus on", {
  class = [[^$]],
  title = [[^$]],
  xwayland = true,
  float = true,
  fullscreen = false,
  pin = false,
})

-- Shared floating stage for qvOS terminal tools and base utilities.
qv.window_rule("float on", { tag = [[floating-window]] })
qv.window_rule("center on", { tag = [[floating-window]] })
qv.window_rule("size 875 600", { tag = [[floating-window]] })
qv.window_rule("tag +floating-window", { class = [[^org\.qvos\.(bluetui|impala|wiremix|btop|terminal)$]] })
qv.window_rule("tag +floating-window", { class = [[^(org\.gnome\.Evince|com\.gabm\.satty|imv|mpv)$]] })
qv.window_rule("tag +floating-window", {
  class = [[^(xdg-desktop-portal-gtk|sublime_text)$]],
  title = [[^(Open.*[Ff]iles?|Open [Ff]older.*|Save.*[Ff]iles?|Save.*As|Save|All Files|.*wants to (open|save).*|[Cc]hoose.*)$]],
})
qv.window_rule("float on", { class = [[^org\.gnome\.Calculator$]] })

-- qvOS TUI and tmux surfaces.
qv.window_rule("float on", { class = [[^org\.qvos\.tui$]] })
qv.window_rule("size 1024 509", { class = [[^org\.qvos\.tui$]] })
qv.window_rule("center on", { class = [[^org\.qvos\.tui$]] })
qv.window_rule("float on", { class = [[^org\.qvos\.tmux-manager$]] })
qv.window_rule("size 900 620", { class = [[^org\.qvos\.tmux-manager$]] })
qv.window_rule("center on", { class = [[^org\.qvos\.tmux-manager$]] })

-- qvOS screensaver owns the screen while active.
qv.window_rule("fullscreen on", { class = [[^org\.qvos\.screensaver$]] })
qv.window_rule("float on", { class = [[^org\.qvos\.screensaver$]] })
qv.window_rule("animation slide", { class = [[^org\.qvos\.screensaver$]] })

-- File manager dialogs and operations.
qv.window_rule("float on", { class = [[^thunar$]], modal = true })
qv.window_rule("center on", { class = [[^thunar$]], modal = true })
qv.window_rule("float on", { class = [[^thunar$]], title = [[^(File Operation Progress|Confirm to replace files|.*(Rename|Copy|Move|Delete).*)$]] })
qv.window_rule("center on", { class = [[^thunar$]], title = [[^(File Operation Progress|Confirm to replace files|.*(Rename|Copy|Move|Delete).*)$]] })

-- Password manager privacy and dialogs.
qv.window_rule("no_screen_share on", { class = [[^Bitwarden$]] })
qv.window_rule("tag +floating-window", { class = [[^Bitwarden$]] })
qv.window_rule("no_screen_share on", { class = [[^chrome-nngceckbapebfimnlniiiahkandclblb-Default$]] })
qv.window_rule("tag +floating-window", { class = [[^chrome-nngceckbapebfimnlniiiahkandclblb-Default$]] })

-- Browser behavior. These rules contain no service-specific Web App identity.
qv.window_rule("tag +chromium-based-browser", { class = [[^((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)$]] })
qv.window_rule("tag +firefox-based-browser", { class = [[^([fF]irefox|zen|librewolf)$]] })
qv.window_rule("tag -default-opacity", { tag = [[chromium-based-browser]] })
qv.window_rule("tag -default-opacity", { tag = [[firefox-based-browser]] })
qv.window_rule("tile on", { tag = [[chromium-based-browser]] })
qv.window_rule("opacity 1.0 0.985", { tag = [[chromium-based-browser]] })
qv.window_rule("opacity 1.0 0.985", { tag = [[firefox-based-browser]] })
qv.window_rule("workspace special silent", { title = [[.*is sharing.*]] })

-- LocalSend and selection overlays.
qv.window_rule("float on", { class = [[^(Share|localsend)$]] })
qv.window_rule("center on", { class = [[^(Share|localsend)$]] })
qv.window_rule("size 1100 700", { class = [[^localsend$]] })
qv.layer_rule("no_anim on", { namespace = [[selection]] })
qv.layer_rule("no_anim on", { namespace = [[walker]] })

-- Picture-in-picture overlays.
qv.window_rule("tag +pip", { title = [[(Picture.?in.?[Pp]icture)]] })
qv.window_rule("tag -default-opacity", { tag = [[pip]] })
qv.window_rule("float on", { tag = [[pip]] })
qv.window_rule("pin on", { tag = [[pip]] })
qv.window_rule("size 600 338", { tag = [[pip]] })
qv.window_rule("keep_aspect_ratio on", { tag = [[pip]] })
qv.window_rule("border_size 0", { tag = [[pip]] })
qv.window_rule("opacity 1 1", { tag = [[pip]] })
qv.window_rule("move (monitor_w-window_w-40) (monitor_h*0.04)", { tag = [[pip]] })

-- qvOS gaming and Windows capabilities.
qv.window_rule("tag -default-opacity", { class = [[^qemu$]] })
qv.window_rule("opacity 1 1", { class = [[^qemu$]] })
qv.window_rule("fullscreen on", { class = [[^com\.libretro\.RetroArch$]] })
qv.window_rule("tag -default-opacity", { class = [[^com\.libretro\.RetroArch$]] })
qv.window_rule("opacity 1 1", { class = [[^com\.libretro\.RetroArch$]] })
qv.window_rule("idle_inhibit fullscreen", { class = [[^com\.libretro\.RetroArch$]] })
qv.window_rule("workspace name:G silent", { class = [[^([Ss]team|steamwebhelper|steam_app_[0-9]+)$]] })
qv.window_rule("float on", { class = [[^steam$]] })
qv.window_rule("center on", { class = [[^steam$]], title = [[^Steam$]] })
qv.window_rule("tag -default-opacity", { class = [[^steam.*$]] })
qv.window_rule("opacity 1 1", { class = [[^steam.*$]] })
qv.window_rule("size 1100 700", { class = [[^steam$]], title = [[^Steam$]] })
qv.window_rule("size 460 800", { class = [[^steam$]], title = [[^Friends List$]] })
qv.window_rule("idle_inhibit fullscreen", { class = [[^steam$]] })
qv.window_rule("idle_inhibit fullscreen", { class = [[GeForceNOW]] })
qv.window_rule("fullscreen on", { class = [[com.moonlight_stream.Moonlight]] })
qv.window_rule("idle_inhibit fullscreen", { class = [[com.moonlight_stream.Moonlight]] })

-- Terminal and media presentation.
qv.window_rule("tag +terminal", { class = [[^(Alacritty|kitty|com\.mitchellh\.ghostty|foot)$]] })
qv.window_rule("tag -default-opacity", { tag = [[terminal]] })
qv.window_rule("opacity 0.985 0.96", { tag = [[terminal]] })
qv.window_rule("tag -default-opacity", { class = [[^(mpv|imv)$]] })
qv.window_rule("opacity 1 1", { class = [[^(mpv|imv)$]] })

-- Webcam overlay used by screen recording.
qv.window_rule("float on", { title = [[^WebcamOverlay$]] })
qv.window_rule("pin on", { title = [[^WebcamOverlay$]] })
qv.window_rule("no_initial_focus on", { title = [[^WebcamOverlay$]] })
qv.window_rule("no_dim on", { title = [[^WebcamOverlay$]] })
qv.window_rule("move (monitor_w-window_w-40) (monitor_h-window_h-40)", { title = [[^WebcamOverlay$]] })

qv.window_rule("rounding 8", { tag = [[pop]] })
qv.window_rule("idle_inhibit always", { tag = [[noidle]] })
qv.window_rule("opacity 0.985 0.96", { tag = [[default-opacity]] })
