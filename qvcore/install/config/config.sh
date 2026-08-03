# Copy the qvOS defaults into the user configuration.
mkdir -p ~/.config
cp -R "$QVOS_PATH"/config/* ~/.config/

# Use the qvOS default bashrc.
cp "$QVOS_PATH/default/bashrc" ~/.bashrc
