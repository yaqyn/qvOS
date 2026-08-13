# qvOS Config Workflow

Read this file completely when changing qvOS-owned Hyprland bindings, config
refresh reconciliation, or installed desktop configuration.

`qvcore/config/base/hypr/` is the singular source-side Hyprland Lua base. Its
typed helpers, session autostart, environment, appearance, and default window
and persistent workspace rules live in five readable `.lua` files.
Session autostart calls `uwsm finalize` once before launching desktop services;
UWSM alone publishes its bounded compositor-variable allowlist to systemd and
D-Bus and cleans it on session stop. Never import the complete compositor
environment or use `dbus-update-activation-environment --all`: either can
persist secrets, machine-local variables, and retired product state.
Workspaces 1 through 5 remain present for the protocol-native Waybar module;
Waybar does not own or recreate their lifecycle. `qvcore/config/files/hypr/` owns the
installed user-editable Lua entrypoint, bindings, monitors, input, environment,
appearance, and autostart leaves. There is no inherited base, `.conf` runtime,
fragment fan-out, binding layer, or qvOS overlay.

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
linked or escaping sources, unsafe target ancestors, and linked, foreign, or
writable targets; skip exact matches, stage in the destination directory,
serialize publication, preserve each replaced value
under private `~/.local/state/qvos/config-backups/refresh` state, and restore
that backup if publication fails. Never place refresh backups beside active
configuration. `qv-refresh-config` owns metadata and
`omarchy-refresh-config` is compatibility only. Native owners call the
transaction directly and never route back through the compatibility command.
The bounded path alphabet includes `@` for systemd template-instance
directories; traversal and unsafe paths remain invalid. The internal
`--preflight` mode performs the same source, target, parent, and recovery-state
checks without creating state, so multi-file owners can fail before their first
mutation. Missing-target publication never clobbers a concurrent writer.

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
`seed-files` is the complete base-config manifest and `seed` installs only its
missing entries under the shared refresh lock. It preflights the full manifest,
preserves every safe existing user file, rejects unsafe paths, and publishes
without clobbering a concurrent target. Feature-owned menu, user-service,
XCompose, and WirePlumber sources stay outside that manifest and are installed
only by their owner. Do not seed empty placeholder files; leave an application
on its own defaults until qvOS owns meaningful policy. Fresh qvOS never
pre-creates a Chromium profile or copies the entire source tree recursively
into a user's home.
The personal menu-extension seed lives at
`qvcore/config/files/qvos/extensions/menu.sh`; never recreate an installed
`~/.config/omarchy/extensions/menu.sh` source.
Coding-assistant configuration belongs to `qvcore/config/assistant/`; its local
workflow owns native skill links, the Pi extension, and exact inherited cleanup.
Never restore `default/omarchy-skill/`, `default/pi/`, or their installer leaves.
Official Neovim uses the small `qvcore/config/files/nvim/init.lua` seed and the
generated current-theme colorscheme; it never requires the provider editor
bundle, LazyVim, or downloaded theme plugins. The singular fresh-install and
explicit config-reset copy owns the seed; desktop reconciliation never scans or
rewrites an existing Neovim tree. Completed provider replacement and signature
state remain retired, while its historical private backup remains user-owned.
Never delete Neovim data or caches as part of config reconciliation.
XCompose and WirePlumber policy live in this tree; their inherited
`default/xcompose` and `default/wireplumber/` sources are retired. Rerunning
installation creates only a missing native XCompose seed and leaves an exact
native seed unchanged. Preserve every other customized regular file and reject
symbolic-link, non-file, and foreign-owned targets. Completed pre-release
include and restart-comment convergence is retired and never runs during fresh
installation or update.
`wireplumber-policy` singularly seeds the optional Bluetooth A2DP and ASUS soft
mixer leaves. It shares the config-refresh lock, validates every user-owned
directory, publishes without clobbering a concurrent target, preserves custom
regular files, and rejects links or foreign ownership. Hardware installer
leaves only select a policy; they never duplicate its write, erase WirePlumber
route state, or mutate a live mixer during image construction or reruns.
qvOS-managed user units use `qvos-*` filenames under its `systemd/user/`
subtree and execute one native owner under
`qvcore/config/`. `user-services` atomically deploys those native unit files
and reloads the active account manager only after a changed
deployment. First run and every post-update desktop reconciliation invoke it;
the retired inherited unit and backup scan is absent. Explicit config reset
preflights all units, restores them through the shared backup transaction, and
reloads the manager once only when a unit changed.
Only manage the user systemd instance when `HOME` is the active account home.
`user-systemd-lib` singularly verifies that the reachable manager reports that
same home. Fresh chroot and cross-home runs deploy unit files without contacting
a manager; first run activates them after the real session exists. The test
override accepts only an executable temporary `systemctl` fixture.
The native user-service inventory includes SwayOSD, battery monitoring,
internal-monitor recovery, and the static on-demand screensaver supervisor;
feature first-run leaves only enable installable native units and never rely on
the broad config seed. The screensaver supervisor is never enabled: Hypridle
starts it explicitly so a Hypridle restart cannot kill launcher cleanup. The
battery monitor keeps its one-shot notification flag only at
`$XDG_RUNTIME_DIR/qvos-battery-notified`; no inherited runtime flag is read,
migrated, or removed during normal monitoring.

`qvcore/config/files/fastfetch/config.jsonc` is the singular native Fastfetch source. It
reads `~/.config/qvos/branding/about.txt`, whose lifecycle belongs to
`qvcore/branding/install`. The former specialized Fastfetch copy, legacy ANSI
asset, and runtime-root rewrite layer are retired.

`toggle-state` singularly initializes and permissions the private
`.local/state/qvos/toggles` tree and its inert `flags.lua`. Toggle templates
and command implementations live under `qvcore/config/`; native `qv-*` routes
carry metadata and matching
`bin/omarchy-*` routes are metadata-free compatibility only. Keep state files
private, validate every ancestor and reject links before mutation, and
serialize changes through the shared toggle lock. A process launched while a
toggle transaction is locked must close that descriptor in the child so the
long-running process cannot retain it after the owner exits. Treat desktop
notifications as best effort after state publication, and preserve every
compatible custom toggle during install and update. A missing toggle directory
is inert and must not invalidate the desktop; an existing malformed toggle must
still fail visibly instead of being ignored.
Verify this lifecycle with `qvos-toggle-services-test.sh`, `qvcore/config/check`,
the first-run and desktop-install suites, `systemd-analyze verify` after live
alignment, and the full qvOS suite.

The general pre-public runtime-root rewriter and retired Hyprland overlay
manifest are removed after the only supported installation converged. Fresh
install and post-update reconciliation use current native sources and do not
scan or rewrite unrelated active user configuration. The native Lua input
source keeps both keyboard and pointer DPMS wake defaults enabled. Native theme
directories and their reviewed compatibility links remain exclusively owned by
`qvcore/theme/config-root`; current configuration never adopts historical
theme state.

Capture bindings and Waybar actions use native `qv-capture-*` routes. The
recording indicator executes `qvcore/capture/status` directly, and active UWSM
examples use `QVOS_SCREENSHOT_DIR` and `QVOS_SCREENRECORD_DIR`.

Config commands use metadata-bearing `qv-*` adapters and one owner here.
Desktop lock, logout, and wake owners live under `qvcore/desktop/session/`.
Interactive monitor, window, and workspace controls live under
`qvcore/desktop/hyprland/`; config owns their native bindings.
Retain matching metadata-free `omarchy-*` files only as external and
saved-config compatibility routes. Native bindings, menus, sleep guards,
screensavers, reinstall flows, and TUI tasks must call the qv route.

`qvcore/config/timezone` owns both the direct searchable picker and the TUI-selected
mutation. Revalidate every selected zone against `timedatectl list-timezones`
immediately before sudo, return cancellation distinctly, and restart Waybar
only after the system change succeeds.

`qvcore/config/monitor-autodetect` owns display-scale reconciliation in
`~/.config/hypr/monitors.lua` on fresh first
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

`qvcore/config/keyboard-layout` is the singular console-to-Hyprland input
translator used by fresh install and explicit Hyprland restore. It accepts only
one bounded `XKBLAYOUT` and optional `XKBVARIANT` from a regular vconsole file,
updates exactly one native Lua input entry under the shared config-refresh lock,
and publishes only through a same-directory atomic replacement after proving
the target did not change. An absent or empty variant removes a stale variant.
Preserve the target on malformed, duplicate, linked, foreign-owned, or
concurrent input; never edit the Lua config in place or implement layout
translation in a sourced installer leaf. Explicit Hyprland restore runs this
owner before display detection so the display owner's one final reload validates
and activates the complete restored configuration.
