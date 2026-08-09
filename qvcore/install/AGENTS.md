# qvOS Installation And Package Workflow

Read this file completely when changing base packages, conditional hardware
packages, package installation, source reinstall, config reset, online install,
repair, ISO caching, or live package removal.

Fresh install and source reinstall must never delete an existing checkout.
Validate repository and ref inputs before privileged work, clone the official
`OS` branch into same-filesystem staging, verify it, and move it into place.
The canonical installed checkout is `~/.local/share/qvos`. Preserve exactly one
relative `~/.local/share/omarchy -> qvos` compatibility link until inherited
paths are fully retired; reject any other object at either path. Migrate the
old checkout atomically with `migrate-source-root` and roll back if link
creation fails.
Relocate the prior copied runtime tree atomically to `~/.local/lib/qvos` before
claiming the source root; never merge runtime payloads into the Git checkout.
Deploy desktop helpers only from `qvcore/desktop/runtime-paths`; source policy,
checks, inventories, and source-only owners must never leak into the runtime.
The desktop owner must resolve `QVOS_PATH` once, bind the inherited
`OMARCHY_PATH` alias to that exact checkout, and export both before reading or
running any feature owner. Never allow stale inherited environment to mix
payloads from two source checkouts.
Windows owners run from the installed source and have no duplicate runtime tree.
Desktop reconciliation invokes their absent-safe identity owner so validated
existing configuration converges on the native command and container without
recreating or discarding VM state; an unavailable Docker daemon safely defers
that existing-system migration.
Source reinstall may replace only the same installed commit, must preserve the
complete previous checkout in a uniquely named backup, and must roll back if
the final move fails. It never returns qvOS to upstream Omarchy.

Resolve and validate the complete native package manifest before changing
mirrors or invoking Pacman. A config reset copies from `$QVOS_PATH`, runs
the native theme configuration directly, and finishes through the shared
Hyprland reconciliation owner. Its Bash source comes only from
`qvcore/shell/files/bashrc`; the inherited top-level shell defaults are
retired.
Remove obsolete qvOS state only through `qvcore/install/cleanup-obsolete`, and only
when its former owner is absent and the installed payload is an exact known
qvOS artifact. Preserve symbolic links, modified files, and foreign data.
Retired Nautilus extensions are removed only when their source hash matches the
known inherited payload; remove their matching bytecode only in that same
verified cleanup and leave every modified or unrelated extension intact.
Fresh install seeds only numeric owners from `qvcore/migrations/` through
`qvcore/migrations/run --mark-current`; it never executes existing-system
migrations or records the retired Omarchy marker tree.

The complete installer implementation lives under `qvcore/install/`, with
login leaves under `qvcore/boot/login/`. The top-level `install.sh` is the only
entry point. `QVOS_INSTALL` names the native stage root; `OMARCHY_INSTALL` may
mirror it only as an upstream helper compatibility environment. Never restore
the retired top-level `install/` tree or route an install lifecycle through the
source-root compatibility link.

Installer-owned runtime identity is qvOS-native: use
`QVOS_INSTALL_LOG_FILE` at `/var/log/qvos-install.log`,
`QVOS_ONLINE_INSTALL`, `/var/tmp/qvos-install-completed`, and the exact
`99-qvos-installer-reboot` temporary policy. The reviewed ISO builder's
`OMARCHY_CHROOT_INSTALL` and temporary `99-omarchy-installer` policy remain
upstream compatibility inputs only; consume or remove them at that boundary
without extending their names into qvOS-owned state.

`qvcore/install/post-install/run` singularly owns the ordered post-install stage.
Stop the install log before handing control to the finished presentation, and
keep both the ISO TUI finale and the non-ISO fallback in the qvOS finished
owner. Never restore inherited post-install orchestration or presentation as a
fallback.

`qvcore/install/config/run` singularly owns the ordered fresh-install configuration
stage. Every selected reviewed configuration and hardware leaf is now native;
keep its order explicit and call it through `run_logged`. The specialized qvOS
MIME and corrected ASUS B9406 owners replace their superseded upstream leaves.
Thunar is the singular file manager; omit the inherited Nautilus package,
extension, context-menu, and Yaru action-icon setup instead of preserving a
guarded dead installer path. The inherited `default/nautilus-python/` source
is retired with that lifecycle and must remain absent. Keep `yaru-icon-theme`
only for compatible external themes.
Never restore `install/config/`, a second stage overlay, or an inherited
fallback.

The login stage is owned by `qvcore/boot/install`; keep `install.sh` wired directly
to it and never restore inherited login orchestration. Boot payload, private
ESP, SDDM, Plymouth, and snapshot rules live in `qvcore/boot/AGENTS.md`.

qvcore/install/helpers/run singularly owns the native chroot, presentation,
error, and logging helper order. The error handler
must preserve the original failure status, bound output on small terminals,
hide command arguments, never upload private logs, and point only to qvOS
support. Online retry replaces the failed installer process from the validated
OMARCHY_PATH; signals stop promptly with conventional exit codes.

`qvcore/install/first-run/prepare` creates the compatibility marker only after it
installs and validates the root-owned helper and exact `apply`/`cleanup`
sudoers commands. `qvcore/install/first-run/run` owns the ordered login lifecycle,
keeps the marker on failure, serializes concurrent starts, and removes the
narrow privilege policy only after all required user-session work succeeds.
Never grant passwordless access to general system, firewall, package, or file
commands for first run. Keep notifications non-fatal after successful cleanup.
The tracked Hyprland autostart source invokes only the native `qv-first-run`
route; the Omarchy route is a metadata-free compatibility adapter.
The active marker lives under `.local/state/qvos/install`; migrate the former
`.local/state/omarchy/first-run.mode` only after validating its type, owner, and
parents, and never leave both markers active.
The native GNOME and icon owners replace the inherited GNOME theme rather than
running after it.
Walker startup files are ordinary native sources under
`qvcore/config/files/`; the singular base config copy installs them. Provider
links, menu runtime, and service reloads
remain singularly owned by `qvcore/menu/install` during first run. Never
restore the duplicate `walker-elephant.sh` stage or a root Pacman hook that
executes a home-directory checkout.
Before first-run services are enabled, run the native config toggle-state and
user-service reconcilers. Battery monitoring and internal-monitor recovery use
only `qvos-*` unit identities; inherited unit names and toggle roots are
existing-system migration inputs, never fresh state.
AC-event rules must execute only root-owned helpers under `/usr/lib/qvos`.
Install or update those helpers through their qvOS owner before atomically
replacing a known udev rule; never embed a home, source-checkout, or
compatibility-link command in a root event.
DNS policy likewise mutates only through the root-owned
`/usr/lib/qvos/network/dns-policy` helper. Desktop reconciliation installs its
exact source before any user can select a provider; fresh installation never
chooses, changes, or activates a DNS provider automatically.
Waybar runtime reconciliation installs only the clock and prayer modules from
`qvcore/waybar/runtime-paths`; source policy, checks, refresh owners, hooks, and
configuration overlays never enter `~/.local/lib/qvos/waybar`.
Install private About and screensaver customization only through
`qvcore/branding/install`; desktop reconciliation invokes it before the
screensaver runtime. Never copy top-level logo assets or write active
`.config/omarchy/branding` state from an install, reset, or update path.
Custom hooks are reconciled through `qvcore/hooks/reconcile` during desktop
installation. Never copy qvOS update jobs into the user-writable hook tree or
restore the retired delayed Voxtype prompt; optional software remains an
explicit menu action.

`qvcore/install/packaging/base.packages` is the singular installed base manifest.
`qvcore/install/packaging/other.packages` is the singular ISO inventory for
conditional hardware paths. `qvcore/install/packaging/resolve` validates and emits
them; never restore an inherited manifest plus additions/exclusions model.
`qvcore/install/packaging/all.sh` calls the native qvOS fixed NPX-wrapper and
empty bundled Web App owners directly, and `qv refresh applications` uses
those same owners. Application refresh delegates the fixed desktop payload to
`qvcore/desktop/applications/install`; it never stages a second icon tree under
`~/.local/share/applications/icons`. The fixed wrapper owner may replace only its current output
or the exact retired generated Pi/GHUI wrappers; it preserves links, modified
files, and foreign commands. Codex is base-owned through the signed Arch
package and must never be written through a user command path.
Custom Web App lifecycle belongs to `qvcore/desktop/webapp`; never restore an
inherited implementation or a bundled desktop launcher. Do not preinstall
arbitrary-command terminal desktop wrappers: command-line tools such as `dust`
and `lazydocker` remain directly accessible without a second launcher
lifecycle. Keep only icons with a current native desktop or Windows owner.
The Windows icon stays with `qvcore/windows/`; the fixed desktop owner installs
only imv into the hicolor application theme. Retire Typora desktop, theme, and
window-rule seeds instead of preinstalling an unowned optional application.
Keep Pi and GHUI in the singular fixed wrapper owner until their product
ownership changes deliberately. Never restore a generic package-to-command
generator or make application refresh download an npm package.

- qvCORE is the mandatory qvOS implementation. Keep qvOS complete without
  optional Services or Development integrations. Their packages stay in their
  domain owner; base packages may provide only shared prerequisites such as
  `mise`.
- Preserve the reviewed gaming-ready runtime in the marked base section.
  Gaming applications and hardware-specific graphics drivers remain optional
  owners under `qvcore/gaming/`.
- Treat upstream package changes as capability-review input. Adopt a package
  only with a named qvOS capability and one lifecycle owner.
- Before removing a package, trace command/config/service consumers, reverse
  dependencies, optional-integration ownership, user data, and live installation
  state. Present the exact source and live removal set for approval.
- Never remove a user-installed, Service-owned, or Development-owned package
  merely because it is outside the base manifest. Use `qv pkg drop` only after
  approval and verify the computed Pacman transaction before mutation; the
  inherited package command is a compatibility adapter, not an owner route.

Run `qvcore/install/check`; the resolver for `base`, `other`, and `all`; package,
first-run, source-lifecycle, product, security, and upstream-boundary tests;
Bash syntax and ShellCheck; and the full qvOS suite. Package-manifest changes
also require ISO prepare-only verification. Do not run package upgrades during
source or live parity work.
