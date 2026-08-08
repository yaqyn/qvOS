echo "Migrate menu, Walker, and Share commands to qvOS ownership"

QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}
"$QVOS_PATH/qvcore/config/migrate-runtime-root"
