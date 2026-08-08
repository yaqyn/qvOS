# qvCORE

qvCORE is the mandatory native implementation of qvOS. qvOS is the complete
repository, distribution, and user-facing product; qvCORE owns its installed
product domains and is never presented as optional software.

Omarchy remains a read-only upstream. Keep an inherited implementation intact
until its domain is promoted, then port only selected capability into one qvOS
owner and remove the inherited implementation, overlay, adapter, and fallback
together. The end state has one native owner, not an upstream system plus an
active overlay.

Current product layout:

```text
qvcore/
  boot/        qvOS boot, Plymouth, SDDM, Limine, and session assets.
  branding/    qvOS vectors, approved terminal art, and private customization.
  browser/     Secure browser policy ownership.
  capture/     Private screenshots, OCR, and recoverable screen recording.
  cli/         Native qv command engine and Omarchy compatibility frontend.
  config/      qvOS config sources and reconciliation after Omarchy defaults.
  controls/    Audio, brightness, notification, and session OSD controls.
  defaults/    Browser, editor, and terminal default ownership.
  desktop/     Shared context, web, Hyprland, and runtime restart owners.
  direct/      Verified manifest-driven direct software and updates.
  font/        Installed font discovery and transactional configuration.
  hooks/       Private custom automation, installation, and state migration.
  install/     Complete native qvOS installation lifecycle.
  menu/        qvOS menus and Elephant deltas installed through Omarchy seams.
  migrations/  Native ordered migrations and private applied-state ownership.
  network/     qvOS DNS policy and optional WARP routing.
  packages/    Omarchy package-provider boundary and Stable configuration.
  power/       Telemetry, profiles, sleep guards, and opt-in battery protection.
  presentation/ qvOS terminal presentation and failure handling.
  reminder/    Private transient desktop reminders and legacy cleanup.
  screensaver/ Screensaver launchers and terminal profile.
  security/    Codex-operated security auditing and hardening workflow.
  share/       LocalSend request routing.
  shell/       qvOS shell additions.
  theme/       Bundled Yaqyn theme and compatible user-theme lifecycle.
  thunar/      Thunar feature entry points.
  tmux/        Persistent tmux session manager.
  transcode/   Atomic picture, video, and terminal-art conversion.
  tui/         Shared actions plus installer and progress presentation.
  update/      qvOS update preflight and presentation wrapper.
  version/     Installed source, branch, channel, and package-age reporting.
  waybar/      qvOS prayer clock modules.
  weather/     Bounded weather-provider parsing for Waybar and status.
  windows/     Windows VM configuration, safe removal, and rollback.
```

Top-level `services/proton/` owns the optional Proton Service and
`development/devel/` owns the optional workstation formerly named qvDEV. Each
exposes only user-facing Install and Uninstall actions and owns its
complete lifecycle independently. There is no qvCORE Software menu or qvCORE
enrollment state; qvCORE is the operating-system implementation itself.

## Product lifecycle

qvOS has one supported base: a solid, gaming-ready Arch system whose package
selection and compatibility policy are curated by qvOS. Omarchy supplies the
credited Stable Arch mirror, curated package repository, and signing keyring;
qvOS does not rebuild, resign, relabel, or mirror that package infrastructure.
Native `qv-pkg-*` commands own validated Pacman and explicit AUR operations;
matching `omarchy-pkg-*` names are direct compatibility adapters only.
The base keeps Omarchy's on-demand OpenAI Codex wrapper plus software with an
independent qvOS, Omarchy, gaming, hardware, or desktop purpose. The package
resolver validates singular qvOS base and conditional-hardware manifests;
upstream package changes are capability-review input, never an automatic change
to the qvOS package set.
Steam remains optional and uses its standard gaming installer and remover.
Services and Development integrations never change qvOS base readiness.

- `qv update` confirms the operation and verifies a clean branch
  `OS`, then delegates once to the qvOS update pipeline. qvOS owns a bounded,
  official-origin, fast-forward-only source update; the preserved pipeline owns
  snapshots, complete package updates from Omarchy Stable, migrations, orphan
  cleanup, log analysis, and restarts. After Pacman/AUR, one direct-tool hook
  updates only
  already-installed manifest entries belonging to Devel and Proton. It never
  restores missing tools, enrolls integrations, authenticates
  accounts, changes integrations, or changes networking.
- `qv` is the primary user-facing command. `omarchy` remains a compatibility
  frontend for inherited scripts and upstream tooling; both use the one native
  qvOS command engine.
- Promoted commands expose `qv-*` metadata and one native owner; exact
  `omarchy-*` names remain metadata-free compatibility only while required.
- Desktop restart commands are native under `qvcore/desktop/restart/`. Native
  qvOS consumers use `qv-restart-*`; exact `omarchy-restart-*` names remain
  direct compatibility adapters for inherited consumers and external callers.
- Font discovery, current-state reporting, and configuration mutation are
  native under `qvcore/font/`. One serialized transaction validates and stages
  every supported config, preserves optional terminal settings and Arabic
  fallback fonts, and restores earlier files if an atomic replacement fails.
- Custom automation is native under `qvcore/hooks/` and private under
  `~/.config/qvos/hooks`. qvOS runs system update jobs directly from their
  tracked feature owners; the custom tree contains only user automation and
  disabled samples. Exact Omarchy hook commands are compatibility adapters.
- Proton appears under Services and Devel appears under Development. Each row
  is Install when unenrolled and Uninstall when enrolled. Install converges
  only missing pieces, configures and verifies the integration, then records
  enrollment under its truthful product state path. Removal deletes the
  enrolled software and qvOS integration while preserving personal files,
  browser profiles, credentials, authentication state, projects, and cloud
  data.
- Codex remains Omarchy-owned through its standard on-demand NPM installation.
  qvOS preserves that upstream step but does not replace or separately update
  Codex.
- Devel unifies developer and Codex workstation ownership. It owns
  developer-specific Pacman packages, mise tools, verified provider binaries,
  Semgrep, Dev Container CLI, and Codex desktop/workbench integration. It uses
  base-owned system Python and mise, creates no global mise Python, and cannot
  remove Omarchy Codex. It also owns the official global Playwright CLI;
  Wrangler, Convex, Playwright dependencies, and Playwright browser assets
  remain project-local. Install checks every inventory entry and installs only
  what is missing before verifying the complete stack.
- The qvOS TUI exposes Update, ISO Build, state-aware Software actions, and
  fixed classified desktop tasks. Three rings identify system-critical or
  high-impact work, two rings identify simple Software install/remove work,
  and one ring identifies ordinary safe tasks. Every action reuses one shared
  authorization, progress, log, and result flow while delegating the mutation
  once to the existing Omarchy or qvOS owner. Information opens directly,
  privileged work uses sudo as its only start gate, and consequential
  unprivileged work confirms once. Allowlisted fixed tasks may collect a
  searchable owner-provided selection, and captured actions may defer a
  required reboot to the shared Reboot Now/Later result. Structured owner
  forms collect bounded configuration and secrets through a private runtime
  file before authorization. Owners with unresolved authentication, hardware
  interaction, or nested TUIs retain their native terminal.
  Install-only selectors keep their browse shape, but every stream-safe leaf
  uses that same TUI flow and verifies its real installed result.
  Installed fonts additionally expose owner-derived Apply and exact Uninstall
  actions; removing the active font restores JetBrains Mono first.
  ISO Build stages the qvOS source over the reviewed source-backed Omarchy ISO
  builder commit, adds the qvOS configurator and progress surfaces, and
  preserves its reviewed disk-install and post-install orchestration.

Returning to upstream Omarchy is not an in-place qvOS lifecycle. It requires a
separate documented installation rather than a source, branch, or config reset.

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
`~/.local/lib/qvos`, never inside the checkout. Boot, config, and remaining
upstream ABI names stay unchanged until their complete lifecycles can move
safely together.

Update and restart intent lives privately under `~/.local/state/qvos/update`.
The native state owner accepts only reboot and validated service-restart
markers, migrates exact legacy markers, and removes an empty Omarchy state root.
It is not a general-purpose settings store.

`qvcore/security/` owns the Codex-operated Lynis audit, a small nonrestrictive
sysctl baseline, signed-package and localhost-first container defaults, the
temporary private-LAN development preview, and the balanced-hardening
workflow. Its reports contain private system inventory, stay outside Git under
the user's state directory, and never authorize automatic hardening.

`qvcore/thunar/actions.sh` is the preservation-safe owner for qvOS custom actions.
The base desktop installs its default helpers, including the LocalSend Share
action for Omarchy's base package, and preserves optional integration payloads
without reinstalling them. Proton and Devel install and remove their own
actions.

## Native transition boundary

Promoted base domains live in `qvcore/`. Until a domain is promoted, keep its
inherited implementation intact and touch Omarchy paths only at the seam that
exposes, installs, or refreshes the native owner:

- `bin/` owns CLI routes and menu handoffs.
- `config/` owns promoted qvOS defaults such as the singular binding source and
  native `qvos-*` user units; `qvcore/config/` owns toggle templates, private
  state migration, service reconciliation, and specialized sources that still
  need a separate installed path. Unpromoted inherited `config/` and `default/`
  paths remain upstream-owned.
- `qvcore/install/` owns the complete fresh-install implementation and
  `qvcore/boot/login/` owns its login leaves. The retired top-level `install/`
  tree must not return. Existing-system transitions live only in
  `qvcore/migrations/`; the historical top-level migration tree is retired.
- `test/qvcore/run.sh` recursively runs the qvCORE, Services, Development,
  Release, Upstream, Compatibility, and inherited root shell suites after
  clearing ambient source-root overrides so fixtures cannot silently read the
  live installation.
- `qvcore/theme/yaqyn/` is qvOS's only bundled theme. The renderer reads Yaqyn and
  compatible custom themes only from the user theme directory; users can copy
  Yaqyn, install an Omarchy-format Git theme, or link one from elsewhere.

When promoting a base domain, trace every seam back to its `qvcore/` owner.
Optional integrations live only under `services/` or `development/`. Choose one
implementation, remove duplicate paths, and verify fresh install, update,
removal, and live behavior. qvsync reports later upstream changes for selective
review but never merges them into qvOS.
