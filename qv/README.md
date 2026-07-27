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
  core/        Opt-in qvCORE integration components.
  diagnostics/ qvOS diagnostic policy layered over Omarchy's command.
  desktop/     Shared context, web, and Hyprland desktop helpers.
  git/         Private git helper source and installers.
  hyprland/    qvOS Hyprland refresh reconciliation.
  install/     qvOS stages applied after Omarchy installation.
  iso/         ISO integration patches.
  launcher/    qvOS Elephant providers.
  maintenance/ qvOS base repair, inherited-extra review, and upstream guards.
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

qvCORE components marked `# qvcore:lifecycle=1` own four local operations:
`--status`, `--repair`, `--adopt`, and `--disable`. One base-owned maintenance
seam checks only explicitly enabled setup state and delegates to the component
owner. It stays silent when qvCORE is unused, ignores optional applications
that were never enabled, and retires setup state when an application is later
removed.

## Product lifecycle

qvOS has one supported base: a solid, unbloated Arch system curated through
Omarchy. qvCORE is separate and adds optional curated setups without changing
qvOS identity, readiness, or base ownership.

- `omarchy qvos update` confirms the operation and verifies branch `OS`, then
  delegates once to the original `omarchy update` implementation. Omarchy owns
  snapshots, source and package updates, migrations, orphan cleanup, log
  analysis, and restarts. qvOS and enabled qvCORE reconciliation stay in
  Omarchy's existing post-update hook seam.
- `omarchy qvos repair` first inventories removed default packages, missing or
  customized qvOS config, owned runtime, and enabled qvCORE integrations. Safe
  repair restores missing config and tracked runtime while preserving package
  removals and customization as user intent. `--reset` is the explicit,
  backup-backed path that reinstalls missing packages from the original qvOS
  manifest and restores every qvOS-owned config file from tracked source.
- `omarchy qvcore status` inventories the complete optional catalog. It
  distinguishes healthy or repairable integrations from available, partial,
  and uninstalled software; optional absence is never damage.
- `omarchy qvcore repair` lets the user choose exactly one component. Enabled
  persistent integrations use their repair owner, installed applications can
  be adopted, and missing software is installed only after explicit selection.
  Automatic update and qvOS repair hooks remain limited to enabled persistent
  integrations.
- `omarchy qvcore disable` removes only enabled qvOS-owned integration and
  maintenance state. Installed applications, authentication, network choices,
  and personal data remain.
- `omarchy qvos cleanup inherited` previews a reviewed legacy package catalog.
  Applying cleanup still requires explicit package selection and confirmation.
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
