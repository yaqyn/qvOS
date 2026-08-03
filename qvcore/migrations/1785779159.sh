echo "Migrate Firefox Wayland environment to qvOS ownership"
QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}

"$QVOS_PATH/qvcore/browser/migrate-runtime-root"
