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
  core/        qvCORE personal-software catalog and managed setup owners.
  diagnostics/ qvOS diagnostic policy layered over Omarchy's command.
  desktop/     Shared context, web, and Hyprland desktop helpers.
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

qvCORE is an optional personal-software catalog, not a qvOS subsystem. It has
two layers:

- Apps (`Brave`, `Devel`, `Codex`, and `Media`) are curated shortcuts for
  installing ordinary personal software.
- Managed setups (`WARP`, `Share`, and `Proton`) have extra configuration
  ownership. Only these setups participate in qvCORE status, repair, disable,
  and post-update integration maintenance.

## Product lifecycle

qvOS has one supported base: a solid, gaming-ready Arch system curated through
Omarchy. Its reviewed gaming runtime is installed from the qvOS base package
manifest. Steam remains optional and uses Omarchy's standard gaming installer
and remover. qvCORE is separate and adds optional personal software without
changing qvOS identity, readiness, health, or base ownership.

- `omarchy qvos update` confirms the operation and verifies branch `OS`, then
  delegates once to the original `omarchy update` implementation. Omarchy owns
  snapshots, source and package updates, migrations, orphan cleanup, log
  analysis, and restarts. A silent qvCORE post-update hook maintains only
  enabled WARP, Share, and Proton integration state; it never installs or
  updates curated apps.
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
- `omarchy install qvcore` installs everything. `apps` installs only the
  curated app catalog, `setups` installs only managed setups, and every
  component remains independently installable.
- `qv codex doctor` is the read-only Codex workstation inspection. Its tracked
  capability contract separates guaranteed base primitives, qvCORE Devel,
  project-local tools, and commands that should stay absent. `--json` emits the
  stable machine-readable report; `--check` fails only when the guaranteed
  Codex foundation needs repair. Optional Browser and Documents profiles remain
  explicitly unavailable until their owners ship.
- `omarchy qvcore status` and `omarchy qvcore repair` cover only WARP, Share,
  and Proton. `omarchy qvcore disable` removes only enabled setup ownership or
  integration state while preserving software and personal data. Status
  reports exit successfully when inspection completes; `status --check`
  returns nonzero when a managed setup needs attention.
- `omarchy qvcore remove` is the removal surface for curated qvCORE software.
  Coordinated owners remove together. Brave Origin reuses Omarchy's browser
  cleanup while preserving its profile and personal data.
- `omarchy qvos software` inventories software added after the immutable
  fresh-install qvOS baseline. It covers explicit Pacman/AUR packages, Bun and
  npm globals, persistent npx wrappers, AppImages, and standalone executables
  in standard user or system locations, including common single-binary
  curl/GitHub installs. Active qvOS package manifests and qvOS-owned runtime
  remain protected. qvCORE-curated software is shown as ordinary personal
  software even when an older baseline captured them. Removing WARP, Share,
  Proton, or Codex software delegates idempotent integration cleanup to its
  owner first. `--remove-standalone` limits the visible inventory to global
  packages, AppImages, and standalone paths; `--remove-qvcore` limits it to
  qvCORE ownership. The broad `--remove` route remains compatibility-only.
  Removal changes only explicit selections
  after confirmation; package managers retain ownership of their packages,
  user files move to Trash, and system standalone removal targets one exact
  path.
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
The base desktop installs only the default Thunar helpers; optional Share,
Codex, and Proton helpers are installed and repaired by their qvCORE component.

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
