echo "Install Code OSS and align the old qvOS editor defaults"

if omarchy-pkg-missing code; then
  omarchy-pkg-add code
fi

uwsm_defaults="$HOME/.config/uwsm/default"
if [[ -f $uwsm_defaults ]]; then
  sed -i \
    -e 's/^export EDITOR=code-oss$/export EDITOR=code/' \
    -e "s/^export VISUAL=code-oss$/export VISUAL=\"\$EDITOR\"/" \
    -e "s/^export SUDO_EDITOR=code-oss$/export SUDO_EDITOR=\"\$EDITOR\"/" \
    "$uwsm_defaults"
fi
