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
only a compatibility frontend over the same native catalog. The engine discovers
and dispatches only metadata-bearing `bin/qv-*` routes. Every promoted inherited
command has one `qvcore/` owner and one metadata-free matching
`bin/omarchy-*` direct compatibility adapter. A qvOS-only capability never
invents an Omarchy binary, and an Omarchy-only binary is never a qvOS command.
Never add mutation logic, state ownership, or product branding to `bin/`.

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

- `ac-`, `audio-`, `battery-`, `branch-`, `brightness-`, `channel-`, `config-`, `debug-`, `dev-`, `drive-`, `first-`, `font-`, `haptic-`, `hibernation-`, `hook-`, `hyprland-`, `menu-`, `migrate-`, `notification-`, `plymouth-`, `powerprofiles-`, `reinstall-`, `remove-`, `screensaver-`, `show-`, `snapshot-`, `state-`, `swayosd-`, `system-`, `transcode-`, `tui-`, `tz-`, `upload-`, `version-`, `voxtype-`, `webapp-`, `wifi-`, `windows-`

`qvcore/menu/menu` owns the product menu engine. Its native `qv-menu` adapter
carries metadata; `omarchy-menu` is compatibility only. Fresh bindings,
providers, and Waybar actions always call the native route.

# Command Metadata

The CLI reads only `# qv:*` metadata from native adapters. `# omarchy:*` metadata
is invalid and ignored; compatibility adapters carry no metadata. Metadata is
scanned only from the first 80 lines, and qvOS help never exposes Omarchy product
identity.

Supported metadata keys:

- `# qv:summary=...` - short help text
- `# qv:group=...` - command group when it differs from the filename-derived prefix
- `# qv:name=...` - command name within the group
- `# qv:args=...` - usage arguments
- `# qv:examples=...` - examples separated with ` | `
- `# qv:alias=...` / `# qv:aliases=...` - alternate routes
- `# qv:hidden=true` - hide from default command listings
- `# qv:requires-sudo=true` - mark commands that require sudo

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
  are retired and must never be accepted or exported by qvOS owners
- use qvOS-owned installer state and environment (`QVOS_INSTALL_LOG_FILE`,
  `QVOS_ONLINE_INSTALL`, `QVOS_PROVIDER_CHANNEL`, `QVOS_USER_NAME`,
  `QVOS_USER_EMAIL`, `QVOS_CHROOT_INSTALL`, `/var/log/qvos-install.log`); the
  native ISO handoff sets the exact chroot signal in an explicit clean
  environment with target-account XDG paths
- keep hardware-specific install logic under `qvcore/install/hardware/`; fresh
  owners install only native qvOS policy and never rescan retired pre-release
  hardware identities
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

- `qvcore/config/files/` is the singular source for installed user config;
  `config/` is retired and must remain absent. Atomic refresh recovery values
  live privately under `~/.local/state/qvos/config-backups/refresh`, never
  beside active configuration. `qvcore/config/seed-files` assigns the complete
  base inventory to a missing-only, preserving seed transaction; menu,
  user-service, XCompose, and WirePlumber files remain feature-owned and never
  enter a recursive fresh-install copy
- `qvcore/config/files/qvos/extensions/menu.sh` owns the personal menu-extension
  seed; active overrides live only under `~/.config/qvos/extensions/`, while the
  inherited Omarchy path is validated migration input and is never seeded
- `qvcore/config/base/hypr/` owns the typed Lua runtime helpers and source-side
  session, environment, appearance, persistent workspaces, and window defaults;
  session autostart finalizes only UWSM's bounded compositor-variable allowlist
  and never imports the complete process environment into systemd or D-Bus;
  `qvcore/config/files/hypr/` owns the complete user-editable Lua entrypoint
  and leaves. Active `.conf`, `default/hypr/`, and the former installed
  `hypr/qv` overlay are retired and must remain absent
- `qvcore/config/files/waybar/` owns one complete native Waybar config and
  style; its workspace buttons use the protocol-native `ext/workspaces` module
  over typed persistent Hyprland workspace rules; `default/waybar/` and the
  former merge overlay are retired
- `qvcore/config/files/` owns XCompose and WirePlumber policy;
  `default/xcompose` and `default/wireplumber/` are retired
- `qvcore/config/assistant/` owns the installed qvOS agent skill and Pi theme
  sync; inherited `default/omarchy-skill/` and `default/pi/` are retired
- `qvcore/screensaver/` owns every installed terminal screensaver profile;
  inherited terminal-specific screensaver defaults are retired
- `qvcore/shell/` owns the native Bash defaults and source-independent alias
  payload; permanent reconciliation recognizes only exact current qvOS source
  lines and never scans historical Omarchy or retired qvOS shell layouts;
  changed Bash recovery values live privately under
  `~/.local/state/qvos/shell-backups`, never beside `.bashrc`
- `qvcore/browser/` owns browser policy and the local Copy URL extension;
  inherited browser defaults are retired and no browser owner seeds a Web App
- `qvcore/menu/` owns every qvOS Elephant provider and the generated Walker
  menu theme; inherited Elephant and Walker defaults are retired, generated
  menu runtime publishes as one exact native inventory, and current install
  never scans historical menu state
- `qvcore/config/files/nvim/` owns the minimal official Neovim seed;
  fresh install and explicit config reset copy it directly, while normal
  desktop reconciliation preserves existing Neovim configuration
- `qvcore/config/files/fastfetch/config.jsonc` is the singular Fastfetch
  source and reads private terminal art from `~/.config/qvos/branding`; never
  restore a second config layer or active Omarchy branding state
- the inherited top-level `default/` source tree is fully retired and must
  remain absent; native defaults live with their qvCORE domain owners
- `qvcore/branding/` owns the qvOS vector masters, the user-approved terminal
  art, the singular system `os-release`, their safe install/migration
  lifecycles, and branding commands; the graphical wordmark and terminal
  composition are intentionally distinct
- `qvcore/version/` derives rolling identity from the exact installed Git
  commit through one checkout validator; the inherited root `version` file is
  retired and snapshots consume the same native owner
- `qvcore/config/toggles/` owns Lua toggle templates; active toggle state lives
  privately under `~/.local/state/qvos/toggles`, and the one-time reviewed
  `.conf` transition is preserved under private Hyprland state
- `qvcore/controls/notification/mako-core.ini` owns shared Mako policy;
  `qvcore/software/voxtype-config.toml` owns the optional Voxtype seed
- `qvcore/hooks/` owns custom automation under `~/.config/qvos/hooks`; qvOS
  system jobs execute from their tracked feature owners, never user copies;
  current reconciliation seeds only missing samples and never scans historical
  hook roots or convergence catalogs
- `qvcore/desktop/session/` owns native lock, logout, and wake behavior;
  qvOS config and menus call its `qv-system-*` routes, while exact
  `omarchy-system-*` names remain external compatibility adapters only
- `qvcore/boot/snapper-root.conf` owns the pre-update recovery policy installed
  by the Limine/Snapper boot owner; `default/snapper/` is retired
- active boot presentation uses native `qvos` Plymouth, SDDM, session,
  mkinitcpio, and UKI identities; completed pre-release theme and session
  convergence is not scanned at runtime, while exact inherited mkinitcpio and
  UKI artifacts remain preservation-safe migration input until separately
  verified
- native NOFILE and inotify tuning use only qvOS filenames; completed
  pre-release tuning convergence is not a fresh-install or update input
- XCompose creates one missing native seed and preserves every existing custom
  file; retired source-include rewriting is not an installer input
- the general pre-public runtime-root config rewriter and obsolete-state
  scanner are retired after the only supported installation converged; fresh
  install and update paths reconcile explicit native owners without scanning
  unrelated user trees
- `qvcore/boot/session-start` owns qvOS login and always passes the verified
  native Lua entrypoint explicitly to Hyprland through UWSM; generic
  `hyprland.desktop` discovery is forbidden because it can regenerate a
  `.conf` stub and discard qvOS configuration. The native launcher never
  mutates retired `.conf` state
- `qvcore/hardware/framework16-qmk-hid.rules` owns the Framework HID policy;
  `default/udev/` is retired
- `qvcore/power/unmount-fuse` owns the root-installed gvfs sleep hook; completed
  pre-release AC-rule, sleep-hook, and hibernation convergence is not scanned
  at runtime;
  qvOS carries no global GnuPG resolver policy or forced shutdown timeout
- `qvcore/network/warp-policy` owns the optional WARP daemon privacy boundary;
  its root-owned systemd drop-in keeps vendor state and logs private and stops
  credential-like daemon output from entering the journal without restricting
  the runtime IPC socket. Reconcile it before starting WARP and after package
  updates, restart only stale active policy with explicit live approval, and
  never read or expose registration data
- `qvcore/desktop/hyprland/` owns validated monitor scaling and event recovery,
  focused-window mutations, and workspace-layout changes; qvOS bindings and
  native autostart call only `qv-hyprland-*` routes, while one typed runtime
  bridge owns every bounded shell-side `hyprctl eval` and Lua dispatcher action;
  native shell/config callers never issue legacy dispatcher tokens directly
- qvOS-managed user units use `qvos-*` names and native `qvcore/` entrypoints;
  one shared probe limits manager access to the active account home, while a
  fresh chroot stages units for first run; retired inherited unit names remain
  absent
- Restartable long-running desktop components use stable `qvos-*` UWSM units
  so a restart stops the complete prior control group before relaunching
- Waybar and monitor-watch restarts stop only their stable qvOS unit and exact
  process; completed transient-unit convergence is not a runtime scan
- qvOS-managed installed runtime command trees expose only native names;
  retired Omarchy runtime aliases remain absent, and thin source adapters are
  the bounded external compatibility surface
- desktop application, browser, web-app, and terminal launching belongs to
  `qvcore/desktop/launch`; callers pass exact arguments and never shell strings
- custom Web App desktop entries belong to `qvcore/desktop/webapp`;
  installation and removal preserve foreign files, while fresh qvOS contains
  no preinstalled Web Apps, fixed service URLs, or service protocol handlers.
  Permanent inventory accepts only marked native qvOS launchers and treats
  historical Omarchy launch entries as foreign user data
- update and restart markers live privately under
  `~/.local/state/qvos/update`; arbitrary persistent state is not a CLI feature
- `qvcore/packages/provider/omarchy/` owns the credited Omarchy mirror and
  repository inputs; installed qvOS uses Stable with required package signatures,
  and release images preserve those signatures in their offline mirror
- qvOS installs the signed standard Arch kernel. Do not add an unsigned hardware
  repository or package set; T2 Macs are refused before disk selection until a
  verifiably signed provider can support their complete required stack
- local debug inventory belongs to `qvcore/security/debug`; it remains private,
  bounded, terminal-safe, and upload-free, with sudo limited to optional dmesg
- `qvcore/theme/yaqyn/` is the only bundled theme; `themes/` is retired
- `qvcore/theme/templates/` owns built-in color templates; compatible user
  overrides remain under `~/.config/qvos/themed/`
- `~/.config/qvos` owns active theme state; matching `~/.config/omarchy`
  theme paths are exact interoperability links only; current owners never
  adopt historical theme directories
- Active Omarchy config compatibility roots contain only reviewed relative
  links; current owners never scan or move historical compatibility state
- btop, Mako, and an installed Helix consume the native current-theme tree;
  Helix reconciliation creates only missing native state and preserves custom
  application configuration
- `qvcore/desktop/applications/` owns fixed desktop entries, package-menu
  suppressors, and the imv icon; the inherited top-level `applications/` tree
  is retired
- Fresh qvOS contains no Web App launchers or service-specific Web App assets;
  the generic installer remains available only for explicit user-created apps

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
`~/.local/share/qvos/qvcore/config/files/hypr/hyprlock.conf` to
`~/.config/hypr/hyprlock.conf` with a backup.

# Migrations

`qvcore/migrations/` is the only migration source. The inherited top-level
`migrations/` tree is retired and must remain absent; its historical outcomes
belong in fresh-install owners, never in a replayable qvOS update path.
`qvcore/migrations/run` serializes execution, fails closed, and records private
atomic markers under `~/.local/state/qvos/migrations`. Fresh installation marks
current migrations without executing them through its exact native owner. When
the supported upgrade floor advances, delete migrations that every supported
installation has completed; the runner removes only their exact safe empty
qvOS markers. Pre-release transition migrations must be retired before the
first public baseline, and the runner never reads inherited Omarchy state.

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
  Select official application packages from that repository; never make an
  `omarchy-*` application or meta-package part of the qvOS product surface.
- During the native transition, keep each inherited implementation byte-for-byte
  until its domain is promoted. Then port selected capability into one owner
  under `qvcore/<domain>/` or `qvcore/<feature>/` and remove the inherited
  implementation, overlay, adapter, fallback, and stale state together. qvOS
  tests live under `test/` and mirror their owner boundary. Record every
  implementation-sized inherited departure in the nearest `native-paths`
  manifest under `qvcore/`, `development/`, or `services/`.
- The complete installer is native under `qvcore/install/` and
  `qvcore/boot/login/`; the top-level `install/` tree is retired. Keep the
  singular native config source reconciled after install, refresh, migration,
  and update paths. Installed source
  is `~/.local/share/qvos`; retain only its exact `omarchy -> qvos` compatibility
  link, and keep runtime payloads under `~/.local/lib/qvos`. Permanent source
  reconciliation creates only that missing exact link; it never adopts or
  relocates historical source or runtime layouts.
- New persistent state is feature-owned and private under
  `~/.local/state/qvos`. User-editable qvOS configuration is feature-owned
  under `~/.config/qvos`; completed legacy-branding backups remain private and
  the active Branding owner reads only native state. Update intent accepts only
  reviewed reboot and service-restart markers under native private state; its
  completed pre-release state-root convergence is retired.
- Native installed identities use `qvos` or `qvOS`; `/etc/os-release` uses
  `ID=qvos` with `ID_LIKE=arch` and is installed only by the Branding owner. An
  `omarchy` name remains
  only at a documented compatibility frontend, exact installed-source link,
  truthful upstream input, or credited package-provider boundary.
- An unflagged ISO build must prove its pinned commit is the public `OS` head.
  `--pre-public` is only for development rehearsal; its unpublished shallow
  source is not releasable and update availability must fail closed unless an
  official fast-forward can be proven.
- Use thin, absent-safe adapters only as transition seams that complete a user
  task. qvCORE is mandatory; qvOS must remain complete and healthy with no
  optional Service or Development integration installed.
- Trace each feature through its command and adapters to installed config,
  state, hooks, permissions, services, network exposure, and focused tests.
  Verify fresh install, update, removal, and live behavior where applicable.
- Update availability combines the official qvOS source head with a read-only
  check of the configured package repositories. Package security updates must
  remain discoverable when source is current; availability checks may refresh
  only private temporary metadata and must never partially sync the live Pacman
  database.
- Preserve useful upstream capability through explicit review and native ports.
  Omit it when unsafe, incompatible, unwanted, or out of scope, and state why.
- Hardware policy that affects boot-time input must use exact supported-device
  evidence, publish through the transactional native owner, and fail before
  writing when its required module inventory is missing or ambiguous.
- Never patch a package-owned executable to change its interpreter or runtime
  environment; isolate that environment at the singular qvOS command owner.

## Zero Duplication

Reusable code has one shared owner. A second consumer must call or extract it
in the same change; thin adapters translate only. Fix shared bugs once, test
the owner and two consumers, and leave no equivalent implementation behind.

## Main qvsync Workflow

`qvsync` is the read-only upstream intake loop for independent Omarchy product
and Omarchy ISO histories. It never merges, cherry-picks, moves product
branches, makes upstream executable build input, or publishes refs.

1. Start with `git qvsync --audit`. Read every commit and diff in both reported
   ranges, then search qvOS owners, installed payloads, tests, and history for
   the same capability; filename overlap alone is not an audit. Keep
   `reviewed-upstream` and `reviewed-iso-upstream` independent.
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
7. Record Omarchy product commits in
   `upstream/qvsync/upstream-reviews/<target-sha>.psv` and ISO commits in
   `upstream/qvsync/iso-upstream-reviews/<target-sha>.psv`. Use the matching
   `--record-reviewed-upstream` or `--record-reviewed-iso-upstream` option only
   for its exact fetched target. Commit each ledger, baseline, and verified
   adaptation together; never advance one baseline as evidence for the other.
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
- Waybar configuration, runtime modules, refresh, and task actions: `qvcore/waybar/AGENTS.md`
- qvOS terminal interface and action flows: `qvcore/tui/AGENTS.md`
- Bash defaults, aliases, completion, and existing-user reconciliation: `qvcore/shell/AGENTS.md`
- Tmux session and configuration lifecycle: `qvcore/tmux/AGENTS.md`
- ISO construction and release images: `release/iso/AGENTS.md`
- qvOS configuration, assistant integration, and Thunar reconciliation:
  `qvcore/config/AGENTS.md`, `qvcore/config/assistant/AGENTS.md`,
  `qvcore/thunar/AGENTS.md`
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
