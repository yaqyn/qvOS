# Place in each assistant's global skills directory so the Omarchy skill is available on first install
mkdir -p ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills
ln -sfn "$QVOS_PATH/default/omarchy-skill" ~/.agents/skills/omarchy
ln -sfn "$QVOS_PATH/default/omarchy-skill" ~/.claude/skills/omarchy
ln -sfn "$QVOS_PATH/default/omarchy-skill" ~/.codex/skills/omarchy
ln -sfn "$QVOS_PATH/default/omarchy-skill" ~/.pi/agent/skills/omarchy
