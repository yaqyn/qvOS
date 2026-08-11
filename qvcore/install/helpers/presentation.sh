# shellcheck shell=bash

# Ensure we have gum available
if ! command -v gum &>/dev/null; then
  qv-pkg-add gum
fi

# Prefer an inherited terminal descriptor. During ISO installation, the target
# user can inherit the live console while lacking permission to reopen
# /dev/tty. Every terminal probe is optional under the installer's strict
# error handling.
TERM_SIZE=""
if [[ -t 0 ]]; then
  TERM_SIZE=$(stty size 2>/dev/null || true)
elif [[ -r /dev/tty ]]; then
  TERM_SIZE=$(stty size 2>/dev/null </dev/tty || true)
fi

if [[ -n $TERM_SIZE ]]; then
  read -r TERM_HEIGHT TERM_WIDTH <<<"$TERM_SIZE"
  export TERM_HEIGHT TERM_WIDTH
else
  # Use predictable dimensions without a readable controlling terminal.
  export TERM_WIDTH=80
  export TERM_HEIGHT=24
fi

LOGO_PATH="$QVOS_PATH/qvcore/branding/terminal-art.txt"
LOGO_WIDTH=$(awk '{ if (length > max) max = length } END { print max+0 }' \
  "$LOGO_PATH" 2>/dev/null || echo 0)
LOGO_HEIGHT=$(wc -l <"$LOGO_PATH" 2>/dev/null || echo 0)

PADDING_LEFT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
((PADDING_LEFT >= 0)) || PADDING_LEFT=0
PADDING_LEFT_SPACES=$(printf "%*s" "$PADDING_LEFT" "")
export LOGO_PATH LOGO_WIDTH LOGO_HEIGHT PADDING_LEFT PADDING_LEFT_SPACES

# qvOS terminal colors for Gum controls.
export GUM_CONFIRM_PROMPT_FOREGROUND="6"     # Cyan for prompt
export GUM_CONFIRM_SELECTED_FOREGROUND="0"   # Black text on selected
export GUM_CONFIRM_SELECTED_BACKGROUND="2"   # Green background for selected
export GUM_CONFIRM_UNSELECTED_FOREGROUND="7" # White for unselected
export GUM_CONFIRM_UNSELECTED_BACKGROUND="0" # Black background for unselected
export PADDING="0 0 0 $PADDING_LEFT"         # Gum Style
export GUM_CHOOSE_PADDING="$PADDING"
export GUM_FILTER_PADDING="$PADDING"
export GUM_INPUT_PADDING="$PADDING"
export GUM_SPIN_PADDING="$PADDING"
export GUM_TABLE_PADDING="$PADDING"
export GUM_CONFIRM_PADDING="$PADDING"

clear_logo() {
  printf '\033[H\033[2J' # Clear screen and move cursor to top-left
  gum style --foreground 2 --padding "1 0 0 $PADDING_LEFT" "$(<"$LOGO_PATH")"
}
