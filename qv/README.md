# qv

qvOS-owned source lives here.

Keep upstream Omarchy files in their existing locations whenever practical. Put qvOS-only helpers, assets, and generated support files under this namespace so upstream syncs stay easy to review.

Expected layout:

```text
qv/
  boot/        qvOS boot, Plymouth, SDDM, Limine, and session assets.
  branding/    qvOS terminal and desktop branding.
  browser/     Secure browser policy ownership.
  codex/       Codex workstation capability contract and read-only doctor.
  config/      qvOS config helpers and files installed after Omarchy defaults.
  core/        qvCORE two-stack catalog and lifecycle owners.
  diagnostics/ qvOS diagnostic policy layered over Omarchy's command.
  desktop/     Shared context, web, and Hyprland desktop helpers.
  direct/      Verified manifest-driven direct software and updates.
  git/         Private git helper source and installers.
  hyprland/    qvOS Hyprland refresh reconciliation.
  install/     qvOS stages applied after Omarchy installation.
  iso/         ISO integration patches.
  launcher/    qvOS Elephant providers.
  maintenance/ qvOS base repair, personal-software inventory, and upstream guards.
  menu/        qvOS menus installed through Omarchy's extension seam.
  network/     qvOS DNS policy and optional WARP routing.
  power/       Sleep inhibition and guarded suspend.
  presentation/ qvOS terminal presentation and failure handling.
  screensaver/ Screensaver launchers and terminal profile.
  share/       Shared notification and LocalSend request routing.
  shell/       qvOS shell additions.
  theme/       The Yaqyn qvOS theme overlay.
  thunar/      Thunar feature entry points.
  tmux/        Persistent tmux session manager.
  tui/         ISO installer, progress UI, and image build tooling.
  update/      qvOS update preflight and presentation wrapper.
  waybar/      qvOS prayer clock modules.
```

qvCORE is an optional two-stack collection, not a qvOS subsystem. Its complete
catalog is Proton and qvDEV. Every stack exposes only Install and Remove.

## Product lifecycle

qvOS has one supported base: a solid, gaming-ready Arch system curated through
Omarchy. The base includes canonical OpenAI Codex plus software with an
independent qvOS, Omarchy, gaming, hardware, desktop, or Recovery purpose.
Steam remains optional and uses Omarchy's standard gaming installer and
remover. qvCORE adds optional integrated stacks without changing qvOS
identity, readiness, health, or Recovery ownership.

- `omarchy qvos update` confirms the operation and verifies branch `OS`, then
  delegates once to the original `omarchy update` implementation. Omarchy owns
  snapshots, source and package updates, migrations, orphan cleanup, log
  analysis, and restarts. After Pacman/AUR, one direct-tool hook updates only
  already-installed manifest entries belonging to Codex base, qvDEV, and
  Proton. It never restores missing tools, installs stacks, authenticates
  accounts, repairs integrations, or changes networking.
- `omarchy qvos health` is the read-only qvOS Recovery v2 inspection. Stable
  findings are Ready, Repairable, Blocked, or Informational across Pacman,
  essential and running-hardware packages, source integrity, runtime and
  config, storage, network readiness, and the Hyprland login session. A
  completed report exits successfully; `--check` returns nonzero only for
  Repairable or Blocked findings. Offline readiness and intentionally removed
  defaults remain informational.
- `qv repair` is a real `~/.local/bin` recovery front door suitable for a TTY.
  Its engine and essential-package policy run from
  `~/.local/share/qvos/maintenance`, independently of optional UI tools and
  source-tree health. Other `qv` arguments pass through to Omarchy.
- `omarchy qvos repair` and `qv repair` use the same runtime engine. Safe Repair
  restores damaged essential or selected hardware packages, runtime bytes and
  modes, missing config, same-byte config mode drift, and only affected
  services. It preserves removed defaults and customized config. Before the
  first persistent change, repair revalidates Pacman, storage, and source after
  sudo, then proves a newer root Snapper snapshot. `--reset` additionally
  reinstalls removable defaults and backup-restores qvOS-owned config.
  `--yes` selects Safe Repair and can never unlock a session.
- Hyprland recovery can wake all-asleep outputs, start a replacement locker
  for an exact same-user compositor signature, and—only after replacement
  failure plus explicit sad-face confirmation—ask Hyprland to clear its
  crashed lock. It never clears a healthy locker, restarts SDDM, stops UWSM, or
  kills the active compositor.
- Recovery v2 Phase 1 targets a booted but damaged installation. Kernel,
  module, UKI, Limine, and mkinitcpio rebuilds; mounted-filesystem repair;
  comprehensive snapshot restore; networking mutation; and offline/unbootable
  rescue remain outside this phase. qvCORE is never graded or repaired.
- The qvCORE menu shows the two stacks directly. Each row is Install when
  unenrolled and Remove when enrolled. Install converges only missing pieces,
  configures and verifies the stack, then records enrollment. Remove deletes
  the complete enrolled stack and its qvOS integration while preserving
  personal files, browser profiles, credentials, authentication state,
  projects, and cloud data.
- `qv codex doctor` is the read-only Codex workstation inspection. Its tracked
  capability contract separates guaranteed base capabilities, qvDEV,
  project-local tools, and commands that should stay absent. `--json` emits the
  stable machine-readable report; `--check` fails only when the guaranteed
  Codex foundation needs repair. Optional Browser and Documents profiles remain
  explicitly unavailable until their owners ship.
- qvDEV unifies developer and Codex workstation ownership. It owns
  developer-specific Pacman packages, mise tools, verified provider binaries,
  Semgrep, Dev Container CLI, and Codex desktop/workbench integration. It uses
  base-owned system Python and mise, creates no global mise Python, and cannot
  remove base Codex. Wrangler, Convex, and Playwright remain project-local.
- `omarchy qvos software` inventories software added after the immutable
  fresh-install qvOS baseline. It covers explicit Pacman/AUR packages, Bun and
  npm globals, persistent npx wrappers, AppImages, and standalone executables
  in standard user or system locations, including common single-binary
  curl/GitHub installs. Active qvOS package manifests, direct-tool manifest
  commands, and qvOS-owned runtime remain protected. qvCORE has no
  personal-software ownership or coordinated-removal layer;
  `--remove-standalone` limits the visible inventory to global packages,
  AppImages, and standalone paths. The broad `--remove` route remains
  compatibility-only. Removal changes only explicit selections after
  confirmation; package managers retain ownership of their packages, user
  files move to Trash, and system standalone removal targets one exact path.
- Existing installations without a fresh-install baseline must run
  `omarchy qvos software --initialize` explicitly. qvOS does not fabricate
  historical ownership from the current package list.
- The qvOS TUI exposes Update, Repair, and ISO Build only. ISO Build stages the
  qvOS source over Omarchy's `main` ISO for its matching `master` installer,
  adds the qvOS configurator and progress surfaces, and preserves Omarchy's
  disk-install and post-install orchestration.

Returning to upstream Omarchy is not an in-place qvOS lifecycle. It requires a
separate documented installation rather than a source, branch, or config reset.

`qv/thunar/actions.sh` is the preservation-safe owner for qvOS custom actions.
The base desktop installs its default helpers, including the LocalSend Share
action for Omarchy's base package, and preserves optional stack payloads
without repairing them. Proton and qvDEV install and remove their own actions.

## Upstream boundary

Keep implementations in `qv/`; touch inherited Omarchy paths only at the seam
that exposes, installs, or refreshes them:

- `bin/` owns CLI routes and menu handoffs.
- `qv/config/files/` owns qvOS config sources; inherited `config/` and
  `default/` remain upstream-owned.
- `install/` owns fresh-install payloads. Future existing-system transitions
  belong in `qv/migrations/` behind thin Omarchy migration stubs.
- `test/qvos/*-test.sh` guards qvOS product and integration contracts;
  `test/qvos/run.sh` runs them together with all upstream root tests.
- `qv/theme/yaqyn/` is the qvOS theme overlay; Omarchy's inherited theme
  catalog remains available.

When one of these seams changes, trace it back to its `qv/` owner and verify
both the fresh-install and update paths. This keeps qvsync conflicts localized
and makes intentional omissions from upstream visible during review.
