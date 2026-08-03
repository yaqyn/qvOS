echo "Promote session configuration commands to qvOS"
QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}

"$QVOS_PATH/qvcore/config/migrate-runtime-root"
