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
---

<!-- qvOS ADDITIONS START -->

# qvOS Additions

The opening policy block is the verbatim upstream Omarchy `AGENTS.md` from
<https://github.com/basecamp/omarchy/blob/master/AGENTS.md>. Never edit that
block for qvOS-only work. During `qvsync`, update it only from upstream and keep
all qvOS policy below this separator.

## Pre-Public Phase

- This PC is the only qvOS installation. Until another installation or public
  release exists, migrate and verify it directly instead of preserving
  compatibility or migrations for unreleased qvOS states.
- This exception never covers user data, security, upstream compatibility,
  clean-install correctness, or future public architecture. Retire it when
  qvOS reaches another machine or public users.
- After publishing qvOS changes, directly align and verify this live
  installation. Do not run the interactive updater or package upgrades unless
  the task requires them.

## qvCORE

`Install > qvCORE` is the opt-in profile for qvOS-integrated daily software.

- Keep new integrations out of base install/package lists unless explicitly
  promoted to the base system.
- Reuse an existing `omarchy-install-*` or `omarchy-setup-*` owner. Add
  `qv/core/<component>.sh` only when qvOS must own the integration.
- Persistent integration or state belongs to one independently rerunnable owner
  covering installation, `--status`, `--repair`, `--adopt`, `--disable`, and
  post-update repair. Menus and desktop adapters must only delegate to it.
- Catalog changes require an explicit curation decision plus matching installer
  route, health inventory, and integration tests.

## Organization And Integration

Every qvOS change must leave one traceable lifecycle. Prefer plain edits to
existing files and add plumbing only when the simple path is brittle or
repetitive.

- Keep tracked Omarchy source byte-for-byte upstream by default. qvOS behavior,
  configuration, assets, and policy belong under `qv/<domain>/`, with upstream
  behavior applied first and the qvOS layer applied afterward.
- Before editing an inherited file, prove that an Omarchy hook, config include,
  qvOS installer or migration, or qvOS-owned public command cannot complete the
  task. When no extension seam exists, keep the inherited change to the
  smallest stable include or delegation line; never place qvOS implementation
  or data there.
- Treat an inherited file containing substantial qvOS logic as refactoring
  debt. When touching it, compare it with `upstream/master`, move the qvOS
  portion to its `qv/<domain>/` owner, and add a focused guard against renewed
  upstream drift.
- Keep qvOS config sources separate even when their installed runtime target is
  an Omarchy-managed path. Apply or reconcile them after the upstream install,
  refresh, migration, or update step instead of replacing the tracked upstream
  default.
- Give each feature one owner, normally under `qv/<feature>/`; reuse upstream
  owners and avoid dumping grounds such as `scripts/`, `utils/`, or `misc/`.
  Move source, installed payloads, references, guards, and tests together.
- Keep all qvOS test files, including new ones, under `test/qvos/`.
- In larger files, use short section headings and brief comments for ownership,
  intent, or non-obvious constraints. Do not narrate obvious code.
- Link qvCORE, menus, Thunar actions, keybindings, and desktop helpers only when
  the link completes a clear user task. Use thin adapters that safely pass
  context to the owner; keep the base usable when an optional dependency is
  absent, and omit surfaces with no user value.
- Keep qvOS actions in their normal product menus and mirror them in
  `show_qvos_menu` for user-friendly direct access and testing; both surfaces
  delegate to the same owner.
- Trace linked work from owner through public command and adapters to installed
  config/payload, state or repair hook, permissions/services/network exposure,
  and focused tests. Verify fresh-install, migration/update, and live paths.
- Treat qvOS as an overlay on Omarchy: prefer qvOS-owned seams, minimize
  inherited edits, and never reorganize upstream code only for qvOS style.
  During conflicts, preserve new upstream capability when practical; omit it
  only when incompatible, broken, unsafe, or intentionally out of scope, and
  state why.
- Shared install/refresh paths must preserve optional integrations or restore
  them through the enabled component's idempotent repair in the same update.
  Verify both tracked source and installed runtime.
- Keep `~/.local/share/omarchy` a clean Git checkout. Deploy runtime content
  through installers/migrations to owned runtime, config, or system paths;
  untracked collisions there can block `omarchy update`.

## ISO Builder

`qv/tui/bin/qvos-build` owns qvOS image construction.

- Use official `omacom-io/omarchy-iso` `main` as the default upstream builder
  and stage it fresh for normal builds. `git qvsync` updates the Omarchy source
  tree; it does not sync this separate repository.
- Stage the selected qvOS Git ref separately and apply
  `qv/iso/omarchy-iso-qvos-tui.patch` only to the temporary builder. Keep ISO
  integration under `qv/iso/` and never persist qvOS edits in upstream source.
- If an upstream builder change breaks the patch or a relied-on contract, stop
  and update the qvOS owner and tests; do not weaken the guard or patch cached
  upstream output directly.
- During pre-public development, run full image builds and embedded audits on
  request or for release candidates. For ISO changes, run fast staging and
  contract checks immediately and report any deferred full build.
- For release verification, pin `QVOS_SOURCE_REF` to the intended qvOS commit,
  build the intended `QVOS_OMARCHY_ISO_REF`, verify the image and embedded
  source, and keep optional qvCORE applications out unless explicitly promoted.

## Keybindings

`qv/config/files/hypr/qv/bindings.conf` is authoritative for qvOS-owned
bindings.

- Inspect it and `omarchy menu keybindings --print` before edits. If a key is
  occupied, report its action and owner and wait before replacing it; use
  `unbind` for an override.
- Letter keys use Family One (`SUPER` plus optional Shift/Ctrl) and Family Two
  (add Alt with the same variants). Inventories show qvOS-owned entries by
  family, a checkmark column, `—` for free slots, non-letter families, and a
  concise script index; mention inherited bindings only for conflicts or when
  requested.
- After edits, check duplicates and executable targets, apply and compare the
  live file, reload Hyprland, require no config errors, and show the updated
  qvOS-only inventory.

## Commit And qvsync

When the user asks to commit and run `qvsync`:

- Treat it as `git qvsync`; inspect `.git/qvsync` when relevant, require branch
  `OS`, and inspect `git status --short --branch`.
- Before `git qvsync`, fetch `upstream/master` without merging. From
  `git merge-base HEAD upstream/master`, inspect every upstream-changed path and
  search qvOS owners, inherited seams, installed payloads, migrations, and tests
  for dependencies on the changed path or behavior.
- Treat an upstream change as qvOS-impacting when it alters a command contract,
  extension seam, config schema or include, path, package or service, install,
  refresh, migration, repair, or update flow, permission, network exposure, or
  security default that qvOS uses or overrides. Also flag new ownership overlap,
  duplicated implementation, or an upstream replacement for a qvOS enhancement.
- A clean merge is not compatibility proof. For every impact, preserve the new
  upstream behavior when safe, update the affected `qv/<domain>/` owner and its
  adapters, guards, and tests in the same sync, then verify the relevant fresh
  install, update, repair, and live paths.
- When adaptation is required, do not let `git qvsync` publish the raw upstream
  merge. Create a backup branch, integrate upstream locally without pushing,
  finish and verify the qvOS adaptation, commit it, then run `git qvsync` from
  the clean tree. If compatibility or safety cannot be proven, stop before any
  push and report the upstream paths, affected qvOS owners, and unresolved risk.
- Before every qvsync, refresh `qv/core/steam.sh` and its test against Linutil's
  current Arch list at `core/tabs/system-setup/gaming-setup.sh`. Use current
  package names and leave GPU drivers to Omarchy hardware detection.
- Set the repository identity to
  `Abdulrahman M. Yaqyn <253025238+yaqyn@users.noreply.github.com>`.
- Match checks to the diff: `bash -n` and `shellcheck` for shell (`-s bash` for
  sourced install/migrations); `gofmt`, `go test -count=1 ./...`, and a
  `/tmp` Go build for Go; `test/qvos/run.sh` for the full shell suite; binding
  checks for qvOS bindings; Hyprland reload/errors for its config; and
  `git diff --check`.
- Before runtime checks, back up and apply changed user config, then install qvOS
  desktop payloads with
  `OMARCHY_PATH=$PWD bash -c 'source qv/install/desktop'`.
  Repair affected enabled qvCORE adapters, require no unexpected
  `omarchy qvcore status` drift, confirm the live checkout is clean, and run the
  relevant reload or smoke test.
- Stage with `git add -A`; inspect `git diff --cached --check` and
  `git diff --cached --stat`; remove generated artifacts; then commit the
  verified logical unit without agent attribution.
- Run `git qvsync` only from a clean post-commit worktree. Afterward, require the
  upstream block above the qvOS separator to match `upstream/master:AGENTS.md`
  byte-for-byte. Report the commit SHA, qvsync result, checks run/skipped, and
  final branch status.
