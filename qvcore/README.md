# qvCORE

qvCORE is the mandatory native implementation of qvOS. qvOS is the complete
repository, distribution, and user-facing product; qvCORE owns its installed
product domains and is never presented as optional software.

Each installed capability has one qvOS owner. Reviewed upstream work may inform
that owner, but never creates a second active implementation. When a domain is
promoted, remove every superseded implementation, overlay, adapter, and
fallback together.

Current product layout:

```text
qvcore/
  boot/        qvOS boot, Plymouth, SDDM, Limine, and session assets.
  branding/    qvOS vectors, approved terminal art, and private customization.
  browser/     Secure browser policy ownership.
  capture/     Private screenshots, OCR, and recoverable screen recording.
  cli/         Native qv command engine and compatibility frontend.
  config/      Singular installed config sources and reconciliation.
  controls/    Audio, brightness, notification, and session OSD controls.
  defaults/    Browser, editor, and terminal default ownership.
  desktop/     Shared context, web, Hyprland, session, and restart owners.
  direct/      Verified manifest-driven direct software and updates.
  font/        Installed font discovery and transactional configuration.
  hooks/       Private custom automation, installation, and sample seeding.
  install/     Complete native qvOS installation lifecycle.
  menu/        Native qvOS menus, search, Walker, and Elephant integration.
  migrations/  Native ordered migrations and private applied-state ownership.
  network/     qvOS DNS policy and optional private WARP routing.
  packages/    Signed package-provider boundary and Stable configuration.
  power/       Telemetry, root-owned AC events, sleep guards, and battery policy.
  presentation/ qvOS terminal presentation and failure handling.
  reminder/    Private transient desktop reminders and legacy cleanup.
  screensaver/ Screensaver launchers and terminal profile.
  security/    Codex-operated security auditing and hardening workflow.
  share/       LocalSend request routing.
  shell/       qvOS shell additions.
  storage/     Validated drive discovery, selection, and LUKS key changes.
  theme/       Bundled Yaqyn theme and compatible user-theme lifecycle.
  thunar/      Thunar feature entry points.
  tmux/        Persistent tmux session manager.
  transcode/   Atomic picture, video, and terminal-art conversion.
  tui/         Shared actions plus installer and progress presentation.
  update/      qvOS update preflight and presentation wrapper.
  version/     Installed source, branch, channel, and package-age reporting.
  waybar/      Waybar lifecycle, native modules, and workspace-state tracking.
  weather/     Bounded weather-provider parsing for Waybar and status.
  windows/     Windows VM configuration, safe removal, and rollback.
```

Top-level `services/proton/` owns the optional Proton Service and
`development/devel/` owns the optional Devel workstation. Each exposes only
user-facing Install and Uninstall actions and owns its
complete lifecycle independently. There is no qvCORE Software menu or qvCORE
enrollment state; qvCORE is the operating-system implementation itself.

## Product lifecycle

qvOS has one supported base: a solid, gaming-ready Arch system whose package
selection and compatibility policy are curated by qvOS. It consumes the
credited Omarchy Stable mirror, package repository, and signing keyring without
rebuilding, resigning, relabeling, or mirroring that infrastructure.
Native `qv-pkg-*` commands own validated Pacman and explicit AUR operations;
matching `omarchy-pkg-*` names are direct compatibility adapters only.
The base keeps Codex through the signed configured repositories plus software
with an independent qvOS, upstream-compatibility, gaming, hardware, or desktop
purpose. The package resolver validates singular qvOS base and
conditional-hardware manifests; upstream package changes are capability-review
input, never an automatic change to the qvOS package set.
Steam remains optional and uses its standard gaming installer and remover.
Services and Development integrations never change qvOS base readiness.

- `qv update` confirms the operation and verifies a clean branch
  `OS`, then delegates once to the qvOS update pipeline. qvOS owns a bounded,
  official-origin, fast-forward-only source update; the preserved pipeline owns
  snapshots, complete package updates from the configured Stable provider,
  migrations, orphan cleanup, log analysis, and restarts. After Pacman/AUR,
  one direct-tool hook
  updates only
  already-installed manifest entries belonging to Devel and Proton. It never
  restores missing tools, enrolls integrations, authenticates
  accounts, changes integrations, or changes networking.
- `qv` is the primary user-facing command. `omarchy` is the compatibility
  frontend for external callers; both use the one native
  qvOS command engine.
- CLI benchmarking and command-metadata documentation are native, bounded,
  read-only `qvcore/cli/` tools and describe qvOS routes exclusively.
- Promoted commands expose `qv-*` metadata and one native owner; exact
  `omarchy-*` names remain metadata-free compatibility only while required.
- Desktop restart commands are native under `qvcore/desktop/restart/`. Native
  qvOS consumers use `qv-restart-*`; exact `omarchy-restart-*` names remain
  direct compatibility adapters for inherited consumers and external callers.
- Hyprland window, workspace, scaling, and monitor-recovery controls are native
  under `qvcore/desktop/hyprland/`. They validate compositor state before
  mutation; matching compatibility names remain direct adapters only.
- Desktop application, browser, web-app, terminal-app, and focus-or-launch
  behavior is native under `qvcore/desktop/launch/`. It preserves exact
  arguments, validates compositor and browser state, and contains no
  caller-controlled shell evaluation. One native `qv-launch-app` owner invokes
  canonical `uwsm app` for every qvOS application launch; the package-owned fast
  shell client is not a runtime dependency. Matching inherited names are
  compatibility adapters only, while this qvOS-only boundary has none.
- Custom Web App creation, inventory, removal, and migration are native under
  `qvcore/desktop/webapp/`. They validate every URL and target, preserve foreign
  desktop entries, and permit no arbitrary Exec payload. Fresh qvOS includes
  no Web App instance, fixed service binding, service handler, or related icon.
- Font discovery, current-state reporting, and configuration mutation are
  native under `qvcore/font/`. One serialized transaction validates and stages
  every supported config, preserves optional terminal settings and Arabic
  fallback fonts, and restores earlier files if an atomic replacement fails.
- Custom automation is native under `qvcore/hooks/` and private under
  `~/.config/qvos/hooks`. qvOS runs system update jobs directly from their
  tracked feature owners; the custom tree contains only user automation and
  disabled samples. Exact `omarchy-hook*` commands are compatibility adapters.
- Proton appears under Services and Devel appears under Development. Each row
  is Install when unenrolled and Uninstall when enrolled. Install converges
  only missing pieces, configures and verifies the integration, then records
  enrollment under its truthful product state path. Removal deletes the
  enrolled software and qvOS integration while preserving personal files,
  browser profiles, credentials, authentication state, projects, and cloud
  data.
- Codex is qvOS-base-owned through its signed repository package and follows
  the normal Pacman update transaction; no global NPM installation path may
  replace it.
- Devel unifies developer and Codex workstation ownership. It owns
  developer-specific Pacman packages, mise tools, verified provider binaries,
  Semgrep, Dev Container CLI, and Codex desktop/workbench integration. It uses
  base-owned system Python and mise, creates no global mise Python, and cannot
  remove base-owned Codex. It also owns the official global Playwright CLI;
  Wrangler, Convex, Playwright dependencies, and Playwright browser assets
  remain project-local. Install checks every inventory entry and installs only
  what is missing before verifying the complete stack.
- The qvOS TUI exposes Update, ISO Build, state-aware Software actions, and
  fixed classified desktop tasks. Three rings identify system-critical or
  high-impact work, two rings identify simple Software install/remove work,
  and one ring identifies ordinary safe tasks. Every action reuses one shared
  authorization, progress, log, and result flow while delegating the mutation
  once to a native qvOS or explicitly retained compatibility owner.
  Information opens directly, privileged work uses sudo as its only start
  gate, and consequential unprivileged work confirms once. Allowlisted fixed
  tasks may collect a
  searchable owner-provided selection, and captured actions may defer a
  required reboot to the shared Reboot Now/Later result. Structured owner
  forms collect bounded configuration and secrets through a private runtime
  file before authorization. Owners with unresolved authentication, hardware
  interaction, or nested TUIs retain their native terminal.
  Install-only selectors keep their browse shape, but every stream-safe leaf
  uses that same TUI flow and verifies its real installed result.
  Installed fonts additionally expose owner-derived Apply and exact Uninstall
  actions; removing the active font restores JetBrains Mono first.
  ISO Build delegates to the native qvOS Archiso builder and profile under
  `release/iso/`, embedding the exact pinned qvOS source and singular TUI
  installer. The ISO upstream is a separately audited, read-only qvsync
  reference, never executable build input. The native image uses one signed provider
  policy for online resolution and the offline mirror, boots the standard Arch
  kernel, and refuses T2 Macs whose required third-party stack is not available
  through that verifiable boundary.

Changing distributions requires a separate documented installation; a source,
branch, or configuration reset never replaces qvOS.

## Internal namespace boundary

New qvOS-owned state, providers, services, and runtime identifiers use `qvos`
or `qvOS`. Preserve an `omarchy` identifier only when it is a stable public
command, upstream environment or path contract, installed-state compatibility
key, package name, or truthful upstream integration. Do not add parallel qvOS
aliases merely to hide a compatibility name.

Migrate a legacy internal name only with its complete domain owner: validate
the old artifact, move or replace its state atomically, remove the old source
and generated residue, update every consumer, and guard both the new identity
and cleanup path in focused tests. The installed source is now canonical at
`~/.local/share/qvos`; the exact relative `omarchy -> qvos` link is its only
source-root compatibility seam. Generated runtime payloads live under
`~/.local/lib/qvos`, never inside the checkout. Boot presentation now uses
native `qvos` Plymouth, SDDM, session, mkinitcpio, and UKI identities; exact
legacy boot artifacts are accepted only as preservation-safe migration input.
Remaining upstream ABI names stay unchanged until their complete lifecycles
can move safely together.

Update and restart intent lives privately under `~/.local/state/qvos/update`.
The native state owner accepts only reboot and validated service-restart
markers. Completed pre-release marker migration is retired, and the owner never
scans or recreates an inherited state root. It is not a general-purpose
settings store.

`qvcore/security/` owns the Codex-operated Lynis audit, a small nonrestrictive
sysctl baseline, signed-package and localhost-first container defaults, the
temporary private-LAN development preview, and the balanced-hardening
workflow. Its reports contain private system inventory, stay outside Git under
the user's state directory, and never authorize automatic hardening.
It also owns bounded local debug collection: output is control-sanitized,
private, explicitly viewed or uniquely saved, and never uploaded.

`qvcore/thunar/actions.sh` is the preservation-safe owner for qvOS custom actions.
The base desktop installs its default helpers, including the LocalSend Share
action for the base-owned LocalSend package, and preserves optional integration
payloads without reinstalling them. Proton and Devel install and remove their
own actions.

## Native ownership boundary

All active base domains live in `qvcore/`. If qvsync identifies a future
upstream capability that qvOS does not yet own, keep that upstream
implementation untouched until the complete domain is deliberately promoted;
change compatibility paths only at their audited seam:

- `bin/` owns CLI routes and menu handoffs.
- `qvcore/config/files/` owns every installed user-config source;
  `qvcore/config/` owns its atomic refresh, toggle templates, private state
  migration, and service reconciliation. The inherited top-level `config/`
  tree and the inherited top-level `default/` source tree are retired.
  Domain-owned defaults must remain under their native `qvcore/` owner.
- `qvcore/install/` owns the complete fresh-install implementation and
  `qvcore/boot/login/` owns its login leaves. The retired top-level `install/`
  tree must not return. Existing-system transitions live only in
  `qvcore/migrations/`; the historical top-level migration tree is retired.
- `test/qvcore/run.sh` recursively runs the qvCORE, Services, Development,
  Release, Upstream, Compatibility, and inherited root shell suites after
  clearing ambient source-root overrides so fixtures cannot silently read the
  live installation. An exact canonical shallow installed source explicitly
  skips only the development upstream-overlay comparison when neither upstream
  ref is embedded; it still runs every applicable suite, reports the skip, and
  never fetches history. Full and noncanonical development checkouts must carry
  the tracked upstream ref and run that comparison.
- `qvcore/theme/yaqyn/` is qvOS's only bundled theme. The renderer reads Yaqyn and
  compatible custom themes only from the user theme directory; users can copy
  Yaqyn, install an Omarchy-format Git theme, or link one from elsewhere.

When promoting a base domain, trace every seam back to its `qvcore/` owner.
Optional integrations live only under `services/` or `development/`. Choose one
implementation, remove duplicate paths, and verify fresh install, update,
removal, and live behavior. qvsync reports later upstream changes for selective
review but never merges them into qvOS.
