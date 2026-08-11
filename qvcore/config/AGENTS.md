# qvOS Config Workflow

Read this file completely when changing qvOS-owned Hyprland bindings, config
refresh reconciliation, or installed desktop configuration.

`qvcore/config/base/hypr/` is the singular source-side Hyprland base. It owns
session autostart, environment, appearance, and all default window rules in
four readable files. `qvcore/config/files/hypr/` owns installed user-editable
configuration, including the single authoritative binding and input sources.
There is no inherited base, fragment fan-out, binding layer, or qvOS overlay.

Fresh qvOS has no fixed web-service bindings. Keep only generic browser,
private-browser, localhost, and prompted-website access; users may install and
bind their own Web Apps later.
Fresh config also omits Typora: it is neither base-owned nor offered by a qvOS
installer. Preserve existing user Typora configuration, but never restore its
retired bundled themes, desktop seed, or window rule.

Promoted desktop bindings and native autostart call `qv-*` routes. Matching
`omarchy-toggle-*` commands exist only as metadata-free saved-config
compatibility adapters after their feature owner is promoted.

- Inspect it and `omarchy menu keybindings --print` before edits. If a key is
  occupied, report its action and owner and wait before replacing it; use
  neither `unbind` nor a second active source to override it.
- Keep `Super+Space` routed through `qv-menu apps`. It must open the shared
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
It reads only `qvcore/config/files/`; the alternate top-level source and
`--owned` selector are retired. Validate a bounded relative path, reject
linked or escaping sources and non-file targets, skip exact matches, stage in
the destination directory, preserve a unique backup, and restore that backup
if publication fails. `qv-refresh-config` owns metadata and
`omarchy-refresh-config` is compatibility only. Native owners call the
transaction directly and never route back through the compatibility command.
The bounded path alphabet includes `@` for systemd template-instance
directories; traversal, links, escaping sources, and non-file targets remain
invalid.

`qvcore/config/refresh-hyprland` is the single complete Hyprland restore owner.
Its native command carries metadata and its matching Omarchy command is a
metadata-free compatibility adapter. The owner preflights the monitor
destination, restores every Hyprland default through the shared transaction
from the singular `qvcore/config/files/hypr/` installed source. The restored
main file loads only `qvcore/config/base/hypr/`, the native qvOS theme, and
user configuration before detecting display scale and keyboard layout. Never
restore a second source or overlay. Reconcile after refresh and verify tracked
and installed config.

Hypridle, Hyprlock, Hyprsunset, and SwayOSD each have one small refresh owner
here. Hypridle is a specialized native source under `qvcore/config/files/`;
its former top-level duplicate is retired. Every source lives under the same
native tree. Each owner rejects arguments, delegates file restoration to
`qvcore/config/refresh`, and invokes the native desktop restart owner only after
every file succeeds. Public `qv-refresh-*` commands carry metadata; matching
`omarchy-refresh-*` files are compatibility only. Native menus and TUI actions
always call the qv route.

All defaults installed under `~/.config` are native qvOS sources under
`qvcore/config/files/`. Bash startup and alias ownership lives separately
under `qvcore/shell/`; never restore it as a second config source here.
The personal menu-extension seed lives at
`qvcore/config/files/qvos/extensions/menu.sh`; never recreate an installed
`~/.config/omarchy/extensions/menu.sh` source.
Coding-assistant configuration belongs to `qvcore/config/assistant/`; its local
workflow owns native skill links, the Pi extension, and exact inherited cleanup.
Never restore `default/omarchy-skill/`, `default/pi/`, or their installer leaves.
Official Neovim uses the small `qvcore/config/files/nvim/init.lua` seed and the
generated current-theme colorscheme; it never requires the provider editor
bundle, LazyVim, or downloaded theme plugins. `qvcore/config/neovim` replaces a
recognized provider config only after staging the native seed and moves the
complete prior config into private qvOS state. It preserves unrecognized or
custom configs, rewrites only their exact inherited theme symlink, fails closed
on unsafe paths, and is idempotent. Never infer ownership from a filename alone
or delete Neovim data and caches as part of config reconciliation.
XCompose and WirePlumber policy live in this tree; their inherited
`default/xcompose` and `default/wireplumber/` sources are retired. Rerunning
installation may replace only a missing or exact prior qvOS-generated file.
In a customized XCompose file, migrate one exact inherited `qvos` or original
`omarchy` source include with a private adjacent backup; reject ambiguous
includes. Preserve other customized regular files and reject symbolic-link
targets.
qvOS-managed user units use `qvos-*` filenames under its `systemd/user/`
subtree and execute one native owner under
`qvcore/config/`. `user-services` atomically deploys those units, preserves the
enabled and active state of exact inherited units, disables their old names,
and archives safe old files privately. First run and every post-update desktop
reconciliation invoke it; never restore an active `omarchy-*` unit.
Disable inherited timer and installable unit names before archiving them, but
stop static helper services directly; static units are not enablement targets.
Only manage the user systemd instance when `HOME` is the active account home.
`user-systemd-lib` singularly verifies that the reachable manager reports that
same home. Fresh chroot and cross-home runs deploy unit files without contacting
a manager; first run activates them after the real session exists. The test
override accepts only an executable temporary `systemctl` fixture.

`qvcore/config/files/fastfetch/config.jsonc` is the singular native Fastfetch source. It
reads `~/.config/qvos/branding/about.txt`, whose lifecycle belongs to
`qvcore/branding/install`. The former specialized Fastfetch copy and legacy
ANSI asset are retired; runtime-root migration rewrites only their exact source
paths and preserves the rest of an existing Fastfetch config.

`toggle-state` singularly migrates safe, user-owned toggle files from
`.local/state/omarchy/toggles` into the private
`.local/state/qvos/toggles` tree, rejects conflicts before mutation, installs
the inert flags file, and rewrites only the exact inherited Hyprland source
line with a backup. Toggle templates and command implementations live under
`qvcore/config/`; native `qv-*` routes carry metadata and matching
`bin/omarchy-*` routes are metadata-free compatibility only. Keep state files
private, validate every ancestor and reject links before mutation, and
serialize changes through the shared toggle lock. A process launched while a
toggle transaction is locked must close that descriptor in the child so the
long-running process cannot retain it after the owner exits. Treat desktop
notifications as best effort after state publication, and preserve every
compatible custom toggle during install and update.
Verify this lifecycle with `qvos-toggle-services-test.sh`, `qvcore/config/check`,
the first-run and desktop-install suites, `systemd-analyze verify` after live
alignment, and the full qvOS suite.

`migrate-runtime-root` changes only exact retired qvOS path, session policy,
and promoted command literals in named active configs. Back up each changed
regular user-owned file, preserve all other content, refuse links and foreign
ownership, and remain a no-op after success. Keep its inherited migration stub
thin and its implementation native. It rewrites the former Hyprland base to
`qvcore/config/base/hypr/`, folds input into the installed user source, and
retires the former `hypr/qv` source line only when every present payload is an
exact known qvOS file listed in `retired-hypr-layer.psv`. Preserve modified
compatibility layers, and collapse duplicate exact native input source lines
created by older layered configs. Cleanup consumes the same manifest; never
duplicate its hash policy. No migrated file requires a systemd daemon reload.
Existing input configs missing a DPMS wake preference receive only the missing
keyboard or pointer default so either device can wake a dark display. Preserve
every explicit true or false value and all other custom input settings.
It also rewrites exact active terminal, lock-screen, preview-picker, SwayOSD,
and Waybar theme references from `.config/omarchy/current` to the native
`.config/qvos/current` owner, using the same adjacent-backup and idempotence
contract. Theme-directory movement and compatibility links remain exclusively
owned by `qvcore/theme/migrate-config-root`.

Capture bindings and Waybar actions use native `qv-capture-*` routes. The
recording indicator executes `qvcore/capture/status` directly, and active UWSM
examples use `QVOS_SCREENSHOT_DIR` and `QVOS_SCREENRECORD_DIR`. Migrate only
their exact inherited command, indicator, and variable literals.
The same migration rewrites exact retired Waybar weather, idle, notification,
and module identifiers to their singular native owners; customized values are
otherwise preserved.

Config commands use metadata-bearing `qv-*` adapters and one owner here.
Desktop lock, logout, and wake owners live under `qvcore/desktop/session/`.
Interactive monitor, window, and workspace controls live under
`qvcore/desktop/hyprland/`; config owns their native bindings and exact
saved-config migration only.
Retain matching metadata-free `omarchy-*` files only as external and
saved-config compatibility routes. Native bindings, menus, sleep guards,
screensavers, reinstall flows, and TUI tasks must call the qv route.

`qvcore/config/timezone` owns both the direct searchable picker and the TUI-selected
mutation. Revalidate every selected zone against `timedatectl list-timezones`
immediately before sudo, return cancellation distinctly, and restart Waybar
only after the system change succeeds.

`qvcore/config/monitor-autodetect` owns display-scale reconciliation on fresh first
login and explicit Hyprland restore. Let Hyprland choose preferred modes,
automatic placement, and PPI-based per-monitor scale. Synchronize the global
toolkit scale from the internal display, then the focused or first active
display. Only touch the generic `,preferred,auto,auto` catch-all; preserve
every explicit custom monitor layout. Reload Hyprland and require no config
errors after detection. Preflight an explicit restore before qvOS overwrites
the monitor file, reject symbolic-link destinations, stop the complete restore
on any owner failure, and restore the pre-edit adaptive config if applying its
detected scale fails. The explicit restore keeps the user's original
monitor file in its normal timestamped backup.
