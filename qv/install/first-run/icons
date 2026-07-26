# shellcheck shell=bash

theme_name="qv-Papirus-Dark"
theme_dir="$HOME/.local/share/icons/$theme_name"
source_theme="/usr/share/icons/Papirus"
sizes=(16 22 24 32 48 64)

if [[ ! -d $source_theme ]]; then
  echo "Papirus icon theme not found; skipping qv icon overlay"
  exit 0
fi

rm -rf "$theme_dir"
mkdir -p "$theme_dir"

directories=""
for size in "${sizes[@]}"; do
  directory="${size}x${size}/places"
  mkdir -p "$theme_dir/$directory"

  if [[ -n $directories ]]; then
    directories="$directories,$directory"
  else
    directories="$directory"
  fi
done

{
  echo "[Icon Theme]"
  echo "Name=$theme_name"
  echo "Comment=qvOS Papirus-Dark with black folders"
  echo "Inherits=Papirus-Dark,hicolor"
  echo "Example=folder"
  echo "Directories=$directories"
  echo

  for size in "${sizes[@]}"; do
    directory="${size}x${size}/places"
    echo "[$directory]"
    echo "Context=Places"
    echo "Size=$size"
    echo "Type=Fixed"
    echo
  done
} >"$theme_dir/index.theme"

for size in "${sizes[@]}"; do
  source_dir="$source_theme/${size}x${size}/places"
  target_dir="$theme_dir/${size}x${size}/places"

  [[ -d $source_dir ]] || continue

  while IFS= read -r -d '' source_icon; do
    icon_file=$(basename "$source_icon")
    target_icon="folder${icon_file#folder-black}"

    ln -snf "$source_icon" "$target_dir/$target_icon"
  done < <(find "$source_dir" -maxdepth 1 -type f -name "folder-black*.svg" -print0)
done

gtk-update-icon-cache "$theme_dir" >/dev/null 2>&1 || true
gsettings set org.gnome.desktop.interface icon-theme "$theme_name"
