# qvOS keeps personal AI tools opt-in through qvCORE.
qvos_owner="$OMARCHY_PATH/qv/install/packaging/npx"
if [[ -f $qvos_owner ]]; then
  source "$qvos_owner"
  return
fi

omarchy-npx-install @openai/codex codex
omarchy-npx-install @google/gemini-cli gemini
omarchy-npx-install @github/copilot copilot
omarchy-npx-install opencode-ai opencode
omarchy-npx-install playwright playwright-cli
omarchy-npx-install @earendil-works/pi-coding-agent pi
omarchy-npx-install @kitlangton/ghui ghui
