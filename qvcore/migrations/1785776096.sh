echo "Promote desktop controls and power-profile rules to qvOS"
QVOS_PATH=${QVOS_PATH:-$HOME/.local/share/qvos}

"$QVOS_PATH/qvcore/config/migrate-runtime-root"
"$QVOS_PATH/qvcore/power/profile-rule" --existing
