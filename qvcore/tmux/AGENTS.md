# qvOS Tmux Workflow

Read this file completely when changing the Tmux manager, saved session model,
default configuration, refresh lifecycle, or public Tmux routes.

`qvcore/tmux/qvos-tmux` is the only persistent-session manager. Recipes live
privately under `~/.config/qvos/tmux`, transient state lives under
`~/.local/state/qvos/tmux`, and concurrent changes serialize through its
feature lock. Preserve exact panes, commands, working directories, focus, and
geometry; never replay saved commands when attaching to an existing session.
The dedicated manager terminal requests tiled state through the sibling native
Hyprland runtime bridge. Tiling is secondary: a missing or rejected compositor
action must report briefly and continue into tmux instead of closing the window.

`qvcore/config/files/tmux/tmux.conf` is the singular default.
`qvcore/tmux/runtime-paths` publishes only the session manager under
`~/.local/lib/qvos/tmux`; policy, refresh, and native-path inventory remain in
the installed source and must not enter runtime.
`qvcore/tmux/refresh` rejects arguments, restores it through
`qvcore/config/refresh`, and reloads the server through the native desktop
restart owner only after the file succeeds.
`qv-refresh-tmux` owns command metadata; `omarchy-refresh-tmux` is a
metadata-free compatibility adapter. Native menus and TUI actions call qv.

Keep source and runtime paths independent, normalize ephemeral Codex launchers
to the canonical command, and preserve user recipes across install, update,
refresh, and removal. Treat a foreground process disappearing during `/proc`
inspection as an empty command, without emitting a procfs race diagnostic.
Verify Bash syntax, ShellCheck, adapter ownership,
refresh failure behavior, and `test/qvcore/qvos-tmux-test.sh`, then run the full
qvOS suite when shared configuration, desktop restart, or menu contracts move.
Every Tmux test or diagnostic must remove the inherited `TMUX` environment and
bind its own validated private `TMUX_TMPDIR` before its first Tmux command.
Never run `kill-server`, `kill-session`, or another mutating diagnostic against
an implicit socket from an agent or development shell; the user's live Tmux
server is outside test scope.
Tmux replaces control-character format separators under the C locale. Parse
machine records with printable delimiters whose leading fields have bounded
syntax, or query one field directly; never use tabs or another control byte in
`-F` output. The focused test exports `LC_ALL=C` so this contract cannot regress.
Node.js is a Mise-managed development runtime, not a qvOS base dependency.
Process-capture tests must synthesize the reviewed Node-shaped argument vector
with base tools and never require an activated Node channel. Wait boundedly for
the intended `/proc` argument vector and assert that transition before testing
normalization; the launcher shell is not valid capture evidence.
