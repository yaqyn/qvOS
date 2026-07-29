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

## Core Contract

Every qvOS change must leave one traceable lifecycle.

- This PC is the only qvOS installation until another installation or public
  release exists. Migrate unreleased qvOS states directly, but never relax user
  data, security, upstream compatibility, clean-install, or future-public
  architecture requirements.
- After each verified local commit, align and verify this live installation
  from the development repository. Do not run the interactive updater or
  package upgrades unless the task requires them.
- Treat qvOS as an overlay on Omarchy. Keep inherited source byte-for-byte
  upstream by default; give each feature one owner under `qv/<domain>/` or
  `qv/<feature>/`, and keep its source, payloads, references, guards, and tests
  together. All qvOS tests live under `test/qvos/`.
- Before editing inherited source, prove no hook, include, installer, migration,
  or qvOS-owned command can complete the task. Otherwise use the smallest stable
  delegation seam. When touching inherited qvOS logic, move it to its owner and
  guard against renewed drift.
- Keep qvOS config sources separate from inherited defaults and reconcile them
  after upstream install, refresh, migration, or update. Deploy runtime content
  outside `~/.local/share/omarchy`; keep that checkout clean.
- Use thin, absent-safe adapters only when they complete a user task. qvOS must
  remain complete and healthy with no qvCORE stack installed. Shared refresh
  paths preserve optional integrations without installing stacks.
- Trace each feature through its command and adapters to installed config,
  state, hooks, permissions, services, network exposure, and focused tests.
  Verify fresh install, update, removal, and live behavior where applicable.
- Preserve safe upstream capability during conflicts. Omit it only when broken,
  unsafe, incompatible, or intentionally out of scope, and state why.

## Main qvsync Workflow

`qvsync` is the main qvOS evolution loop: preserve new Omarchy capability while
keeping qvOS cleaner, integrated, and deliberately differentiated.

1. Start with `git qvsync --audit`. Read every upstream commit and diff, then
   search qvOS owners, installed payloads, tests, and history for the same
   capability; filename overlap alone is not an audit.
2. Flag changed commands, seams, schemas, paths, packages, services, lifecycle
   flows, permissions, network exposure, security defaults, duplicate
   ownership, and upstream replacements for qvOS enhancements.
3. Record each commit's capability, qvOS owner or history, decision (`adopt`,
   `combine`, `retire-qvos`, `preserve`, or `no-impact`), cleanup, and
   verification. Explain every `preserve` and `no-impact`.
4. Prefer an equal-or-better mature upstream owner. Port only qvOS
   differentiators to its supported seam, remove superseded source, payloads,
   hooks, state, migrations, adapters, and tests, then prove replacement and
   residue removal.
5. Treat maintainer roadmaps as advisory signals only; never merge or depend on
   unshipped work.
6. A clean merge is not compatibility proof. If adaptation is needed, integrate
   locally without publishing, update owners and guards, verify affected fresh
   install, update, removal, and live paths, then commit the complete adaptation.
7. Approve only the exact audit target with `--reviewed-upstream <full-sha>`;
   audit again if it advances and stop before pushing unresolved risk.
8. Run qvsync only from a clean verified post-commit tree. Require the upstream
   block here to match `upstream/master:AGENTS.md` byte-for-byte, then report the
   ledger, commit, checks, qvsync result, and final status.

Command mechanics and publication checks live in `qv/git/AGENTS.md`; they
supplement this workflow and never replace its judgment.

## Workflow Routing

Root-started Codex sessions do not discover nested instructions automatically.
Read every matching route completely before editing:

- qvOS architecture and lifecycle boundaries: `qv/README.md`
- qvCORE catalog and component lifecycle: `qv/core/AGENTS.md`
- Menu, search, Walker, and Elephant: `qv/menu/AGENTS.md`
- qvOS terminal interface and action flows: `qv/tui/AGENTS.md`
- ISO construction and release images: `qv/iso/AGENTS.md`
- qvOS Hyprland config and reconciliation: `qv/config/AGENTS.md`
- Screensaver lifecycle and cursor handling: `qv/screensaver/AGENTS.md`
- Commit and qvsync command mechanics: `qv/git/AGENTS.md`

## Future Workflow Instructions

- Codex must automatically create or update the nearest owner-local `AGENTS.md`
  for a recurring conditional or multi-stage workflow, safety invariant, or UX
  contract, and add its root route in the same change so future work inherits
  the reusable learning without bloating this file.
- Do not document simple or one-off work or duplicate an existing workflow.
  Keep the permanent operating model, overlay and ownership boundaries, main
  qvsync workflow, and repository-wide invariants here. Never move them out
  merely to reduce root size.
- Keep every workflow concise: trigger and scope, source of truth, ordered
  procedure, approval or stop conditions, verification, and live apply or
  cleanup. Update it with behavior and remove stale guidance.
- Enforce deterministic requirements in tests, hooks, or CI. The instruction
  guard must discover every nested owner-local `AGENTS.md` and require a root
  route.
