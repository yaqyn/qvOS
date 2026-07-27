# qv

qvOS-owned source lives here.

Keep upstream Omarchy files in their existing locations whenever practical. Put qvOS-only helpers, assets, and generated support files under this namespace so upstream syncs stay easy to review.

Expected layout:

```text
qv/
  boot/        qvOS boot, Plymouth, SDDM, Limine, and session assets.
  branding/    qvOS terminal and desktop branding.
  browser/     Secure browser policy ownership.
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
- Managed setups (`WARP`, `Share`, `Proton`, and Gaming Dependencies) have extra
  configuration or dependency ownership. Only these setups participate in
  qvCORE status, repair, disable, and post-update integration maintenance.

## Product lifecycle

qvOS has one supported base: a solid, unbloated Arch system curated through
Omarchy. qvCORE is separate and adds optional personal software without
changing qvOS identity, readiness, health, or base ownership.

- `omarchy qvos update` confirms the operation and verifies branch `OS`, then
  delegates once to the original `omarchy update` implementation. Omarchy owns
  snapshots, source and package updates, migrations, orphan cleanup, log
  analysis, and restarts. A silent qvCORE post-update hook maintains only
  enabled WARP, Share, and Proton integration state; it never installs or
  updates curated apps.
- `omarchy qvos health` is the read-only qvOS base inspection. It checks the
  source branch, missing base config, customized config, and installed qvOS
  runtime without grading personal software. A completed report exits
  successfully even when it recommends repair; `--check` returns nonzero when
  automation requires a healthy base.
- `omarchy qvos repair` uses the same base inspection. Safe repair restores
  missing config and tracked runtime while preserving package removals and
  customization as user intent. `--reset` is the explicit, backup-backed path
  that reinstalls missing packages from the original qvOS manifest and
  restores every qvOS-owned config file from tracked source. It does not repair
  or reinstall qvCORE software.
- `omarchy install qvcore` installs everything. `apps` installs only the
  curated app catalog, `setups` installs only managed setups, and every
  component remains independently installable.
- `omarchy qvcore status` and `omarchy qvcore repair` cover only WARP, Share,
  Proton, and Gaming Dependencies. `omarchy qvcore disable` removes only enabled
  WARP, Share, or Proton integration state while preserving their software and
  personal data. Status reports exit successfully when inspection completes;
  `status --check` returns nonzero when a managed setup needs attention.
- `omarchy qvos software` inventories software added after the immutable
  fresh-install qvOS baseline. It covers explicit Pacman/AUR packages, Bun and
  npm globals, persistent npx wrappers, AppImages, and standalone executables
  in standard user or system locations, including common single-binary
  curl/GitHub installs. Active qvOS package manifests and qvOS-owned runtime
  remain protected. qvCORE-curated software is shown as ordinary personal
  software even when an older baseline captured them. Removing WARP, Share,
  Proton, or Codex software delegates idempotent integration cleanup to its
  owner first. `--remove` changes only explicit selections
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
