# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/My App.desktop"`, not `$APP_DIR/My\ App.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)
- Scripts under `qvcore/install/`, `qvcore/boot/login/`, and numeric owners
  under `qvcore/migrations/` may be sourced and intentionally omit shebangs

# Command Architecture

`qv` is the product CLI and `qvcore/cli/qv` is its command engine. `omarchy` is
only a compatibility frontend. During the command-tree transition, a promoted
command has one `qvcore/` owner, one metadata-bearing `bin/qv-*` adapter, and a
metadata-free matching `bin/omarchy-*` compatibility adapter. The engine prefers
the native route. Unpromoted inherited `bin/omarchy-*` files remain intact until
their complete domain moves. Never add mutation logic, state ownership, or
product branding to `bin/`.

Native CLI benchmarking and metadata documentation live under `qvcore/cli/`.
They inspect only static `qv` surfaces and describe only the current `qv:*`
schema; inherited dev-tool names are external compatibility adapters.

The authoritative command group list lives in `qvcore/cli/qv` in
`GROUP_DESCRIPTIONS`. Keep it updated when adding a command prefix. User-facing
help, examples, errors, and suggestions use `qv`, even while an inherited
binary name remains as compatibility ABI.

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

The CLI reads `# qv:*` metadata from promoted native adapters and temporary
`# omarchy:*` metadata from unpromoted inherited routes. Never keep both records
for the same command. Metadata is scanned only from the first 80 lines, and qvOS
help never exposes Omarchy product identity.

Supported metadata keys:

- `# qv:summary=...` - short help text
- `# qv:group=...` - command group when it differs from the filename-derived prefix
- `# qv:name=...` - command name within the group
- `# qv:args=...` - usage arguments
- `# qv:examples=...` - examples separated with ` | `
- `# qv:alias=...` / `# qv:aliases=...` - alternate routes
- `# qv:hidden=true` - hide from default command listings
- `# qv:requires-sudo=true` - mark commands that require sudo

The inherited schema supports the same keys with the `omarchy:` prefix only
until that route is promoted.

Prefer explicit metadata for user-facing commands. Keep routes consistent with the filename unless there is a deliberate alias or compatibility route.

Example:

```bash
# qv:summary=Take a screenshot
# qv:group=capture
# qv:args=[smart|region|windows|fullscreen] [slurp|copy]
# qv:examples=qv screenshot | qv capture screenshot region
# qv:aliases=qv screenshot
```

# Install Scripts

Install entry points (`install.sh`, `boot.sh`) use `#!/bin/bash`. The complete
installer lives under `qvcore/install/`, with login leaves under
`qvcore/boot/login/`. The inherited top-level `install/` tree is retired and
must remain absent.

Install stage files follow this pattern:

- `qvcore/install/{preflight,packaging,config,post-install}/` owns ordered stages
- leaf scripts are sourced by `run_logged` from `$QVOS_INSTALL`
- avoid `exit` in sourced install scripts unless intentionally aborting the install
- use `$QVOS_INSTALL` and `$QVOS_PATH`; `OMARCHY_INSTALL` and `OMARCHY_PATH`
  exist only where an inherited ABI requires them
- use qvOS-owned installer state and environment (`QVOS_INSTALL_LOG_FILE`,
  `QVOS_ONLINE_INSTALL`, `/var/log/qvos-install.log`); preserve
  `OMARCHY_CHROOT_INSTALL` only as the reviewed ISO-builder input
- keep hardware-specific install logic under `qvcore/install/config/hardware/`
- prefer helper commands for package and command checks where available

Raw `command -v`, `pacman`, and `pacman-key` are acceptable in bootstrap/preflight/package-helper contexts where the helper commands may not be available yet or where direct package-manager behavior is the point of the script.

# Helper Commands

Use native helpers when their domain is promoted. Unpromoted inherited code may
keep its exact compatibility ABI until that complete domain moves:

- `qv-cmd-missing` / `qv-cmd-present` - check for commands
- `qv-pkg-missing` / `qv-pkg-present` - check for packages
- `qv-pkg-add` - install from qvOS configured repositories
- `qv-pkg-aur-add` - explicitly install a user-selected AUR package
- `qv-restart-*` - restart supported desktop processes, services, and devices
- `qv-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

Exceptions are allowed for bootstrap, preflight, migration, and package-helper scripts where the helper may not be available yet, where the helper itself is being implemented, or where direct package-manager behavior is required.

# Config Structure

- `config/` and `default/` remain reviewed sources only for domains not yet
  promoted
- `qvcore/config/files/` owns specialized native installed sources; Hypridle
  lives only there and its former top-level duplicate remains retired
- `config/fastfetch/config.jsonc` is the singular Fastfetch source and reads
  private terminal art from `~/.config/qvos/branding`; never restore a
  `qvcore/config/files/fastfetch` overlay or active Omarchy branding state
- `qvcore/branding/` owns the qvOS vector masters, the user-approved terminal
  art, its private install/migration lifecycle, and branding commands; the
  graphical wordmark and terminal composition are intentionally distinct
- `qvcore/config/toggles/` owns toggle templates; active toggle state lives
  privately under `~/.local/state/qvos/toggles`
- `qvcore/hooks/` owns custom automation under `~/.config/qvos/hooks`; qvOS
  system jobs execute from their tracked feature owners, never user copies
- `qvcore/desktop/session/` owns native lock, logout, and wake behavior;
  qvOS config and menus call its `qv-system-*` routes, while exact
  `omarchy-system-*` names remain external compatibility adapters only
- `qvcore/desktop/hyprland/` owns validated monitor scaling and event recovery,
  focused-window mutations, and workspace-layout changes; qvOS bindings and
  menus call `qv-hyprland-*`, while the inherited autostart source alone keeps
  the exact monitor-watch compatibility seam until that source is promoted
- qvOS-managed user units use `qvos-*` names and native `qvcore/` entrypoints;
  inherited unit names are migration input only
- desktop application, browser, web-app, and terminal launching belongs to
  `qvcore/desktop/launch`; callers pass exact arguments and never shell strings
- custom Web App desktop entries belong to `qvcore/desktop/webapp`;
  installation and removal preserve foreign files, while fresh qvOS contains
  no preinstalled Web Apps, fixed service URLs, or service protocol handlers
- update and restart markers live privately under
  `~/.local/state/qvos/update`; arbitrary persistent state is not a CLI feature
- local debug inventory belongs to `qvcore/security/debug`; it remains private,
  bounded, terminal-safe, and upload-free, with sudo limited to optional dmesg
- `qvcore/theme/yaqyn/` is the only bundled theme; `themes/` is retired
- `default/themed/*.tpl` remains the compatible custom-theme template format

# Visual Changes

When making visual changes, such as Waybar styles or desktop appearance, take
and analyze a screenshot after applying the change. Use
`qv capture screenshot fullscreen save` for fullscreen screenshots.

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
qv refresh config hypr/hyprlock.conf
```

This copies the selected source from
`~/.local/share/qvos/config/hypr/hyprlock.conf` to
`~/.config/hypr/hyprlock.conf` with a backup.

# Migrations

`qvcore/migrations/` is the only migration source. The inherited top-level
`migrations/` tree is retired and must remain absent; its historical outcomes
belong in fresh-install owners, never in a replayable qvOS update path.
`qvcore/migrations/run` serializes execution, fails closed, and records private
atomic markers under `~/.local/state/qvos/migrations`. Fresh installation marks
current migrations without executing them through its exact native owner.

Create migrations with `qv dev add migration`. Numeric migration files are
`0644`, have no shebang, start with a concise `echo`, use `$QVOS_PATH`, and are
idempotent so an interrupted unmarked run can safely retry. Prefer existing
command and package helpers, but direct package-manager or config work is
allowed when it is the migration's reviewed purpose. Never add a skip path or
restore Omarchy migration state as an active dependency.
# Repository Contract

This entire file is qvOS-owned and must describe the current repository, not a
copied upstream layout. Update root and owner-local instructions in the same
change whenever paths, ownership, compatibility, verification, or lifecycle
behavior changes. qvsync reviews upstream policy as capability input but never
overwrites this contract.

## Core Contract

Every qvOS change must leave one traceable lifecycle.

- This PC is the only qvOS installation until another installation or public
  release exists. Migrate unreleased qvOS states directly, but never relax user
  data, security, upstream compatibility, clean-install, or future-public
  architecture requirements.
- After each verified local commit, align and verify this live installation
  from the development repository. Do not run the interactive updater or
  package upgrades unless the task requires them.
- Treat qvOS as an independent downstream distribution and Omarchy as a
  read-only code upstream, never product authority. qvOS owns product and
  package selection; Omarchy provides only the credited Stable mirror,
  repository, and signing keyring boundary described in `qvcore/packages/`.
- During the native transition, keep each inherited implementation byte-for-byte
  until its domain is promoted. Then port selected capability into one owner
  under `qvcore/<domain>/` or `qvcore/<feature>/` and remove the inherited
  implementation, overlay, adapter, fallback, and stale state together. qvOS
  tests live under `test/` and mirror their owner boundary.
- The complete installer is native under `qvcore/install/` and
  `qvcore/boot/login/`; the top-level `install/` tree is retired. Keep remaining
  config sources separate until their domain is promoted and reconcile them
  after native install, refresh, migration, or update paths. Installed source
  is `~/.local/share/qvos`; retain only its exact `omarchy -> qvos` compatibility
  link, and keep runtime payloads under `~/.local/lib/qvos`.
- New persistent state is feature-owned and private under
  `~/.local/state/qvos`. User-editable qvOS configuration is feature-owned
  under `~/.config/qvos`; legacy branding is preserved privately and retired
  through its native owner. The generic state compatibility route accepts only
  reviewed reboot and service-restart markers; it never recreates an active
  Omarchy state root.
- Use thin, absent-safe adapters only as transition seams that complete a user
  task. qvCORE is mandatory; qvOS must remain complete and healthy with no
  optional Service or Development integration installed.
- Trace each feature through its command and adapters to installed config,
  state, hooks, permissions, services, network exposure, and focused tests.
  Verify fresh install, update, removal, and live behavior where applicable.
- Preserve useful upstream capability through explicit review and native ports.
  Omit it when unsafe, incompatible, unwanted, or out of scope, and state why.

## Zero Duplication

Reusable code has one shared owner. A second consumer must call or extract it
in the same change; thin adapters translate only. Fix shared bugs once, test
the owner and two consumers, and leave no equivalent implementation behind.

## Main qvsync Workflow

`qvsync` is the read-only upstream intake loop. It never merges, cherry-picks,
moves product branches, or publishes refs.

1. Start with `git qvsync --audit`. Read every upstream commit and diff, then
   search qvOS owners, installed payloads, tests, and history for the same
   capability; filename overlap alone is not an audit.
2. Flag changed commands, seams, schemas, paths, packages, services, lifecycle
   flows, permissions, network exposure, security defaults, duplicate
   ownership, and upstream replacements for qvOS enhancements.
3. Record each commit's capability, qvOS owner or history, decision (`adopt`,
   `combine`, `retire-qvos`, `preserve`, or `no-impact`), cleanup, and
   verification. Explain every `preserve` and `no-impact`.
4. Port selected capability into one native qvOS owner. Remove superseded
   source, payloads, hooks, state, migrations, adapters, and tests, then prove
   replacement and residue removal.
5. Treat maintainer roadmaps as advisory signals only; never merge or depend on
   unshipped work.
6. Never merge or cherry-pick an upstream commit into qvOS. Port reviewed code
   deliberately, update owners and guards, and verify affected fresh install,
   update, removal, live, and cleanup paths.
7. Record every commit in `upstream/qvsync/upstream-reviews/<target-sha>.psv`, then use
   `--record-reviewed-upstream <full-sha>` only for that exact fetched target.
   Commit the ledger, baseline, and verified adaptation together.
8. Review upstream instruction changes for useful engineering guidance, but
   keep this qvOS-owned contract current and independent. qvsync never
   publishes; use normal Git publication only when explicitly requested and
   report the ledger, checks, baseline, and status.

Command mechanics and publication checks live in `upstream/qvsync/AGENTS.md`; they
supplement this workflow and never replace its judgment.

## Workflow Routing

Root-started sessions must read every matching route completely before editing:

- qvOS identity, version, application defaults, fonts, hooks, reminders, weather, CLI, desktop runtime and controls, theme, and browser lifecycle: `qvcore/branding/AGENTS.md`, `qvcore/version/AGENTS.md`, `qvcore/defaults/AGENTS.md`, `qvcore/font/AGENTS.md`, `qvcore/hooks/AGENTS.md`, `qvcore/reminder/AGENTS.md`, `qvcore/weather/AGENTS.md`, `qvcore/cli/AGENTS.md`, `qvcore/desktop/AGENTS.md`, `qvcore/controls/AGENTS.md`, `qvcore/theme/AGENTS.md`, `qvcore/browser/AGENTS.md`
- qvOS boot presentation and Limine lifecycle: `qvcore/boot/AGENTS.md`
- qvCORE architecture and lifecycle boundaries: `qvcore/README.md`
- Services and Development ownership: `services/AGENTS.md`, `development/AGENTS.md`
- Gaming, install, migration, package, and update ownership: `qvcore/gaming/AGENTS.md`, `qvcore/install/AGENTS.md`, `qvcore/migrations/AGENTS.md`, `qvcore/packages/AGENTS.md`, `qvcore/update/AGENTS.md`
- Read-only hardware detection shared by install, config, gaming, and software: `qvcore/hardware/AGENTS.md`
- Menu, search, Walker, Elephant, presentation, sharing, and optional software: `qvcore/menu/AGENTS.md`, `qvcore/presentation/AGENTS.md`, `qvcore/share/AGENTS.md`, `qvcore/software/AGENTS.md`
- DNS, WARP, and privileged resolver policy: `qvcore/network/AGENTS.md`
- Picture, video, and terminal-art conversion: `qvcore/transcode/AGENTS.md`
- Screenshots, OCR, screen recording, and recording state: `qvcore/capture/AGENTS.md`
- Waybar overlay, runtime modules, refresh, and task actions: `qvcore/waybar/AGENTS.md`
- qvOS terminal interface and action flows: `qvcore/tui/AGENTS.md`
- Tmux session and configuration lifecycle: `qvcore/tmux/AGENTS.md`
- ISO construction and release images: `release/iso/AGENTS.md`
- qvOS configuration and Thunar reconciliation: `qvcore/config/AGENTS.md`, `qvcore/thunar/AGENTS.md`
- qvOS power, root-owned AC events, battery protection, and charging thresholds: `qvcore/power/AGENTS.md`
- Windows VM configuration, data scope, and rollback: `qvcore/windows/AGENTS.md`
- Security hardening and screensaver lifecycle: `qvcore/security/AGENTS.md`, `qvcore/screensaver/AGENTS.md`
- Drive discovery, selection, and LUKS key lifecycle: `qvcore/storage/AGENTS.md`
- Commit and qvsync command mechanics: `upstream/qvsync/AGENTS.md`
- Native migration execution and state cleanup: `qvcore/migrations/AGENTS.md`
- Retained Omarchy command and state compatibility: `compat/omarchy/AGENTS.md`

## Future Workflow Instructions

- Codex must automatically create or update the nearest owner-local `AGENTS.md`
  for a recurring conditional or multi-stage workflow, safety invariant, or UX
  contract, and add its root route in the same change so future work inherits
  the reusable learning without bloating this file.
- Do not document simple or one-off work or duplicate an existing workflow.
  Keep the permanent operating model, downstream and ownership boundaries, main
  qvsync workflow, and repository-wide invariants here. Never move them out
  merely to reduce root size.
- Keep every workflow concise: trigger and scope, source of truth, ordered
  procedure, approval or stop conditions, verification, and live apply or
  cleanup. Update it with behavior and remove stale guidance.
- Enforce deterministic requirements in tests, hooks, or CI. The instruction
  guard must discover every nested owner-local `AGENTS.md` and require a root
  route.
