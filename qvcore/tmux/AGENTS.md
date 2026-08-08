# qvOS Tmux Workflow

Read this file completely when changing the Tmux manager, saved session model,
default configuration, refresh lifecycle, or public Tmux routes.

`qvcore/tmux/qvos-tmux` is the only persistent-session manager. Recipes live
privately under `~/.config/qvos/tmux`, transient state lives under
`~/.local/state/qvos/tmux`, and concurrent changes serialize through its
feature lock. Preserve exact panes, commands, working directories, focus, and
geometry; never replay saved commands when attaching to an existing session.

`config/tmux/tmux.conf` is the singular default. `qvcore/tmux/refresh` rejects
arguments, restores it through `qvcore/config/refresh`, and reloads the server
through the native desktop restart owner only after the file succeeds.
`qv-refresh-tmux` owns command metadata; `omarchy-refresh-tmux` is a
metadata-free compatibility adapter. Native menus and TUI actions call qv.

Keep source and runtime paths independent, normalize ephemeral Codex launchers
to the canonical command, and preserve user recipes across install, update,
refresh, and removal. Verify Bash syntax, ShellCheck, adapter ownership,
refresh failure behavior, and `test/qvcore/qvos-tmux-test.sh`, then run the full
qvOS suite when shared configuration, desktop restart, or menu contracts move.
