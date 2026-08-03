# qvOS Branding Promotion Workflow

Read this file completely when changing visible qvOS identity, inherited
branding copy, session metadata, installer labels, terminal titles, or branding
assets.

`qvcore/branding/` owns product identity during the native transition. Public copy
must say qvOS. Use Omarchy only for truthful upstream attribution, an exact
legacy compatibility match, or historical migration evidence; never expose it
as the installed product name.

About, screensaver, and terminal-logo behavior lives in this directory. Their
inherited `omarchy-*` commands are metadata-only compatibility adapters, and
qvOS-owned consumers call the branding owners directly.
The shared floating-terminal route is likewise a direct adapter to
qvcore/presentation/run; its owner preserves exact argument boundaries and the
single-string legacy route without retaining a second launcher implementation.

- Do not rename lowercase `omarchy-*` commands, `OMARCHY_*` variables, package
  repositories, state paths, app IDs, or compatibility filenames in a branding
  change. Internal renaming is a later atomic migration.
- Keep theme and binding behavior with their domain owners. Branding may change
  their visible labels but must not redesign or duplicate those systems.
- List every promoted inherited branding path in `native-paths`, sorted and
  unique. A listed path becomes qvOS-owned and must differ intentionally from
  the current upstream target. Never list qvOS-only source or a thin seam
  already audited by the transition guard.
- Preserve exact legacy identifiers only in matching or migration logic. New
  output, metadata, notifications, help, logs, and screenshots use qvOS.

Run `qvcore/branding/check`, Bash syntax and ShellCheck for changed shell, focused
CLI/menu/product tests, and the full qvOS suite. Apply changed desktop and boot
metadata through their existing owners, then capture and inspect a fullscreen
screenshot for every changed visible desktop surface.
