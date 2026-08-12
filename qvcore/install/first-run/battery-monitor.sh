if qv-battery-present; then
  qv-powerprofiles-set battery || true

  # Enable battery monitoring timer for low battery notifications
  systemctl --user enable --now qvos-battery-monitor.timer
else
  qv-powerprofiles-set ac || true
fi
