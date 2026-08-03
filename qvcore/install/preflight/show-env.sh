# Show installation environment variables
gum log --level info "Installation Environment:"

env | grep -E "^(QVOS_PATH|QVOS_INSTALL|QVOS_REPO|QVOS_REF|OMARCHY_CHROOT_INSTALL|OMARCHY_ONLINE_INSTALL|OMARCHY_USER_NAME|OMARCHY_USER_EMAIL|OMARCHY_MIRROR|OMARCHY_REPO|OMARCHY_REF|OMARCHY_PATH|USER|HOME)=" | sort | while IFS= read -r var; do
  gum log --level info "  $var"
done
