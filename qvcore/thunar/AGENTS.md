# qvOS Thunar Workflow

Read this file completely when changing Thunar launch, plugins, custom actions,
desktop activation, or installed Thunar state.

`qvcore/thunar/launch` is the one runtime launcher. It refreshes a private
plugin view without the wallpaper plugin, then calls the absolute system
binary so the local compatibility command cannot recurse. `install` owns the
exact `~/.local/bin/thunar` link and the user systemd drop-in that routes D-Bus
activation through the same launcher. Refuse foreign objects at either owned
path. Reload only a reachable user manager that reports the same `HOME` through
the shared config probe; a fresh chroot stages the drop-in for first login.

Keep custom-action mutation in `actions.sh` and reconcile only named qvOS
actions. Preserve valid foreign actions and optional Proton or Devel actions.
The Transcode action accepts one regular selected file and launches the native
`qv-transcode` owner through the qvOS presentation route with exact arguments.
Fresh qvOS never creates the retired desktop file, user unit, D-Bus services,
copied launcher, or plugin-link tree. Current reconciliation never scans or
deletes those historical paths; preserve all foreign state.

After changes, run Bash syntax and ShellCheck, the Thunar and desktop-install
tests, then the full qvOS suite. On live apply, run the desktop owner, reload
the user service manager, verify the command link and drop-in, and confirm no
active config points at a retired runtime root.
