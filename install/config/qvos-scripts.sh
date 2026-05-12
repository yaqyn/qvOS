# shellcheck shell=bash

# Install qvOS-owned helper scripts and optional TUI payloads.
mkdir -p "$HOME/.local/share/qvos"

if [[ -d $OMARCHY_PATH/qv/scripts ]]; then
  find "$OMARCHY_PATH/qv/scripts" -mindepth 1 -maxdepth 1 ! -name "tui" -exec cp -R {} "$HOME/.local/share/qvos/" \;
  find "$HOME/.local/share/qvos" -type f ! -name "README.md" -exec chmod +x {} \;
fi

if [[ -d $OMARCHY_PATH/qv/tui ]]; then
  rm -rf "$HOME/.local/share/qvos/tui"
  mkdir -p "$HOME/.local/share/qvos/tui"
  cp -R "$OMARCHY_PATH/qv/tui/." "$HOME/.local/share/qvos/tui/"
  find "$HOME/.local/share/qvos/tui" -type f \( -path "*/bin/*" -o -name "qvos-tui" \) -exec chmod +x {} \;
fi
