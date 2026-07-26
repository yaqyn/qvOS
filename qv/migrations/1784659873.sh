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
  [[ -L $theme_path ]] || continue
  theme_target=$(readlink -f -- "$theme_path" 2>/dev/null || true)
  case $theme_target in
  "$OMARCHY_PATH/themes/"* | "$HOME/.local/share/qvos/theme/"*)
    rm -f -- "$theme_path" || migration_status=1
    ;;
  esac
done

"$OMARCHY_PATH/qv/theme/install" || migration_status=1

if [[ $(omarchy-theme-current) != "Yaqyn" ]]; then
  omarchy-theme-set "Yaqyn" || migration_status=1
fi

"$OMARCHY_PATH/qv/launcher/install" || migration_status=1
omarchy-restart-walker || migration_status=1
omarchy-plymouth-reset || migration_status=1

((migration_status == 0))
