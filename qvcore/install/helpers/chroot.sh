# The native qvOS ISO builder sets QVOS_CHROOT_INSTALL=1 for target chroot mode.
chrootable_systemctl_enable() {
  if [[ ${QVOS_CHROOT_INSTALL:-} == "1" ]]; then
    sudo systemctl enable "$1"
  else
    sudo systemctl enable --now "$1"
  fi
}

# Export the function so it's available in subshells
export -f chrootable_systemctl_enable
