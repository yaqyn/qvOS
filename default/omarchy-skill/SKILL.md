---
name: omarchy
description: >
  REQUIRED for end-user customization of Linux desktop, window manager, or system config.
  Use when editing ~/.config/hypr/, ~/.config/waybar/, ~/.config/walker/,
  ~/.config/alacritty/, ~/.config/foot/, ~/.config/kitty/, ~/.config/ghostty/, ~/.config/mako/,
  or ~/.config/omarchy/. Triggers: Hyprland, window rules, animations, keybindings,
  monitors, gaps, borders, blur, opacity, waybar, walker, terminal config, themes,
  wallpaper, night light, idle, lock screen, screenshots, reminders, layer rules,
  workspace settings, display config, and user-facing omarchy commands. Excludes qvOS
  source development in ~/.local/share/qvos/ and `omarchy dev` workflows.
---

# qvOS Skill

Manage [qvOS](https://github.com/Yaqyn-qvOS/qvOS) Linux systems - a focused Arch distribution with Hyprland.

This skill is for end-user customization on installed systems.
It is not for contributing to qvOS source code.

## When This Skill MUST Be Used

**ALWAYS invoke this skill for end-user requests involving ANY of these:**

- Editing ANY file in `~/.config/hypr/` (window rules, animations, keybindings, monitors, etc.)
- Editing ANY file in `~/.config/waybar/`, `~/.config/walker/`, `~/.config/mako/`
- Editing terminal configs (alacritty, foot, kitty, ghostty)
- Editing ANY file in `~/.config/omarchy/`
- Window behavior, animations, opacity, blur, gaps, borders
- Layer rules, workspace settings, display/monitor configuration
- Themes, wallpapers, fonts, appearance changes
- User-facing `omarchy` commands (`omarchy theme ...`, `omarchy refresh ...`, `omarchy restart ...`, etc.)
- Screenshots, screen recording, reminders, night light, idle behavior, lock screen

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

**Do NOT use this skill for qvOS development tasks** (editing files in `~/.local/share/qvos/`, creating migrations, or running `omarchy dev ...` workflows).

## Critical Safety Rules

**For end-user customization tasks, NEVER modify anything in `~/.local/share/qvos/`** - but READING is safe and encouraged.

This directory contains qvOS source files managed by git. Any changes will be:
- Lost on next `omarchy update`
- Cause conflicts with upstream
- Break the system's update mechanism

```
~/.local/share/qvos/     # READ-ONLY - NEVER EDIT (reading is OK)
├── bin/                    # Source scripts (symlinked to PATH)
├── qvcore/config/files/    # Default config templates
├── default/                # System defaults
└── qvcore/                 # Native owners, installer, migrations, and Yaqyn
```

**Reading `~/.local/share/qvos/` is SAFE and useful** - do it freely to:
- Understand how qvOS commands work: `qv theme set --help` or `cat $(which qv-theme-set)`
- See default configs before customizing: `cat ~/.local/share/qvos/qvcore/config/files/waybar/config.jsonc`
- Inspect native owners before customizing their installed user config
- Reference default hyprland settings: `cat ~/.local/share/qvos/default/hypr/*`

**Always use these safe locations instead:**
- `~/.config/` - User configuration (safe to edit)
- `~/.config/omarchy/themes/<custom-name>/` - Custom themes (must be real directories)
- `~/.config/qvos/hooks/` - Custom automation hooks

If the request is to develop qvOS itself, this skill is out of scope. Follow repository development instructions instead of this skill.

## System Architecture

qvOS is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Arch Linux** | Base OS | `/etc/`, `~/.config/` |
| **Hyprland** | Wayland compositor/WM | `~/.config/hypr/` |
| **Waybar** | Status bar | `~/.config/waybar/` |
| **Walker** | App launcher | `~/.config/walker/` |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |
| **Mako** | Notifications | `~/.config/mako/` |
| **SwayOSD** | On-screen display | `~/.config/swayosd/` |

## Command Discovery

qvOS currently keeps the compatible `omarchy` CLI, which dispatches to
`omarchy-*` binaries via `omarchy <group> <action>`. Prefer this stable form
until the internal command migration is complete. The underlying binaries
remain safe to inspect for source.

```bash
# List every documented command and its summary
omarchy commands

# Show the commands inside a group
omarchy theme --help
omarchy refresh --help
omarchy restart --help

# Show help for a specific command (does not execute it)
omarchy theme set --help

# Machine-readable listing (binary, route, summary, args, aliases)
omarchy commands --json

# Read a command's source to understand it
cat $(which qv-theme-set)
```

### Command Groups

Run `omarchy --help` for the full list. The most common groups:

| Group | Purpose | Example |
|-------|---------|---------|
| `omarchy refresh` | Reset config to defaults (backs up first) | `omarchy refresh waybar` |
| `omarchy restart` | Restart a service/app | `omarchy restart waybar` |
| `omarchy toggle` | Toggle feature on/off | `omarchy toggle nightlight` |
| `omarchy theme` | Theme management | `omarchy theme set <name>` |
| `omarchy install` | Install optional software / packages | `omarchy install docker dbs` |
| `omarchy launch` | Launch apps | `omarchy launch browser` |
| `omarchy capture` | Screenshots and recordings | `omarchy capture screenshot` |
| `qv reminder` | Desktop notification reminders | `qv reminder 15 "Pickup Jack"` |
| `omarchy pkg` | Package management | `omarchy pkg install <pkg>` |
| `omarchy setup` | Initial setup tasks | `omarchy setup fingerprint` |
| `omarchy update` | System updates | `omarchy update` |

## Configuration Locations

### Hyprland (Window Manager)

```
~/.config/hypr/
├── hyprland.conf      # Main config (sources others)
├── bindings.conf      # Keybindings
├── monitors.conf      # Display configuration
├── input.conf         # Keyboard/mouse settings
├── looknfeel.conf     # Appearance (gaps, borders, animations)
├── envs.conf          # Environment variables
├── autostart.conf     # Startup applications
├── hypridle.conf      # Idle behavior (screen off, lock, suspend)
├── hyprlock.conf      # Lock screen appearance
└── hyprsunset.conf    # Night light / blue light filter
```

**Key behaviors:**
- Hyprland auto-reloads on config save (no restart needed for most changes)
- Use `hyprctl reload` to force reload
- After ANY Hyprland config change, validate with `hyprctl reload` followed by `hyprctl configerrors`
- If `hyprctl configerrors` reports errors, address them and rerun validation until clean or until a real blocker is identified
- Use `omarchy refresh hyprland` to reset to defaults

### Waybar (Status Bar)

```
~/.config/waybar/
├── config.jsonc       # Bar layout and modules (JSONC format)
└── style.css          # Styling
```

**Waybar does NOT auto-reload.** You MUST run `omarchy restart waybar` after any config changes.

**Commands:** `omarchy restart waybar`, `omarchy refresh waybar`, `omarchy toggle waybar`

### Terminals

```
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

**Command:** `omarchy restart terminal`

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `~/.config/fastfetch/config.jsonc` |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |
| walker | `~/.config/walker/config.toml` |

## Safe Customization Patterns

### Pattern 1: Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read current config
cat ~/.config/hypr/bindings.conf

# 2. Backup before changes
cp ~/.config/hypr/bindings.conf ~/.config/hypr/bindings.conf.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply changes
# - Hyprland: auto-reloads on save, but MUST validate with `hyprctl reload` and `hyprctl configerrors`
# - Waybar: MUST restart with `omarchy restart waybar`
# - Walker: MUST restart with `omarchy restart walker`
# - Terminals: MUST restart with `omarchy restart terminal`
```

### Pattern 2: Make a new theme

Yaqyn is the only bundled qvOS theme. Create a custom theme by copying it:

```bash
mkdir -p ~/.config/omarchy/themes/my-theme
cp -a ~/.config/omarchy/themes/yaqyn/. ~/.config/omarchy/themes/my-theme/
omarchy theme set my-theme
```

You can instead install a compatible theme repository with
`omarchy theme install <git-url>`, or link a compatible theme directory as a
lowercase slug under `~/.config/omarchy/themes/`. qvOS preserves custom theme
directories and external links during updates.

### Pattern 3: Use Hooks for Automation

Create scripts in `~/.config/qvos/hooks/` to run automatically on events:

```bash
# Available hooks (see samples in ~/.config/qvos/hooks/):
~/.config/qvos/hooks/
├── theme-set        # Runs after theme change (receives theme name as $1)
├── font-set         # Runs after font change
└── post-update      # Runs after `qv update`
```

Example hook (`~/.config/qvos/hooks/theme-set`):
```bash
#!/bin/bash
THEME_NAME=$1
echo "Theme changed to: $THEME_NAME"
# Add custom actions here
```

### Pattern 4: Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong:

```bash
# Reset specific config (creates backup automatically)
omarchy refresh waybar
omarchy refresh hyprland

# The refresh command:
# 1. Backs up current config with timestamp
# 2. Copies the default from ~/.local/share/qvos/qvcore/config/files/
# 3. Restarts the component
```

## Common Tasks

### Themes

```bash
omarchy theme list              # Show available themes
omarchy theme current           # Show current theme
omarchy theme set <name>        # Apply Yaqyn or an installed compatible user theme
omarchy theme bg next           # Cycle wallpaper
omarchy theme install <url>     # Install from git repo
```

### Keybindings

Edit `~/.config/hypr/bindings.conf`. Format:
```
bind = SUPER, Return, exec, xdg-terminal-exec
bind = SUPER, Q, killactive
bind = SUPER SHIFT, E, exit
```

View current bindings: `omarchy menu keybindings --print`

**IMPORTANT: When re-binding an existing key:**

1. First check existing bindings: `omarchy menu keybindings --print`
2. If the key is already bound, you MUST add an `unbind` directive BEFORE your new `bind`
3. Inform the user what the key was previously bound to

Example - rebinding SUPER+F (which is bound to fullscreen by default):
```
# Unbind existing SUPER+F (was: fullscreen)
unbind = SUPER, F
# New binding for file manager
bind = SUPER, F, exec, nautilus
```

Always tell the user: "Note: SUPER+F was previously bound to fullscreen. I've added an unbind directive to override it."

### Display/Monitors

Edit `~/.config/hypr/monitors.conf`. Format:
```
monitor = eDP-1, 1920x1080@60, 0x0, 1
monitor = HDMI-A-1, 2560x1440@144, 1920x0, 1
```

List monitors: `hyprctl monitors`

### Window Rules

**CRITICAL: Hyprland window rules syntax changes frequently between versions.**

Before writing ANY window rules, you MUST fetch the current documentation from the official Hyprland wiki:
- https://github.com/hyprwm/hyprland-wiki/blob/main/content/Configuring/Window-Rules.md

DO NOT rely on cached or memorized window rule syntax. The format has changed multiple times and using outdated syntax will cause errors or unexpected behavior.

Window rules go in `~/.config/hypr/hyprland.conf` or a sourced file. Always verify the current syntax from the wiki first.

### Fonts

```bash
omarchy font list               # Available fonts
omarchy font current            # Current font
omarchy font set <name>         # Change font
```

### System

```bash
omarchy update                  # Full system update
omarchy version                 # Show qvOS version
omarchy debug --no-sudo --print # Debug info (ALWAYS use these flags)
omarchy system lock             # Lock screen
omarchy system shutdown         # Shutdown
omarchy system reboot           # Reboot
```

**IMPORTANT:** Always run `omarchy debug` with `--no-sudo --print` flags to avoid interactive sudo prompts that will hang the terminal.

## Troubleshooting

```bash
# Get debug information (ALWAYS use these flags to avoid interactive prompts)
omarchy debug --no-sudo --print

# Reset specific config to defaults
omarchy refresh <app>

# Refresh specific config file
# config-file path is relative to ~/.config/
# eg. `omarchy refresh config hypr/hyprlock.conf` will refresh ~/.config/hypr/hyprlock.conf
omarchy refresh config <config-file>

# Full reinstall of configs (nuclear option)
omarchy reinstall
```

## Decision Framework

When user requests system changes:

1. **Is it a stock omarchy command?** Use it directly
2. **Is it a config edit?** Edit in `~/.config/`, never `~/.local/share/qvos/`
3. **Is it a theme customization?** Create a NEW custom theme directory
4. **Is it automation?** Use hooks in `~/.config/qvos/hooks/`
5. **Is it a package install?** Use `omarchy pkg add <pkgs...>` (or `omarchy pkg aur add <pkgs...>` for AUR-only packages)
6. **Unsure if command exists?** Run `omarchy commands` (or `omarchy <group> --help` for one group)

### Reminder Requests

When the user asks to set a reminder, use `qv reminder <minutes> [message]` directly. Convert natural language durations to minutes and title-case short reminder labels when appropriate.

```bash
qv reminder 15 "Pickup Jack"
qv reminder 60 "Check laundry"
qv reminder show
qv reminder clear
```

## Out of Scope

This skill intentionally does not cover qvOS source development. Do not use this skill for:
- Editing files in `~/.local/share/qvos/` (`bin/`, `default/`, `qvcore/`, etc.)
- Creating or editing migrations
- Running `omarchy dev ...` commands

## Example Requests

- "Install this compatible theme" -> `omarchy theme install <git-url>`, then apply its installed slug
- "Add a keybinding for Super+E to open file manager" -> Check existing bindings first, add `unbind` if needed, then add `bind` in `~/.config/hypr/bindings.conf`
- "Configure my external monitor" -> Edit `~/.config/hypr/monitors.conf`
- "Make the window gaps smaller" -> Edit `~/.config/hypr/looknfeel.conf`
- "Set up night light to turn on at sunset" -> `omarchy toggle nightlight` or edit `~/.config/hypr/hyprsunset.conf`
- "Set a reminder to pickup jack in 15 minutes" -> `qv reminder 15 "Pickup Jack"`
- "Show my reminders" -> `qv reminder show`
- "Clear all reminders" -> `qv reminder clear`
- "Customize the Yaqyn theme colors" -> Copy Yaqyn to `~/.config/omarchy/themes/yaqyn-custom/`, edit the copy, then apply it
- "Run a script every time I change themes" -> Create `~/.config/qvos/hooks/theme-set`
- "Reset waybar to defaults" -> `omarchy refresh waybar`
