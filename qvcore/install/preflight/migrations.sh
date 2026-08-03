QVOS_MIGRATIONS_STATE_PATH=~/.local/state/qvos/migrations
mkdir -p "$QVOS_MIGRATIONS_STATE_PATH"

for file in "$QVOS_PATH"/migrations/*.sh; do
  touch "$QVOS_MIGRATIONS_STATE_PATH/$(basename "$file")"
done
