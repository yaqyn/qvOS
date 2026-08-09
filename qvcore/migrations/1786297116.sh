echo "Replace provider-branded app bundles with official packages"

QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}

official_packages=(
  walker
  elephant
  elephant-calc
  elephant-clipboard
  elephant-desktopapplications
  elephant-files
  elephant-menus
  elephant-providerlist
  elephant-symbols
  elephant-websearch
)
retired_packages=(
  omarchy-nvim
  omarchy-walker
  elephant-bluetooth
  elephant-runner
  elephant-todo
  elephant-unicode
)

"$QVOS_PATH/qvcore/packages/add" "${official_packages[@]}"
sudo pacman -D --asexplicit -- "${official_packages[@]}"

installed_retired=()
for package in "${retired_packages[@]}"; do
  if pacman -Q -- "$package" &>/dev/null; then
    installed_retired+=("$package")
  fi
done
if (( ${#installed_retired[@]} > 0 )); then
  sudo pacman -R --noconfirm -- "${installed_retired[@]}"
fi

for package in "${official_packages[@]}"; do
  pacman -Q -- "$package" &>/dev/null || {
    printf 'qvOS package migration: required package is missing: %s\n' \
      "$package" >&2
    exit 1
  }
done
for package in "${retired_packages[@]}"; do
  if pacman -Q -- "$package" &>/dev/null; then
    printf 'qvOS package migration: retired package remains: %s\n' \
      "$package" >&2
    exit 1
  fi
done
