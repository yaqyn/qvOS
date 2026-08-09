# qvOS Theme Workflow

Read this file completely when changing the Yaqyn theme, theme rendering,
custom-theme compatibility, backgrounds, appearance menus, or retired upstream
theme paths.

qvOS has one bundled product theme: `qvcore/theme/yaqyn/`. Users may copy Yaqyn,
install a compatible Omarchy-format Git theme, or link a compatible theme into
`~/.config/qvos/themes/`. Keep one renderer for bundled and user themes; do
not restore the inherited source catalog or a second rendering system.
The bundled background and preview are identical copies of the user-approved
centered qvOS wordmark artwork. Keep graphical wallpaper assets here; terminal
art remains independently owned by `qvcore/branding/terminal-art.txt`.

The `~/.config/qvos/{themes,current,backgrounds,themed}` namespace owns all
theme data and active state. `qvcore/theme/migrate-config-root` moves each safe
legacy directory atomically after a complete conflict preflight, then leaves
only relative `~/.config/omarchy/` compatibility links. Preserve conflicts and
unrecognized links without partial migration. Omarchy-format describes the
accepted theme payload, never qvOS state ownership.
Native commands are `qv-theme-*` and `qv-plymouth-set-by-theme`; matching
`omarchy-*` files are metadata-free compatibility adapters only. Implement
behavior under `qvcore/theme/`, and keep native qvOS consumers off the adapters.
Built-in color templates live only under `qvcore/theme/templates/`;
`default/themed/` is retired. Preflight every built-in and user template before
rendering, keep user overrides first, reject unsafe paths and output names, and
publish each generated file atomically inside the staged theme.
The reserved `qvos-neovim.lua` output is always regenerated from the validated
palette (or an explicit user template) before activation, so official Neovim
follows Yaqyn and compatible imported themes without executing an imported
theme's editor code or downloading theme plugins.

- `qvcore/theme/install` owns the source-independent runtime and removes only
  inherited stock-theme symlinks. Preserve real user directories, external
  links, and backups. It owns and may replace only the Yaqyn runtime link.
- Every install and post-update path runs the config-root migration before
  reading or writing theme state. Native owners and installed configs use only
  `~/.config/qvos`; the old paths are compatibility links, never fallbacks.
- `qvcore/theme/configure` is the single fresh-install owner. The inherited install
  stage delegates to it; qvOS install code must not repeat its mutations.
- Theme list, set, install, remove, update, and appearance providers read only
  the user theme directory. `qvcore/theme/name` is the shared slug validator,
  and `qvcore/theme/validate` owns payload and optional-integration validation.
- `qvcore/theme/backgrounds` opens only the validated current installed theme's
  user-background directory. Preserve compatible theme links, but never use
  unchecked `theme.name` content as a path component.
- Treat theme paths, colors, and integration metadata as untrusted input. Git
  installs accept HTTPS or Git SSH only, clone shallowly, validate before
  activation, reject internal links and special files, and never copy Git
  metadata into the rendered theme. Themes still contain application config,
  so describe them as user-selected trusted content rather than a sandbox.
  Parse `colors.toml` through the validator; never interpolate theme values into
  source code or terminal control sequences. Never install an editor extension
  declared by an external theme. The explicit VS Code installer may install only
  the bundled, version-checked Yaqyn VSIX.
- `set-zed` derives one schema-valid local `qvos.json` from validated colors,
  updates only that qvOS-owned payload, seeds settings only when absent, and is
  inert when Zed is not installed. Do not restore Omazed, its hooks, logs,
  state, parser, or automatic application launch.
- Browser theme policy directories remain root-owned and non-writable. Their
  exact `color.json` leaf is desktop-user-owned. Preflight every installed
  browser before a bounded in-place update, verify readback, and restore every
  changed leaf on failure; an atomic rename cannot work across this ownership
  boundary and must not be emulated by weakening the directory.
- Yaqyn is always present and cannot be installed over or removed. Removing an
  active custom theme first returns to Yaqyn without changing the background.
- Theme runtime policy accepts only documented `QVOS_THEME_*` inputs; inherited
  environment names are not a compatibility ABI.
- Theme activation stages and validates a complete next tree, swaps it
  atomically, and preserves the prior tree until the name marker lands. Git
  updates require a clean checkout and restore the exact prior commit if the
  pulled payload fails validation.
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
