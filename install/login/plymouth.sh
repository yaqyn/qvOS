if [[ $(plymouth-set-default-theme) != "omarchy" ]]; then
  sudo cp -r "$OMARCHY_PATH/default/plymouth" /usr/share/plymouth/themes/omarchy/
  sudo plymouth-set-default-theme omarchy
fi
