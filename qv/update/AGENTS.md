# qvOS Update Workflow

Read this file completely when changing qvOS source updates, the public update
wrapper, update stages, update failure handling, or reboot handoff.

`qv/update/update-source` owns source synchronization. The public inherited
command is a thin compatibility adapter. Require a clean non-symbolic checkout
on branch `OS`, accept only the official qvOS origin, and pull `origin/OS` with
fast-forward-only semantics and bounded network time. Never autostash, reset,
merge another branch, or conceal source changes. Always restore Hyprland error
reporting after an attempted pull.

`qv/update/qvos-update` owns product preflight and presentation, then delegates
once to the update pipeline. Its read-only check must reject a dirty or non-OS
live checkout before authorization. Package operations, migrations, hooks, and
reboot behavior remain discrete pipeline stages; do not duplicate them in the
wrapper.

Run `qv/update/check`, Bash syntax, ShellCheck, the focused update and source
lifecycle tests, and the full qvOS suite. A source-only audit must not invoke
the interactive updater or package upgrades. Live verification requires a
clean checkout and exact development/live commit parity.
