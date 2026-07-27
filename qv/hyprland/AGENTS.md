# qvOS Hyprland Workflow

Read this file completely when changing qvOS-owned Hyprland bindings, refresh
reconciliation, or installed Hyprland configuration.

`qv/config/files/hypr/qv/bindings.conf` is authoritative for qvOS-owned
bindings.

- Inspect it and `omarchy menu keybindings --print` before edits. If a key is
  occupied, report its action and owner and wait before replacing it; use
  `unbind` for an override.
- Letter keys use Family One (`SUPER` plus optional Shift/Ctrl) and Family Two
  (add Alt with the same variants). Inventories show qvOS-owned entries by
  family, a checkmark column, `—` for free slots, non-letter families, and a
  concise script index. Mention inherited bindings only for conflicts or when
  requested.
- After edits, check duplicate modifier/key pairs and executable targets, apply
  and compare the live file, reload Hyprland, require no config errors, and show
  the updated qvOS-only inventory.

`qv/hyprland/refresh` is the authoritative inventory of installed qvOS
Hyprland sources under `qv/config/files/hypr/`. Put additive overrides in its
`qv/` sublayer where the include structure supports that; otherwise update the
owned top-level source. Reconcile after upstream refresh and verify tracked and
installed configuration.
