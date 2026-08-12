# qvOS Shell Workflow

Read this file completely when changing Bash startup, aliases, completion,
Readline behavior, shell environment, or existing-user Bash reconciliation.

`qvcore/shell/files/` owns the fresh Bash configuration and
`qvcore/shell/aliases` is the single alias source. `install` deploys that alias
source to the source-independent runtime and reconciles only exact qvOS source
lines in an existing `.bashrc`. Preserve every unrelated user line, reject
linked or foreign paths, preserve a changed existing file privately under
`~/.local/state/qvos/shell-backups`, publish atomically, and never place
recovery files beside `.bashrc`. Do not rewrite exact runtime or Bash content.
Historical Omarchy and retired qvOS source lines are not active migration input
and must remain unrecognized.

The default shell remains small. Do not restore raw drive-formatting helpers,
pattern-based process killing, forced worktree deletion, legacy tmux layouts,
duplicate Transcode wrappers, or development-tool aliases. Those capabilities
belong to their validated qvOS domain owners or an optional Development
integration. `cy` and `hx` are the intentional qvOS aliases.

Completion prefers the native `qv` frontend and supports `omarchy` only as the
external compatibility command. Native shell files use only `QVOS_PATH`;
`OMARCHY_PATH` is retired and must not be exported into shell or desktop
sessions. The exact installed-source link remains the bounded path-level
compatibility seam.
The inherited top-level `default/bash/` and `default/bashrc` sources are
retired and must remain absent.

Run `qvcore/shell/check`, Bash syntax and ShellCheck, the shell, install,
source-lifecycle, product, CLI, Transcode, and upstream-overlay tests, then the
full qvOS suite. After live alignment, run `qvcore/shell/install` and verify
exact native source-line deduplication, backup, runtime parity, permissions,
and a clean interactive Bash startup without changing unrelated user content.
