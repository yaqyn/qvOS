# qvOS Waybar Workflow

Read this file completely when changing the Waybar configuration,
runtime modules, refresh lifecycle, task routes, or post-update reconciliation.

`qvcore/config/files/waybar/` is the singular complete Waybar configuration.
The inherited `default/waybar/` tree and former base-plus-overlay merge are
retired. Weather, idle, notification, Capture, update, menu, Voxtype, network,
prayer, and clock modules call one explicit qvOS owner each. Never restore an
Omarchy-named module, command, source path, or second configuration overlay.

`qvcore/waybar/refresh` validates the complete config and style before mutation,
then restores both through the shared atomic config owner. `qv-refresh-waybar`
is the native command; `omarchy-refresh-waybar` is a metadata-free compatibility
adapter. `--status` is read-only and succeeds only when both installed files
exactly match the native source. Restart Waybar only after a real successful
change.

`qvcore/waybar/toggle` owns visibility and the private `waybar-off` startup
flag as one rollback-aware action. Stop Waybar through the shared exact-process
helper and start it through the native restart owner. If either primary action
fails, restore the prior flag; notifications are best effort only. Never use a
broad or unconditional SIGKILL. Close the toggle-lock descriptor only in the
restart child so Waybar never inherits the lock while the owner retains its
transaction boundary through startup verification.

The complete config carries only supported qvOS modules. Review upstream
Waybar changes as capability input and port useful behavior deliberately; do
not merge upstream keys or recreate a copied base. A reset preserves different
active files through the shared backup transaction before restoring the native
source.

`qv-launch-task` is the native fallback for a classified qvOS task when the
checked TUI runtime is unavailable. Waybar task actions must use it; never
restore the retired `omarchy-launch-qvos-task` or
`omarchy-qvos-refresh-waybar` qvOS-in-Omarchy namespaces.

`install` deploys only the files listed in `runtime-paths` to
`~/.local/lib/qvos/waybar` through an atomic directory replacement. The runtime
contains only the clock and prayer modules; checks, policy, manifests, refresh
owners, hooks, and complete configuration remain in the installed source.

`idle-status` and `notification-status` are source-side presentation owners;
they never enter the minimal runtime payload. List implementation-sized
inherited departures in `native-paths`. Run
`qvcore/waybar/check`, the Waybar, menu, TUI owner, hooks, installer, CLI,
product, and upstream-overlay tests, Bash syntax, ShellCheck, JSON validation,
and the full qvOS suite. After source/live alignment, install the menu and TUI
payloads, run `qv-refresh-waybar --reset`, verify `--status`, active qv task
routes, and the running Waybar service. Take a screenshot only when appearance
changes; a command-route-only reconciliation should remain visually identical.
