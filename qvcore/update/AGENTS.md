# qvOS Update Workflow

Read this file completely when changing qvOS source updates, the public update
wrapper, update stages, update failure handling, or reboot handoff.

`qvcore/update/update-source` owns source synchronization. The public inherited
command is a thin compatibility adapter. Require a clean non-symbolic checkout
on branch `OS`, accept only the official qvOS origin, and pull `origin/OS` with
fast-forward-only semantics and bounded network time. Never autostash, reset,
merge another branch, or conceal source changes. Always restore Hyprland error
reporting after an attempted pull.
qvOS has one installed source channel: official `origin/OS`. The inherited
branch and channel switchers are retired; experimental upstream refs belong in
separate development checkouts and never mutate the installed OS.

`qvcore/update/qvos-update` owns product preflight and presentation, then delegates
once to the update pipeline. Its read-only check must reject a dirty or non-OS
live checkout before authorization. Package operations, migrations, hooks, and
reboot behavior remain discrete pipeline stages; do not duplicate them in the
wrapper.

`qvcore/update/restart` singularly detects post-update reboot and service-restart
requirements. Use only package-owned kernel images, inspect one running
Hyprland process safely, accept only exact restart-marker service slugs, and
clear each marker only after its restart owner succeeds. Delegate every reboot
choice to `qvcore/update/reboot-request`; never restore an inherited fallback.

Run `qvcore/update/check`, Bash syntax, ShellCheck, the focused update and source
lifecycle tests, and the full qvOS suite. A source-only audit must not invoke
the interactive updater or package upgrades. Live verification requires a
clean checkout and exact development/live commit parity.
