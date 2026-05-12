# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)
- Scripts under `install/` and `migrations/` may be sourced and intentionally omit shebangs

# Command Naming

All commands start with `omarchy-`. Prefixes indicate purpose.

The authoritative command group list lives in `bin/omarchy` in `GROUP_DESCRIPTIONS`. Keep `GROUP_DESCRIPTIONS` updated when adding a new command prefix.

Common prefixes include:

- `cmd-` - check if commands exist, misc utility commands
- `capture-` - screenshots, screen recordings, and other capture tools
- `pkg-` - package management helpers
- `hw-` - hardware detection (return exit codes for use in conditionals)
- `refresh-` - copy default config to user's `~/.config/`
- `restart-` - restart a component
- `launch-` - open applications
- `install-` - install optional software
- `setup-` - interactive setup wizards
- `toggle-` - toggle features on/off
- `theme-` - theme management
- `update-` - update components

Other current prefixes include:

- `ac-`, `audio-`, `battery-`, `branch-`, `brightness-`, `channel-`, `config-`, `debug-`, `dev-`, `drive-`, `first-`, `font-`, `haptic-`, `hibernation-`, `hook-`, `hyprland-`, `menu-`, `migrate-`, `notification-`, `npx-`, `plymouth-`, `powerprofiles-`, `reinstall-`, `remove-`, `screensaver-`, `show-`, `snapshot-`, `state-`, `sudo-`, `swayosd-`, `system-`, `transcode-`, `tui-`, `tz-`, `upload-`, `version-`, `voxtype-`, `webapp-`, `wifi-`, `windows-`

# Command Metadata

Commands in `bin/` can declare CLI metadata in comments near the top of the file. `bin/omarchy` scans the first 80 lines, and tests expect command metadata to remain valid.

Supported metadata keys:

- `# omarchy:summary=...` - short help text
- `# omarchy:group=...` - command group when it differs from the filename-derived prefix
- `# omarchy:name=...` - command name within the group
- `# omarchy:args=...` - usage arguments
- `# omarchy:examples=...` - examples separated with ` | `
- `# omarchy:alias=...` / `# omarchy:aliases=...` - alternate routes
- `# omarchy:hidden=true` - hide from default command listings
- `# omarchy:requires-sudo=true` - mark commands that require sudo

Prefer explicit metadata for user-facing commands. Keep routes consistent with the filename unless there is a deliberate alias or compatibility route.

Example:

```bash
# omarchy:summary=Take a screenshot
# omarchy:group=capture
# omarchy:args=[smart|region|windows|fullscreen] [slurp|copy]
# omarchy:examples=omarchy screenshot | omarchy capture screenshot region
# omarchy:aliases=omarchy screenshot
```

# Install Scripts

Install entry points (`install.sh`, `boot.sh`) use `#!/bin/bash`. Many scripts under `install/` are sourced via `run_logged` and intentionally do not have shebangs.

Install stage files follow this pattern:

- `install/*/all.sh` lists scripts in execution order
- leaf scripts are sourced by `run_logged $OMARCHY_INSTALL/path/to/script.sh`
- avoid `exit` in sourced install scripts unless intentionally aborting the install
- use `$OMARCHY_INSTALL` and `$OMARCHY_PATH` instead of hard-coded Omarchy paths
- keep hardware-specific logic under `install/config/hardware/`
- prefer helper commands for package and command checks where available

Raw `command -v`, `pacman`, and `pacman-key` are acceptable in bootstrap/preflight/package-helper contexts where the helper commands may not be available yet or where direct package-manager behavior is the point of the script.

# Simplicity

Keep changes simple. Prefer plain edits to existing files, lists, and config over new mechanisms, helpers, generated layers, or abstractions.

Only add new plumbing when the simple path is clearly too brittle or repetitive, and state that reason before editing.

# Helper Commands

Use these instead of raw shell commands:

- `omarchy-cmd-missing` / `omarchy-cmd-present` - check for commands
- `omarchy-pkg-missing` / `omarchy-pkg-present` - check for packages
- `omarchy-pkg-add` - install packages (handles both pacman and AUR)
- `omarchy-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

Exceptions are allowed for bootstrap, preflight, migration, and package-helper scripts where the helper may not be available yet, where the helper itself is being implemented, or where direct package-manager behavior is required.

# Config Structure

- `config/` - default configs copied to `~/.config/`
- `default/themed/*.tpl` - templates with `{{ variable }}` placeholders for theme colors
- `themes/*/colors.toml` - theme color definitions (accent, background, foreground, color0-15)

# Visual Changes

When making visual changes, such as Waybar styles or desktop appearance, always take and analyze a screenshot after applying the change to verify the result. Use `omarchy capture screenshot fullscreen save` for fullscreen screenshots.

# Upstream Sync Conflicts

When syncing from upstream Omarchy, qvOS customizations should not silently block new upstream features.

If a merge conflict happens because upstream added or changed a feature in an area qvOS customizes, prefer integrating the upstream feature into the qvOS customization instead of dropping it. Keep the qvOS design/behavior, but preserve the new upstream capability when practical.

Only omit an upstream feature when it is clearly incompatible, broken, unsafe, or intentionally not part of qvOS. In that case, state the reason explicitly.

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
omarchy-refresh-config hypr/hyprlock.conf
```

This copies `~/.local/share/omarchy/config/hypr/hyprlock.conf` to `~/.config/hypr/hyprlock.conf`.

# Migrations

To create a new migration, run `omarchy-dev-add-migration --no-edit`. This creates a migration file named after the unix timestamp of the last commit.

New migration format:
- File permissions must be `0644` (`-rw-r--r--`); migrations are sourced, not executed directly
- No shebang line
- Start with an `echo` describing what the migration does
- Use `$OMARCHY_PATH` to reference the omarchy directory
- Prefer helper commands such as `omarchy-cmd-present`, `omarchy-cmd-missing`, `omarchy-pkg-present`, and `omarchy-pkg-missing`

Some older migrations predate these rules. Do not copy older migrations that start with shebangs, omit the leading `echo`, or hard-code `~/.local/share/omarchy`.

Migrations may use raw `pacman`, `command -v`, or direct config edits when needed for historical compatibility or one-off repair work.

Example:
```bash
echo "Disable fingerprint in hyprlock if fingerprint auth is not configured"

if omarchy-cmd-missing fprintd-list || ! fprintd-list "$USER" 2>/dev/null | grep -q "finger"; then
  sed -i 's/fingerprint:enabled = .*/fingerprint:enabled = false/' ~/.config/hypr/hyprlock.conf
fi
```

# Clean Commit And qvsync Workflow

When the user asks to commit current work and run `qvsync`, use this clean
workflow:

- Treat `qvsync` as the git alias `git qvsync`; inspect `.git/qvsync` before
  first use in a session if its behavior is relevant.
- Confirm the branch is `OS` and inspect `git status --short --branch` before
  staging.
- Verify the repo identity is exactly
  `Abdulrahman M. Yaqin <Hi@Yaqin.dev>` before committing.
- Run the narrow checks for the touched files before staging. For mixed
  shell/config/Go changes, prefer:
  - `bash -n` on changed shell scripts
  - `shellcheck` on changed shell scripts
  - `gofmt` on changed Go files
  - `go test -count=1 ./...`
  - `go build -trimpath -o /tmp/qvos-tui-test .` for Go command packages so no
    build binary lands in the repo
  - `bash test/omarchy-cli-test.sh` when command metadata or `bin/` routes are
    touched
  - `hyprctl reload && hyprctl configerrors` for Hyprland config changes
  - `git diff --check`
- Apply user-facing desktop changes to the running system before runtime checks:
  - For changed files under `config/`, back up the live target first, then copy
    the exact repo file to the matching `~/.config/...` path. Example:
    `cp ~/.config/hypr/qv/bindings.conf ~/.config/hypr/qv/bindings.conf.bak.$(date +%s)`
    then
    `install -m 0644 config/hypr/qv/bindings.conf ~/.config/hypr/qv/bindings.conf`.
  - For qvOS helper scripts under `qv/scripts/` or `qv/tui/`, apply the repo
    payload with the install script pattern:
    `OMARCHY_PATH=$PWD bash -c 'source install/config/qvos-scripts.sh'`.
  - After applying, run the relevant live reload/check command, such as
    `hyprctl reload && hyprctl configerrors`, `omarchy restart waybar`, or a
    direct launcher/script smoke test.
- Stage with `git add -A`, then run `git diff --cached --check` and inspect
  `git diff --cached --stat` before committing.
- Remove generated artifacts such as `__pycache__/`, `*.pyc`, and local Go
  build binaries from the index and worktree before commit. Add a narrow
  `.gitignore` entry only when the artifact is a repeatable local build output.
- Commit all staged changes with a clear human commit message and no agent
  attribution.
- Run `git qvsync` only after the commit leaves the worktree clean.
- Report the commit SHA, qvsync result, checks that ran, checks skipped, and the
  final `git status --short --branch` state.
