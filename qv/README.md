# qv

qvOS-owned source lives here.

Keep upstream Omarchy files in their existing locations whenever practical. Put qvOS-only helpers, assets, and generated support files under this namespace so upstream syncs stay easy to review.

Expected layout:

```text
qv/
  boot/        qvOS boot, Plymouth, SDDM, Limine, and session assets.
  branding/    qvOS terminal and desktop branding.
  browser/     Secure browser policy ownership.
  config/      qvOS config sources and reconciliation after Omarchy defaults.
  core/        qvCORE two-stack catalog and lifecycle owners.
  desktop/     Shared context, web, and Hyprland desktop helpers.
  direct/      Verified manifest-driven direct software and updates.
  git/         Private git helper source and installers.
  install/     qvOS stages applied after Omarchy installation.
  iso/         ISO integration patches.
  menu/        qvOS menus and Elephant deltas installed through Omarchy seams.
  network/     qvOS DNS policy and optional WARP routing.
  power/       Sleep inhibition, guarded suspend, and opt-in battery protection.
  presentation/ qvOS terminal presentation and failure handling.
  screensaver/ Screensaver launchers and terminal profile.
  security/    Codex-operated security auditing and hardening workflow.
  share/       LocalSend request routing.
  shell/       qvOS shell additions.
  theme/       The Yaqyn qvOS theme overlay.
  thunar/      Thunar feature entry points.
  tmux/        Persistent tmux session manager.
  tui/         ISO installer, progress UI, and image build tooling.
  update/      qvOS update preflight and presentation wrapper.
  waybar/      qvOS prayer clock modules.
  windows/     Windows VM configuration, safe removal, and rollback.
```

qvCORE is an optional two-stack collection, not a qvOS subsystem. Its complete
catalog is Proton and qvDEV. Every stack exposes only Install and Uninstall.

## Product lifecycle

qvOS has one supported base: a solid, gaming-ready Arch system curated through
Omarchy. The base keeps Omarchy's on-demand OpenAI Codex wrapper plus software
with an independent qvOS, Omarchy, gaming, hardware, or desktop purpose.
The package resolver layers validated qvOS additions and exclusions over
Omarchy's original manifests; qvOS does not copy or replace those manifests.
Steam remains optional and uses Omarchy's standard gaming installer and
remover. qvCORE adds optional integrated stacks without changing qvOS
identity or base readiness.

- `omarchy qvos update` confirms the operation and verifies branch `OS`, then
  delegates once to the original `omarchy update` implementation. Omarchy owns
  snapshots, source and package updates, migrations, orphan cleanup, log
  analysis, and restarts. After Pacman/AUR, one direct-tool hook updates only
  already-installed manifest entries belonging to qvDEV and Proton. It never
  restores missing tools, installs stacks, authenticates
  accounts, changes integrations, or changes networking.
- The qvCORE menu shows the two stacks directly. Each row is Install when
  unenrolled and Uninstall when enrolled. Install converges only missing
  pieces, configures and verifies the stack, then records enrollment. The
  underlying removal owner deletes
  the complete enrolled stack and its qvOS integration while preserving
  personal files, browser profiles, credentials, authentication state,
  projects, and cloud data.
- Codex remains Omarchy-owned through its standard on-demand NPM installation.
  qvOS preserves that upstream step but does not replace or separately update
  Codex.
- qvDEV unifies developer and Codex workstation ownership. It owns
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
  ISO Build stages the qvOS source over Omarchy's `main` ISO for its matching
  `master` installer, adds the qvOS configurator and progress surfaces, and
  preserves Omarchy's disk-install and post-install orchestration.

Returning to upstream Omarchy is not an in-place qvOS lifecycle. It requires a
separate documented installation rather than a source, branch, or config reset.

`qv/security/` owns the Codex-operated Lynis audit, a small nonrestrictive
sysctl baseline, signed-package and localhost-first container defaults, the
temporary private-LAN development preview, and the balanced-hardening
workflow. Its reports contain private system inventory, stay outside Git under
the user's state directory, and never authorize automatic hardening.

`qv/thunar/actions.sh` is the preservation-safe owner for qvOS custom actions.
The base desktop installs its default helpers, including the LocalSend Share
action for Omarchy's base package, and preserves optional stack payloads
without reinstalling them. Proton and qvDEV install and remove their own
actions.

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
