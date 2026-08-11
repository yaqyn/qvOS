# shellcheck shell=bash

# Show installation environment variables without persisting personal identity.
gum log --level info "Installation Environment:"

for name in \
  HOME \
  OMARCHY_CHROOT_INSTALL \
  QVOS_INSTALL \
  QVOS_INSTALL_LOG_FILE \
  QVOS_ONLINE_INSTALL \
  QVOS_PATH \
  QVOS_PROVIDER_CHANNEL \
  QVOS_REF \
  QVOS_REPO \
  QVOS_USER_EMAIL \
  QVOS_USER_NAME \
  USER; do
  [[ -v $name ]] || continue
  value=${!name}
  case $name in
  QVOS_USER_EMAIL | QVOS_USER_NAME)
    if [[ -n $value ]]; then
      value="[set]"
    else
      value="[empty]"
    fi
    ;;
  *)
    printf -v value '%q' "$value"
    ;;
  esac
  gum log --level info "  $name=$value"
done
