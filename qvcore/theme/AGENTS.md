# qvOS Theme Workflow

Read this file completely when changing the Yaqyn theme, theme rendering,
custom-theme compatibility, backgrounds, appearance menus, or retired upstream
theme paths.

qvOS has one bundled product theme: `qvcore/theme/yaqyn/`. Users may copy Yaqyn,
install a compatible Omarchy-format Git theme, or link a compatible theme into
`~/.config/omarchy/themes/`. Keep one renderer for bundled and user themes; do
not restore the inherited source catalog or a second rendering system.

- `qvcore/theme/install` owns the source-independent runtime and removes only
  inherited stock-theme symlinks. Preserve real user directories, external
  links, and backups. It owns and may replace only the Yaqyn runtime link.
- `qvcore/theme/configure` is the single fresh-install owner. The inherited install
  stage delegates to it; qvOS install code must not repeat its mutations.
- Theme list, set, install, remove, update, and appearance providers read only
  the user theme directory. `qvcore/theme/name` is the shared slug validator.
- `qvcore/theme/backgrounds` opens only the validated current installed theme's
  user-background directory. Preserve compatible theme links, but never use
  unchecked `theme.name` content as a path component.
- Treat compatible themes as untrusted data. Git installs accept HTTPS or Git
  SSH only, clone shallowly, validate the complete payload before activation,
  reject internal links and special files, and never copy Git metadata into the
  rendered theme. Parse `colors.toml` through `qvcore/theme/validate`; never build
  executable template programs from unchecked theme values.
- Yaqyn is always present and cannot be installed over or removed. Removing an
  active custom theme first returns to Yaqyn without changing the background.
- Post-update refresh reinstalls Yaqyn and reapplies the selected compatible
  custom theme when it still exists; otherwise it falls back to Yaqyn.
- List promoted inherited files in `native-paths` and deliberately absent
  inherited files or directory prefixes in `retired-paths`. Keep both sorted,
  unique, and guarded by the upstream-boundary test.

Run `qvcore/theme/check`, Bash syntax, ShellCheck, the focused theme/menu/TUI tests,
and the full qvOS suite. Apply with `qvcore/theme/install`, reapply the prior theme
without changing its background, reconcile the menu, and inspect a fullscreen
screenshot. Never delete real user theme directories or external theme links
during source or live cleanup.
