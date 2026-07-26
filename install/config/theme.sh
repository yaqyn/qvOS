# Setup user theme folder
mkdir -p ~/.config/omarchy/themes

# Chromium policy directory for theme
policy_group=$(id -gn)
sudo install -d -o root -g root -m 0755 /etc/chromium/policies/managed
sudo touch /etc/chromium/policies/managed/color.json
sudo chown "$USER:$policy_group" /etc/chromium/policies/managed/color.json
sudo chmod 0644 /etc/chromium/policies/managed/color.json

# Set initial theme
omarchy-theme-set "Yaqyn"
rm -rf ~/.config/chromium/SingletonLock # otherwise archiso will own the chromium singleton

# Set specific app links for current theme
mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme

mkdir -p ~/.config/mako
ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config

# Default Chromium to follow system appearance ("device") instead of dark
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' | sudo tee /usr/lib/chromium/initial_preferences >/dev/null
