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

# Validate the requested source before any privileged package or mirror change.
OMARCHY_REF="${OMARCHY_REF:-OS}"
OMARCHY_REPO="${OMARCHY_REPO:-Yaqyn-qvOS/qvOS}"
OMARCHY_TARGET="$HOME/.local/share/omarchy"
if [[ ! $OMARCHY_REPO =~ ^[[:alnum:]_.-]+/[[:alnum:]_.-]+$ ]]; then
  echo "Invalid qvOS GitHub repository: $OMARCHY_REPO" >&2
  exit 2
fi
if [[ ! $OMARCHY_REF =~ ^[[:alnum:]][[:alnum:]_./-]*$ ]] ||
  [[ $OMARCHY_REF == *".."* || $OMARCHY_REF == *"//"* ]]; then
  echo "Invalid qvOS Git ref: $OMARCHY_REF" >&2
  exit 2
fi
if [[ -e $OMARCHY_TARGET || -L $OMARCHY_TARGET ]]; then
  echo "qvOS source already exists at $OMARCHY_TARGET." >&2
  echo "Move it aside explicitly before starting a fresh installation." >&2
  exit 1
fi

# Set mirror based on branch
if [[ $OMARCHY_REF == "dev" ]]; then
  export OMARCHY_MIRROR=edge
  # shellcheck disable=SC2016
  echo 'Server = https://mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
elif [[ $OMARCHY_REF == "rc" ]]; then
  export OMARCHY_MIRROR=rc
  # shellcheck disable=SC2016
  echo 'Server = https://rc-mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
else
  export OMARCHY_MIRROR=stable
  # shellcheck disable=SC2016
  echo 'Server = https://stable-mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
fi

sudo pacman -Syu --noconfirm --needed git

echo -e "\nCloning qvOS from: https://github.com/${OMARCHY_REPO}.git"
echo -e "\e[32mUsing branch: $OMARCHY_REF\e[0m"
install -d "${OMARCHY_TARGET%/*}"
staging_root=$(mktemp -d "${OMARCHY_TARGET%/*}/.qvos-install-stage.XXXXXX")
cleanup() {
  rm -rf -- "$staging_root"
}
trap cleanup EXIT
git clone --quiet --single-branch --branch "$OMARCHY_REF" -- \
  "https://github.com/${OMARCHY_REPO}.git" "$staging_root/source"
[[ $(git -C "$staging_root/source" branch --show-current) == "$OMARCHY_REF" ]] || {
  echo "Cloned qvOS source did not select the requested branch." >&2
  exit 1
}
git -C "$staging_root/source" fsck --strict --no-progress >/dev/null
[[ -f $staging_root/source/install.sh ]] || {
  echo "Cloned qvOS source has no installer." >&2
  exit 1
}
mv -- "$staging_root/source" "$OMARCHY_TARGET"
trap - EXIT
cleanup

echo -e "\nInstallation starting..."
# shellcheck source=/dev/null
source "$OMARCHY_TARGET/install.sh"
