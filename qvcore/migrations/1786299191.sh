echo "Restore keyboard and pointer display wake defaults"

QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}
"$QVOS_PATH/qvcore/config/migrate-runtime-root"
