echo "Migrate the inherited Mise Node.js channel to LTS"
# shellcheck disable=SC1090

QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}
QVOS_MISE_MODE=migrate-node-lts
source "$QVOS_PATH/qvcore/install/config/mise-work.sh"
