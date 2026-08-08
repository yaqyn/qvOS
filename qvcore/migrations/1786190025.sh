echo "Migrate custom hooks to qvOS ownership"

QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}
"$QVOS_PATH/qvcore/hooks/reconcile"
