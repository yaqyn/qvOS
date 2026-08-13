if qv-battery-present; then
  "$QVOS_PATH/qvcore/power/profile-rule"

  sudo systemctl enable power-profiles-daemon

  if [[ ${QVOS_CHROOT_INSTALL:-} != "1" ]]; then
    sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
  fi
fi
