-- qvOS session services.
qv.autostart("uwsm-app -- hypridle")
qv.autostart("uwsm-app -- mako")
qv.autostart("! qv-toggle-enabled waybar-off && qv-restart-waybar")
qv.autostart("uwsm-app -- fcitx5 --disable notificationitem")
qv.autostart("qv-theme-bg-restore")
qv.autostart("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
qv.autostart("qv-first-run")
qv.autostart("qv-powerprofiles-init")
qv.autostart("qv-restart-monitor-watch")

-- Make the complete session environment available to slow-starting services.
qv.autostart("systemctl --user import-environment $(env | cut -d'=' -f 1)")
qv.autostart("dbus-update-activation-environment --systemd --all")

-- Run user hooks only after the base desktop has started.
qv.autostart("sleep 2 && qv-hook post-boot")
