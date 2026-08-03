echo "Migrate qvOS source and runtime ownership"
QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}

"$QVOS_PATH/qvcore/install/migrate-source-root"
"$QVOS_PATH/qvcore/config/migrate-runtime-root"
