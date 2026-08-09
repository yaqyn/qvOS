# Show installation environment variables
gum log --level info "Installation Environment:"

env | grep -E "^(QVOS_PATH|QVOS_INSTALL|QVOS_REPO|QVOS_REF|QVOS_ONLINE_INSTALL|QVOS_INSTALL_LOG_FILE|OMARCHY_CHROOT_INSTALL|OMARCHY_USER_NAME|OMARCHY_USER_EMAIL|OMARCHY_MIRROR|USER|HOME)=" | sort | while IFS= read -r var; do
  gum log --level info "  $var"
done
