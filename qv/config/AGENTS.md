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

`qv/config/refresh-hyprland` is the authoritative inventory of the remaining
specialized qvOS Hyprland sources under `qv/config/files/hypr/`. The inherited
refresh command installs native `config/hypr/bindings.conf` and
`config/hypr/hyprland.conf` before this owner reconciles the specialized
sources. Put only look, window, input, and future specialized config in the
`qv/` sublayer. Reconcile after refresh and verify tracked and installed config.

`qv/config/monitor-autodetect` owns display-scale reconciliation on fresh first
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
