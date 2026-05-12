# shellcheck shell=bash

stop_install_log

show_qvos_finished_tui() {
  local tui="$OMARCHY_PATH/qv/tui/qvos-tui"

  if [[ -z ${OMARCHY_CHROOT_INSTALL:-} || ! -x $tui ]]; then
    return 1
  fi

  "$tui" --iso-finished --log "$OMARCHY_INSTALL_LOG_FILE"
}

remove_installer_sudoers() {
  if sudo test -f /etc/sudoers.d/99-omarchy-installer; then
    sudo rm -f /etc/sudoers.d/99-omarchy-installer &>/dev/null
  fi
}

if show_qvos_finished_tui; then
  remove_installer_sudoers
  touch /var/tmp/omarchy-install-completed
  exit 0
fi

echo_in_style() {
  echo "$1" | tte --canvas-width 0 --anchor-text c --frame-rate 640 print
}

clear
echo
tte -i ~/.local/share/omarchy/logo.txt --canvas-width 0 --anchor-text c --frame-rate 920 laseretch
echo

# Display installation time if available
if [[ -f $OMARCHY_INSTALL_LOG_FILE ]] && grep -q "Total:" "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null; then
  echo
  TOTAL_TIME=$(tail -n 20 "$OMARCHY_INSTALL_LOG_FILE" | grep "^Total:" | sed 's/^Total:[[:space:]]*//')
  if [[ -n $TOTAL_TIME ]]; then
    echo_in_style "Installed in $TOTAL_TIME"
  fi
else
  echo_in_style "Finished installing"
fi

remove_installer_sudoers

# Exit gracefully if user chooses not to reboot
if gum confirm --padding "0 0 0 $((PADDING_LEFT + 32))" --show-help=false --default --affirmative "Reboot Now" --negative "" ""; then
  # Clear screen to hide any shutdown messages
  clear

  if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    touch /var/tmp/omarchy-install-completed
    exit 0
  else
    sudo reboot 2>/dev/null
  fi
fi
