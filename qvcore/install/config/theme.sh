# shellcheck shell=bash

"$QVOS_PATH/qvcore/theme/configure"
rm -f -- "$HOME/.config/chromium/SingletonLock" # otherwise archiso will own the chromium singleton

# Default Chromium to follow system appearance ("device") instead of dark.
"$QVOS_PATH/qvcore/browser/install-chromium-defaults"
