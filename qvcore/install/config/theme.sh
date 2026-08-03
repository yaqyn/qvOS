# shellcheck shell=bash

"$QVOS_PATH/qvcore/theme/configure"
rm -f -- "$HOME/.config/chromium/SingletonLock" # otherwise archiso will own the chromium singleton

# Default Chromium to follow system appearance ("device") instead of dark
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' | sudo tee /usr/lib/chromium/initial_preferences >/dev/null
