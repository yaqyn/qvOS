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
QVOS_REF="${QVOS_REF:-${OMARCHY_REF:-OS}}"
QVOS_REPO="${QVOS_REPO:-${OMARCHY_REPO:-Yaqyn-qvOS/qvOS}}"
QVOS_TARGET="$HOME/.local/share/qvos"
OMARCHY_COMPAT_TARGET="$HOME/.local/share/omarchy"
if [[ $QVOS_REPO != "Yaqyn-qvOS/qvOS" ]]; then
  echo "qvOS installation requires the official repository." >&2
  exit 2
fi
if [[ $QVOS_REF != "OS" ]]; then
  echo "qvOS installation requires the official OS branch." >&2
  exit 2
fi
if [[ -e $QVOS_TARGET || -L $QVOS_TARGET ||
  -e $OMARCHY_COMPAT_TARGET || -L $OMARCHY_COMPAT_TARGET ]]; then
  echo "qvOS source already exists under $HOME/.local/share." >&2
  echo "Move it aside explicitly before starting a fresh installation." >&2
  exit 1
fi

# qvOS has one installed channel and uses its credited upstream Stable mirror.
export OMARCHY_MIRROR=stable
# shellcheck disable=SC2016
echo 'Server = https://stable-mirror.omarchy.org/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null

sudo pacman -Syu --noconfirm --needed git

echo -e "\nCloning qvOS from: https://github.com/${QVOS_REPO}.git"
echo -e "\e[32mUsing branch: $QVOS_REF\e[0m"
install -d "${QVOS_TARGET%/*}"
staging_root=$(mktemp -d "${QVOS_TARGET%/*}/.qvos-install-stage.XXXXXX")
cleanup() {
  rm -rf -- "$staging_root"
}
trap cleanup EXIT
git clone --quiet --single-branch --branch "$QVOS_REF" -- \
  "https://github.com/${QVOS_REPO}.git" "$staging_root/source"
[[ $(git -C "$staging_root/source" branch --show-current) == "$QVOS_REF" ]] || {
  echo "Cloned qvOS source did not select the requested branch." >&2
  exit 1
}
git -C "$staging_root/source" fsck --strict --no-progress >/dev/null
[[ -f $staging_root/source/install.sh ]] || {
  echo "Cloned qvOS source has no installer." >&2
  exit 1
}
mv -- "$staging_root/source" "$QVOS_TARGET"
if ! ln -s qvos "$OMARCHY_COMPAT_TARGET"; then
  mv -- "$QVOS_TARGET" "$staging_root/source"
  echo "Could not create the inherited source compatibility link." >&2
  exit 1
fi
trap - EXIT
cleanup

echo -e "\nInstallation starting..."
# shellcheck source=/dev/null
source "$QVOS_TARGET/install.sh"
