#!/bin/bash

set -e

# Set install mode to online since boot.sh is used for curl installations
export OMARCHY_ONLINE_INSTALL=true

ansi_art='
  ██████  ██    ██  ██████  ███████
 ██    ██ ██    ██ ██    ██ ██
 ██    ██ ██    ██ ██    ██ ███████
 ██ ▄▄ ██  ██  ██  ██    ██      ██
  ██████    ████    ██████  ███████
     ▀▀'

clear
echo -e "\n$ansi_art\n"

# Use a custom branch if instructed, otherwise install the qvOS product branch.
OMARCHY_REF="${OMARCHY_REF:-OS}"

# Set mirror based on branch
if [[ $OMARCHY_REF == "dev" ]]; then
  export OMARCHY_MIRROR=edge
  echo 'Server = https://mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
elif [[ $OMARCHY_REF == "rc" ]]; then
  export OMARCHY_MIRROR=rc
  echo 'Server = https://rc-mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
else
  export OMARCHY_MIRROR=stable
  echo 'Server = https://stable-mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
fi

sudo pacman -Syu --noconfirm --needed git

# Use a custom repository if specified, otherwise install qvOS.
OMARCHY_REPO="${OMARCHY_REPO:-Yaqyn-qvOS/qvOS}"

echo -e "\nCloning qvOS from: https://github.com/${OMARCHY_REPO}.git"
echo -e "\e[32mUsing branch: $OMARCHY_REF\e[0m"
rm -rf ~/.local/share/omarchy/
git clone --branch "$OMARCHY_REF" "https://github.com/${OMARCHY_REPO}.git" ~/.local/share/omarchy >/dev/null

echo -e "\nInstallation starting..."
source ~/.local/share/omarchy/install.sh
