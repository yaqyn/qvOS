-- qvOS session services.
-- Publish only UWSM's compositor-variable allowlist. UWSM also owns cleanup
-- when the graphical session stops.
qv.autostart("uwsm finalize")

qv.autostart("qv-launch-app -- hypridle")
qv.autostart("qv-launch-app -- mako")
qv.autostart("! qv-toggle-enabled waybar-off && qv-restart-waybar")
qv.autostart("qv-launch-app -- fcitx5 --disable notificationitem")
qv.autostart("qv-theme-bg-restore")
qv.autostart("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
qv.autostart("qv-first-run")
qv.autostart("qv-powerprofiles-init")
qv.autostart("qv-restart-monitor-watch")

-- Run user hooks only after the base desktop has started.
qv.autostart("sleep 2 && qv-hook post-boot")
