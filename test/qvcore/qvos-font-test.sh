#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_home="$test_root/home"
test_bin="$test_root/bin"
config_root="$test_home/.config"
runtime_root="$test_root/runtime"
log="$test_root/integrations.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$runtime_root" \
  "$config_root"/{alacritty,kitty,ghostty,foot,hypr,waybar,swayosd,fontconfig}

install -m 0755 /dev/stdin "$test_bin/fc-list" <<'SCRIPT'
#!/bin/bash
printf '%s\n' \
  'MesloLGL Nerd Font' \
  'JetBrainsMono Nerd Font' \
  'Noto Color Emoji' \
  'MesloLGL Nerd Font'
SCRIPT
for command in qv-restart-waybar qv-restart-swayosd qv-hook; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
printf '%s\t%s\n' "${0##*/}" "$*" >>"$QVOS_FONT_TEST_LOG"
SCRIPT
done
for command in pkill pgrep notify-send; do
  install -m 0755 /dev/stdin "$test_bin/$command" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
done

install -m 0644 /dev/stdin "$config_root/alacritty/alacritty.toml" <<'EOF'
[font]
size = 9
[font.normal]
family = "JetBrainsMono Nerd Font"
[font.bold]
family = "JetBrainsMono Nerd Font"
[font.italic]
family = "JetBrainsMono Nerd Font"
EOF
printf '%s\n' 'font_family JetBrainsMono Nerd Font' >"$config_root/kitty/kitty.conf"
printf '%s\n' 'font-family = "JetBrainsMono Nerd Font"' >"$config_root/ghostty/config"
printf '%s\n' 'font=JetBrainsMono Nerd Font:size=11:weight=medium' >"$config_root/foot/foot.ini"
printf '%s\n' '  font_family = JetBrainsMono Nerd Font' >"$config_root/hypr/hyprlock.conf"
printf '%s\n' "  font-family: 'JetBrainsMono Nerd Font';" >"$config_root/waybar/style.css"
printf '%s\n' "font-family: 'JetBrainsMono Nerd Font';" >"$config_root/swayosd/style.css"
install -m 0644 /dev/stdin "$config_root/fontconfig/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any"><string>monospace</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>JetBrainsMono Nerd Font</string>
      <string>Noto Naskh Arabic</string>
    </edit>
  </match>
</fontconfig>
EOF
chmod 0600 "$config_root/waybar/style.css"

export HOME="$test_home"
export PATH="$test_bin:/usr/bin"
export QVOS_PATH="$root"
export QVOS_FONT_CONFIG_ROOT="$config_root"
export QVOS_FONT_TEST_LOG="$log"
export XDG_RUNTIME_DIR="$runtime_root"

qv_font_list=$("$root/bin/qv-font-list")
[[ $qv_font_list == $'JetBrainsMono Nerd Font\nMesloLGL Nerd Font' ]] ||
  fail "font list is not exact, filtered, sorted, and unique"
[[ $("$root/bin/qv-font-current") == "JetBrainsMono Nerd Font" ]] ||
  fail "current font parsing"
[[ $("$root/bin/omarchy-font-current") == "JetBrainsMono Nerd Font" ]] ||
  fail "compatibility current-font adapter"

before_mode=$(stat -c '%a' "$config_root/waybar/style.css")
"$root/bin/qv-font-set" "MesloLGL Nerd Font"
[[ $("$root/bin/qv-font-current") == "MesloLGL Nerd Font" ]] ||
  fail "font transaction readback"
[[ $(stat -c '%a' "$config_root/waybar/style.css") == "$before_mode" ]] ||
  fail "font transaction changed a config mode"
[[ $(grep -c 'family = "MesloLGL Nerd Font"' "$config_root/alacritty/alacritty.toml") == "3" ]] ||
  fail "Alacritty font update"
grep -Fqx 'font_family MesloLGL Nerd Font' "$config_root/kitty/kitty.conf" ||
  fail "Kitty font update"
grep -Fqx 'font-family = "MesloLGL Nerd Font"' "$config_root/ghostty/config" ||
  fail "Ghostty font update"
grep -Fqx 'font=MesloLGL Nerd Font:size=11:weight=medium' "$config_root/foot/foot.ini" ||
  fail "Foot settings were not preserved"
grep -Fqx '  font_family = MesloLGL Nerd Font' "$config_root/hypr/hyprlock.conf" ||
  fail "Hyprlock font update"
grep -Fqx '  font-family: "MesloLGL Nerd Font";' "$config_root/waybar/style.css" ||
  fail "Waybar font update"
grep -Fqx 'font-family: "MesloLGL Nerd Font";' "$config_root/swayosd/style.css" ||
  fail "SwayOSD font update"
[[ $(xmlstarlet sel -t -v '(//match[test/string="monospace"]/edit/string)[1]' "$config_root/fontconfig/fonts.conf") == "MesloLGL Nerd Font" ]] ||
  fail "Fontconfig primary font update"
[[ $(xmlstarlet sel -t -v '(//match[test/string="monospace"]/edit/string)[2]' "$config_root/fontconfig/fonts.conf") == "Noto Naskh Arabic" ]] ||
  fail "Fontconfig Arabic fallback was overwritten"
grep -Fqx $'qv-restart-waybar\t' "$log" || fail "Waybar refresh"
grep -Fqx $'qv-restart-swayosd\t' "$log" || fail "SwayOSD refresh"
grep -Fqx $'qv-hook\tfont-set MesloLGL Nerd Font' "$log" || fail "native custom hook"
printf 'ok - font transaction updates every supported config without damaging fallbacks\n'

find "$config_root" -type f -print0 | sort -z | xargs -0 sha256sum >"$test_root/before-rejection"
if "$root/bin/qv-font-set" 'MesloLGL' >/dev/null 2>&1; then
  fail "substring font name was accepted"
fi
if "$root/bin/qv-font-set" $'MesloLGL Nerd Font\nmalicious' >/dev/null 2>&1; then
  fail "multiline font name was accepted"
fi
find "$config_root" -type f -print0 | sort -z | xargs -0 sha256sum >"$test_root/after-rejection"
cmp -s "$test_root/before-rejection" "$test_root/after-rejection" ||
  fail "rejected font input changed configuration"
printf 'ok - font selection requires one safe exact installed family\n'

cp -a "$config_root" "$test_root/config-before-malformed"
printf '%s\n' 'color: white;' >"$config_root/swayosd/style.css"
cp -a "$config_root" "$test_root/config-malformed"
if "$root/bin/qv-font-set" "JetBrainsMono Nerd Font" >/dev/null 2>&1; then
  fail "malformed required config was accepted"
fi
diff -qr "$config_root" "$test_root/config-malformed" >/dev/null ||
  fail "malformed preflight left partial changes"
rm -rf -- "$config_root"
cp -a "$test_root/config-before-malformed" "$config_root"
printf 'ok - malformed preflight leaves the entire config set untouched\n'

cp -a "$config_root" "$test_root/config-before-failed-commit"
install -m 0755 /dev/stdin "$test_bin/mv" <<'SCRIPT'
#!/bin/bash
destination=${!#}
if [[ $destination == */kitty/kitty.conf ]]; then
  exit 73
fi
exec /usr/bin/mv "$@"
SCRIPT
if "$root/bin/qv-font-set" "JetBrainsMono Nerd Font" >"$test_root/failed-commit.log" 2>&1; then
  fail "simulated atomic replacement failure succeeded"
fi
if ! diff -qr "$config_root" "$test_root/config-before-failed-commit" >/dev/null; then
  sed -n '1,120p' "$test_root/failed-commit.log" >&2
  diff -ru "$test_root/config-before-failed-commit" "$config_root" >&2 || true
  fail "failed commit did not restore every earlier config"
fi
rm -f -- "$test_bin/mv"
printf 'ok - failed atomic replacement restores the complete prior configuration\n'

mv "$config_root/waybar/style.css" "$config_root/waybar/style.real.css"
ln -s style.real.css "$config_root/waybar/style.css"
if "$root/bin/qv-font-current" >/dev/null 2>&1; then
  fail "current-font reader followed a symbolic link"
fi
printf 'ok - font owners reject unsafe user configuration paths\n'
