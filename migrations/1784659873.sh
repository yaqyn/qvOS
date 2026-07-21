echo "Keep only the Yaqyn desktop and unlock themes"

migration_status=0
themes_dir="$HOME/.config/omarchy/themes"
legacy_themes=(
  catppuccin-latte
  catppuccin
  ethereal
  everforest
  flexoki-light
  gruvbox
  hackerman
  kanagawa
  lumon
  matte-black
  miasma
  nord
  orion
  osaka-jade
  qvos
  retro-82
  ristretto
  rose-pine
  tokyo-night
  vantablack
  white
)

for theme in "${legacy_themes[@]}"; do
  theme_path="$themes_dir/$theme"
  if [[ -e $theme_path || -L $theme_path ]]; then
    rm -rf -- "$theme_path" || migration_status=1
  fi
done

if [[ $(omarchy-theme-current) != "Yaqyn" ]]; then
  omarchy-theme-set "Yaqyn" || migration_status=1
fi

menus_dir="$HOME/.config/elephant/menus"
mkdir -p "$menus_dir"
ln -snf "$OMARCHY_PATH/default/elephant/omarchy_themes.lua" "$menus_dir/omarchy_themes.lua" || migration_status=1
ln -snf "$OMARCHY_PATH/default/elephant/omarchy_unlocks.lua" "$menus_dir/omarchy_unlocks.lua" || migration_status=1
omarchy-restart-walker || migration_status=1
omarchy-plymouth-reset || migration_status=1

((migration_status == 0))
