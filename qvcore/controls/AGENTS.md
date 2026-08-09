# qvOS Desktop Controls Workflow

Read this file completely when changing audio switching, display or keyboard
brightness, desktop notifications, notification silencing, or SwayOSD
presentation.

`qvcore/controls/` owns these user-session controls. Public `qv-*` commands
carry metadata; matching `omarchy-*` files are metadata-free compatibility
adapters only. qvOS bindings and native owners call the native command or
owner. Keep the focused-monitor lookup as a reviewed inherited Hyprland ABI
until that complete domain moves.

`qvcore/controls/notification/mako-core.ini` is the singular shared Mako
policy included by Yaqyn and compatible custom-theme templates. It may call
only native qvOS routes. `default/mako/` is retired and listed in this owner's
`retired-paths` manifest.

Validate bounded values before hardware or session mutation, preserve exact
arguments, and fail clearly when no compatible device exists. Treat hardware
LED feedback as best effort only after the real audio mutation succeeds. Use
one shared OSD client owner and direct owner-to-owner calls; never duplicate
progress calculations or rebuild command strings.

Notification silencing reads the current Mako mode, toggles exactly
`do-not-disturb`, verifies the opposite state, and rolls back on disagreement.
Notify and refresh the Waybar indicator only after the state is verified; both
are best-effort presentation, not evidence of mutation success.

List every promoted inherited route in `native-paths` and every removed source
prefix in `retired-paths`, sorted and unique. Run
`qvcore/controls/check`, the focused controls suite, binding/config checks,
Bash syntax and ShellCheck, then the full qvOS suite. Hardware fixtures use
`QVOS_CONTROLS_TESTING=1`; never point a test override at live sysfs or device
trees.
