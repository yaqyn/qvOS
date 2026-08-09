---
name: qvos
description: >
  Required for end-user qvOS desktop customization and installed-system
  configuration. Use for Hyprland, Waybar, Walker, terminal, Mako, wallpaper,
  theme, font, monitor, window-rule, keybinding, night-light, idle, lock-screen,
  screenshot, recording, reminder, workspace, display, and user-facing qv
  command work. Covers user configuration under ~/.config and the compatible
  theme ABI under ~/.config/omarchy. Excludes qvOS source development under
  ~/.local/share/qvos and repository development checkouts.
---

# qvOS Desktop Customization

Customize an installed qvOS system without modifying its tracked source.

## Safety boundary

- Treat `~/.local/share/qvos` as read-only. Read owners and defaults there, but
  never edit them for an end-user customization.
- Edit user state under `~/.config`, `~/.local/state/qvos`, or another
  feature-documented user path.
- Keep custom automation under `~/.config/qvos/hooks`.
- Keep compatible themes under `~/.config/omarchy/themes`. This path is qvOS's
  documented external-theme ABI.
- Read the current file, its source owner, and nearby patterns before editing.
- Preserve user changes and create a backup before a manual replacement.
- Ask before resetting configuration, replacing an occupied binding, removing
  data, installing packages, or making a privileged system change.

Do not use this skill for qvOS source development, migrations, ISO work, or
changes inside a qvOS repository. Follow that repository's `AGENTS.md` files.

## Native command discovery

Use the native `qv` frontend. Compatibility command names are not the product
interface.

```bash
qv commands
qv commands --json
qv <group> --help
qv <group> <command> --help
```

Inspect an implementation without changing it:

```bash
command -v qv-theme-set
sed -n '1,220p' "$(command -v qv-theme-set)"
```

Common routes:

| Task | Command |
|---|---|
| Refresh a component | `qv refresh <component>` |
| Refresh one config file | `qv refresh config <relative-path>` |
| Restart a desktop component | `qv restart <component>` |
| Toggle a feature | `qv toggle <feature>` |
| Manage themes | `qv theme <action>` |
| Install a repository package | `qv pkg add <package...>` |
| Install an explicit AUR package | `qv pkg aur add <package...>` |
| Capture the desktop | `qv capture <action>` |
| Inspect bounded diagnostics | `qv debug --no-sudo --print` |

## Source map

| Component | User configuration | Read-only qvOS source |
|---|---|---|
| Hyprland | `~/.config/hypr` | `qvcore/config/files/hypr`, `qvcore/config/base/hypr` |
| Waybar | `~/.config/waybar` | `qvcore/config/files/waybar` |
| Walker | `~/.config/walker` | `qvcore/config/files/walker` |
| Mako | `~/.config/mako` | `qvcore/controls/notification` |
| Terminals | `~/.config/<terminal>` | `qvcore/config/files/<terminal>` |
| Themes | `~/.config/omarchy/themes` | `qvcore/theme` |
| Hooks | `~/.config/qvos/hooks` | `qvcore/hooks` |

Resolve source paths beneath `~/.local/share/qvos` only for inspection.

## Working loop

1. Inspect the active user configuration and its qvOS source owner.
2. Identify whether the request is a direct edit, a native command, or a reset.
3. Check existing bindings, includes, services, and process ownership before
   changing shared desktop behavior.
4. Make the smallest user-scoped change.
5. Apply the component-specific reload or restart.
6. Validate the resulting configuration and report the backup path when one was
   created.

## Hyprland

The installed configuration normally contains:

```text
~/.config/hypr/
├── hyprland.conf
├── bindings.conf
├── monitors.conf
├── input.conf
├── looknfeel.conf
├── envs.conf
├── autostart.conf
├── hypridle.conf
├── hyprlock.conf
└── hyprsunset.conf
```

After every Hyprland edit, run:

```bash
hyprctl reload
hyprctl configerrors
```

Require an empty config-error result before calling the change valid.

### Keybindings

Inspect the complete current inventory first:

```bash
qv menu keybindings --print
```

If the requested modifier/key pair is occupied, tell the user its current
action and owner. Wait before replacing it unless the request explicitly
authorizes that exact replacement. Edit the singular active binding directly;
do not add an `unbind` overlay or a second binding source.

### Monitors

Inspect active outputs with `hyprctl monitors`, then edit
`~/.config/hypr/monitors.conf`. Preserve explicit layouts that the user did not
ask to change.

### Window rules

Window-rule syntax changes between Hyprland releases. Consult the current
official Hyprland window-rules documentation before writing a rule, then reload
and check configuration errors.

## Component application

| Change | Apply and verify |
|---|---|
| Hyprland | `hyprctl reload`; `hyprctl configerrors` |
| Waybar | `qv restart waybar` |
| Walker | `qv restart walker` |
| Terminal config | `qv restart terminal` when a running process must reload |
| Theme | `qv theme set <slug>` |
| Visual desktop change | `qv capture screenshot fullscreen save` and inspect it |

## Themes

Yaqyn is the only bundled qvOS theme. Create a custom theme by copying it:

```bash
mkdir -p ~/.config/omarchy/themes/my-theme
cp -a ~/.config/omarchy/themes/yaqyn/. \
  ~/.config/omarchy/themes/my-theme/
qv theme set my-theme
```

Alternatively install a compatible Git theme explicitly:

```bash
qv theme install <https-or-git-ssh-url>
```

Treat an external theme as user-selected configuration, not sandboxed content.
Never edit the bundled Yaqyn source for a personal customization.

## Hooks

Place user automation in `~/.config/qvos/hooks`. Keep arguments quoted and do
not duplicate qvOS system jobs. Common hooks include `theme-set`, `font-set`,
and `post-update`.

## Reminders

Use the native reminder owner directly:

```bash
qv reminder 15 "Pickup Jack"
qv reminder show
qv reminder clear
```

Convert natural-language durations to minutes and keep labels concise.

## Recovery and diagnostics

Obtain confirmation before a reset. Native refresh creates a backup:

```bash
qv refresh waybar
qv refresh hyprland
qv refresh config hypr/hyprlock.conf
```

Use bounded, non-interactive diagnostics:

```bash
qv debug --no-sudo --print
qv version
```

Do not upload diagnostics or expose machine identifiers, credentials, tokens,
private URLs, or user data.
