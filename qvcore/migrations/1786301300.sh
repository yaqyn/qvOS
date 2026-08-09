echo "Archive historical Omarchy config backups into qvOS state"

QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}
"$QVOS_PATH/qvcore/theme/migrate-config-root"
"$QVOS_PATH/qvcore/menu/install" --install
