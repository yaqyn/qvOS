# Copy the qvOS defaults into the user configuration.
mkdir -p ~/.config
cp -a "$QVOS_PATH/qvcore/config/files/." ~/.config/

# Use the qvOS default bashrc.
cp "$QVOS_PATH/default/bashrc" ~/.bashrc
