# qvOS Waybar Workflow

Read this file completely when changing the Waybar configuration overlay,
runtime modules, refresh lifecycle, task routes, or post-update reconciliation.

`qvcore/waybar/refresh` singularly merges the reviewed inherited Waybar source
with `overrides.jsonc`. `qv-refresh-waybar` is the native command;
`omarchy-refresh-waybar` is a metadata-free compatibility adapter. Native qvOS
menus, TUI catalogs, hooks, and installed configuration use only qv routes.

`qvcore/waybar/toggle` owns visibility and the private `waybar-off` startup
flag as one rollback-aware action. Stop Waybar through the shared exact-process
helper and start it through the native restart owner. If either primary action
fails, restore the prior flag; notifications are best effort only. Never use a
broad or unconditional SIGKILL. Close the toggle-lock descriptor only in the
restart child so Waybar never inherits the lock while the owner retains its
transaction boundary through startup verification.

The overlay may replace only qvOS-owned keys and the clock module placement.
Preserve every unrelated inherited key so qvsync can review upstream Waybar
capability without maintaining a copied configuration. A reset backs up a
different active configuration, writes the merged result atomically, refreshes
the shared style through its configuration owner, and restarts Waybar only when
something changed. `--status` is read-only and must not rewrite or restart.

`qv-launch-task` is the native fallback for a classified qvOS task when the
checked TUI runtime is unavailable. Waybar task actions must use it; never
restore the retired `omarchy-launch-qvos-task` or
`omarchy-qvos-refresh-waybar` qvOS-in-Omarchy namespaces.

`install` deploys only the files listed in `runtime-paths` to
`~/.local/lib/qvos/waybar` through an atomic directory replacement. The runtime
contains only the clock and prayer modules; checks, policy, manifests, refresh
owners, hooks, and configuration overlays remain in the installed source.

List implementation-sized inherited departures in `native-paths`. Run
`qvcore/waybar/check`, the Waybar, menu, TUI owner, hooks, installer, CLI,
product, and upstream-overlay tests, Bash syntax, ShellCheck, JSON validation,
and the full qvOS suite. After source/live alignment, install the menu and TUI
payloads, run `qv-refresh-waybar --reset`, verify `--status`, active qv task
routes, and the running Waybar service. Take a screenshot only when appearance
changes; a command-route-only reconciliation should remain visually identical.
