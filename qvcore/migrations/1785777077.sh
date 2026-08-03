echo "Promote power telemetry and sleep guards to qvOS"
QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}

"$QVOS_PATH/qvcore/config/migrate-runtime-root"
