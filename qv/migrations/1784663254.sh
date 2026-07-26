omarchy-pkg-add gnome-keyring || return 1

if [[ ! -f $HOME/.local/share/keyrings/Default_keyring.keyring ]] || [[ ! -f $HOME/.local/share/keyrings/default ]]; then
  bash "$OMARCHY_PATH/install/login/default-keyring.sh"
fi

sudo sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
sudo sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
