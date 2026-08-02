# qvOS Theme Workflow

Read this file completely when changing the Yaqyn theme, theme rendering,
custom-theme compatibility, backgrounds, appearance menus, or retired upstream
theme paths.

qvOS has one bundled product theme: `qv/theme/yaqyn/`. Users may copy Yaqyn,
install a compatible Omarchy-format Git theme, or link a compatible theme into
`~/.config/omarchy/themes/`. Keep one renderer for bundled and user themes; do
not restore the inherited source catalog or a second rendering system.

- `qv/theme/install` owns the source-independent runtime and removes only
  inherited stock-theme symlinks. Preserve real user directories, external
  links, and backups. It owns and may replace only the Yaqyn runtime link.
- `qv/theme/configure` is the single fresh-install owner. The inherited install
  stage delegates to it; qvOS install code must not repeat its mutations.
- Theme list, set, install, remove, update, and appearance providers read only
  the user theme directory. `qv/theme/name` is the shared slug validator.
- Yaqyn is always present and cannot be installed over or removed. Removing an
  active custom theme first returns to Yaqyn without changing the background.
- Post-update refresh reinstalls Yaqyn and reapplies the selected compatible
  custom theme when it still exists; otherwise it falls back to Yaqyn.
- List promoted inherited files in `native-paths` and deliberately absent
  inherited files or directory prefixes in `retired-paths`. Keep both sorted,
  unique, and guarded by the upstream-boundary test.

Run `qv/theme/check`, Bash syntax, ShellCheck, the focused theme/menu/TUI tests,
and the full qvOS suite. Apply with `qv/theme/install`, reapply the prior theme
without changing its background, reconcile the menu, and inspect a fullscreen
screenshot. Never delete real user theme directories or external theme links
during source or live cleanup.
