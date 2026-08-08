# qvOS Hyprland Config Workflow

Read this file completely when changing qvOS-owned Hyprland bindings, refresh
reconciliation, or installed Hyprland configuration.

`config/hypr/bindings.conf` is the single authoritative qvOS binding source.
There is no inherited binding layer and no qvOS binding overlay.

- Inspect it and `omarchy menu keybindings --print` before edits. If a key is
  occupied, report its action and owner and wait before replacing it; use
  neither `unbind` nor a second active source to override it.
- Keep `Super+Space` routed through `omarchy-menu apps`. It must open the shared
  qvOS surface in Apps mode and preserve its Tab switch to Menu.
- Rank access from simplest to most complex as `Super`, `Super+Shift`,
  `Super+Ctrl`, `Super+Shift+Ctrl`, `Super+Alt`, `Super+Ctrl+Alt`,
  `Super+Shift+Alt`, then `Super+Shift+Ctrl+Alt`. Use Ctrl for the contextual
  variant beside a base or Shift action; preserve a better semantic Alt pair
  when a mechanical swap would make access worse.
- Keep the special workspace on `Super+S` with window transfer on
  `Super+Ctrl+S`. Keep window states together on F: full screen, tiled full
  screen, floating, then pop-out in descending ease order.
- Letter keys use Family One (`SUPER` plus optional Shift/Ctrl) and Family Two
  (add Alt with the same variants). Inventories show qvOS-owned entries by
  family, a checkmark column, `—` for free slots, non-letter families, and a
  concise script index.
- After edits, check duplicate modifier/key pairs and executable targets, apply
  and compare the live file, reload Hyprland, require no config errors, and show
  the updated qvOS-only inventory.

`qvcore/config/refresh` is the singular atomic file-restoration transaction.
Its default source is `config/`; the internal `--owned` mode reads specialized
files from `qvcore/config/files/`. Validate a bounded relative path, reject
linked or escaping sources and non-file targets, skip exact matches, stage in
the destination directory, preserve a unique backup, and restore that backup
if publication fails. `qv-refresh-config` owns metadata and
`omarchy-refresh-config` is compatibility only. Native owners call the
transaction directly and never route back through the compatibility command.

`qvcore/config/refresh-hyprland` is the single complete Hyprland restore owner.
Its native command carries metadata and its matching Omarchy command is a
metadata-free compatibility adapter. The owner preflights the monitor
destination, installs native `config/hypr/` defaults through the shared refresh
transaction, reconciles the specialized qvOS sources under
`qvcore/config/files/hypr/`, detects the current display scale, then detects the
keyboard layout. Never copy an inherited file immediately before replacing the
same destination with a specialized owner. Put only look, window, input, and
future specialized config in the `qvcore/` sublayer. Reconcile after refresh
and verify tracked and installed config.

Promoted defaults under `config/` are native qvOS sources and must not be
duplicated under `qvcore/config/files/`. qvOS-managed user units use `qvos-*`
filenames under `config/systemd/user/` and execute one native owner under
`qvcore/config/`. `user-services` atomically deploys those units, preserves the
enabled and active state of exact inherited units, disables their old names,
and archives safe old files privately. First run and every post-update desktop
reconciliation invoke it; never restore an active `omarchy-*` unit.
Disable inherited timer and installable unit names before archiving them, but
stop static helper services directly; static units are not enablement targets.
Only manage the user systemd instance when `HOME` is the active account home.
Cross-home fixtures may deploy files but must never contact the real manager;
the test override accepts only an executable temporary `systemctl` fixture.

`config/fastfetch/config.jsonc` is the singular native Fastfetch source. It
reads `~/.config/qvos/branding/about.txt`, whose lifecycle belongs to
`qvcore/branding/install`. The former specialized Fastfetch copy and legacy
ANSI asset are retired; runtime-root migration rewrites only their exact source
paths and preserves the rest of an existing Fastfetch config.

`toggle-state` singularly migrates safe, user-owned toggle files from
`.local/state/omarchy/toggles` into the private
`.local/state/qvos/toggles` tree, rejects conflicts before mutation, installs
the inert flags file, and rewrites only the exact inherited Hyprland source
line with a backup. Toggle templates and command implementations live under
`qvcore/config/`; inherited `bin/omarchy-*` routes are metadata-bearing adapters
only. Keep state files private, validate names and ownership before mutation,
and preserve every compatible custom toggle during install and update.
Verify this lifecycle with `qvos-toggle-services-test.sh`, `qvcore/config/check`,
the first-run and desktop-install suites, `systemd-analyze verify` after live
alignment, and the full qvOS suite.

`migrate-runtime-root` changes only exact retired qvOS path and promoted command
literals in named active configs. Back up each changed regular user-owned file,
preserve all other content, refuse links and foreign ownership, and remain a
no-op after success. Keep its inherited migration stub thin and its
implementation native.

Capture bindings and Waybar actions use native `qv-capture-*` routes. The
recording indicator executes `qvcore/capture/status` directly, and active UWSM
examples use `QVOS_SCREENSHOT_DIR` and `QVOS_SCREENRECORD_DIR`. Migrate only
their exact inherited command, indicator, and variable literals.

Config and session commands use metadata-bearing `qv-*` adapters and one
owner here. Retain matching metadata-free `omarchy-*` files only as external
and saved-config compatibility routes. Native bindings, menus, sleep guards,
screensavers, reinstall flows, and TUI tasks must call the qv route.

`qvcore/config/timezone` owns both the direct searchable picker and the TUI-selected
mutation. Revalidate every selected zone against `timedatectl list-timezones`
immediately before sudo, return cancellation distinctly, and restart Waybar
only after the system change succeeds.

`qvcore/config/monitor-autodetect` owns display-scale reconciliation on fresh first
login and explicit Hyprland restore. Let Hyprland choose preferred modes,
automatic placement, and PPI-based per-monitor scale. Synchronize the global
toolkit scale from the internal display, then the focused or first active
display. Only touch Omarchy's generic `,preferred,auto,auto` catch-all; preserve
every explicit custom monitor layout. Reload Hyprland and require no config
errors after detection. Preflight an explicit restore before Omarchy overwrites
the monitor file, reject symbolic-link destinations, stop the complete restore
on any owner failure, and restore the pre-edit adaptive config if applying its
detected scale fails. Omarchy's explicit restore keeps the user's original
monitor file in its normal timestamped backup.
