# qvOS Installation And Package Workflow

Read this file completely when changing base packages, conditional hardware
packages, package installation, source reinstall, config reset, online install,
repair, ISO caching, or live package removal.

Fresh install and source reinstall must never delete an existing checkout.
Validate repository and ref inputs before privileged work, clone the official
`OS` branch into same-filesystem staging, verify it, and move it into place.
The canonical installed checkout is `~/.local/share/qvos`. Preserve exactly one
relative `~/.local/share/omarchy -> qvos` compatibility link until inherited
paths are fully retired; reject any other object at either path. The permanent
`source-root` owner validates the native checkout and creates only this missing
exact link. Concurrent reconciliation accepts only an atomic winner with the
same relative target and rejects every other object. The completed pre-release
checkout and copied-runtime relocation is retired; historical layouts are
preserved as conflicts, never adopted.
Never merge runtime payloads into the Git checkout.
Deploy direct, desktop, and Tmux helpers only from their exact `runtime-paths`
manifests through the shared atomic runtime publisher; source policy, checks,
inventories, and source-only owners must never leak into the runtime.
The desktop owner must resolve and export `QVOS_PATH` once before reading or
running any feature owner. Native install orchestration never propagates
`OMARCHY_PATH`; a stale compatibility environment must not select or mix
payloads from another source checkout.
Windows owners run from the installed source and have no duplicate runtime tree.
Their completed pre-release identity migration is retired. Desktop
reconciliation never scans or rewrites Windows user state, and active owners
accept only the native command and `qvos-windows` container identity.
Source reinstall may replace only the same installed commit, must preserve the
complete previous checkout in a uniquely named backup, and must roll back if
the final move fails. It never returns qvOS to upstream Omarchy.

Resolve and validate the complete native package manifest before changing
mirrors or invoking Pacman. A config reset copies from `$QVOS_PATH`, runs
the native theme configuration directly, and finishes through the shared
Hyprland reconciliation owner. Its Bash source comes only from
`qvcore/shell/files/bashrc`; the inherited top-level shell defaults are
retired.
Resolve package-provider files only through
`qvcore/packages/provider-files`. Installed and online qvOS use Stable; Edge and
RC are accepted only inside the reviewed ISO chroot. Provider source requires
signed Omarchy packages before the first repository synchronization.
Fresh install uses the signed standard Arch `linux` kernel. Never append an
unsigned hardware repository after provider validation. T2 Macs require an
unsigned third-party package set that qvOS does not manage, so both native and
fallback ISO preflight must refuse them before disk selection; keep their
repository, packages, kernel, graphics branch, and post-install fix absent.
The general pre-public config and obsolete-state convergence owners are retired
after the only supported installation reached native state. Fresh installation
and post-update reconciliation must not scan unrelated user trees or carry
historical Hyprland overlays, Nautilus extensions, logo fonts, maintenance
aliases, D-Bus services, or copied Thunar launchers. Each current feature owner
mutates only its explicit native paths and preserves foreign data.
The pre-release Services/Development structure migrator is also retired after
the only supported installation converged. Base reconciliation and optional
owners use only native enrollment and runtime paths; they never scan or recreate
the former `qvos/qvcore` state root or `qvdev-tools` runtime root.
Do not install a global GnuPG resolver policy or force system and user service
shutdown timeouts. The pre-public convergence code for those inherited files
is retired; fresh qvOS carries only the system defaults.
Fresh install marks only the current supported numeric owners from
`qvcore/migrations/` through `qvcore/migrations/run --mark-current`; an empty
compacted baseline is valid. It never executes existing-system migrations or
reads or records a retired Omarchy marker tree. This seeding runs before the
installed account has a login session and must not require `/run/user/$UID`.

The complete installer implementation lives under `qvcore/install/`, with
login leaves under `qvcore/boot/login/`. The top-level `install.sh` is the only
entry point. `QVOS_INSTALL` names the only stage root; `OMARCHY_INSTALL` is
retired. Native install owners resolve only `QVOS_PATH`, invoke native `qv-*`
helpers, and never select a source through inherited environment. Never restore
the retired top-level `install/` tree or route an install lifecycle through the
source-root compatibility link.

`qvcore/install/system-tuning` singularly owns the NOFILE and inotify defaults
under native `qvos` filenames. It installs tracked sources atomically, applies
only the owned sysctl file, preserves exact native files, and rejects modified,
linked, or unsafe native targets. Completed pre-release tuning convergence is
retired, so fresh installation does not inspect or mutate inherited filenames.
Fresh install never grants wheel-wide passwordless timezone commands; the
security owner retires that exact predecessor.

`qvcore/install/hardware/identity` singularly owns installed hardware policy
identity. Its ASUS Z13 and Apple NVMe stage adapters only select hardware; the
owner installs tracked native files, activates them, and rolls back only files
and service state created by the current attempt. Preserve an exact existing
native policy without replacing it, and reject modified, linked, or unsafe
native targets before activation. The completed pre-release hardware identity
migration is retired; fresh install never scans or mutates inherited rule,
unit, backup, or service names.

Installer-owned runtime identity is qvOS-native: use
`QVOS_INSTALL_LOG_FILE` at `/var/log/qvos-install.log`,
`QVOS_ONLINE_INSTALL`, `QVOS_PROVIDER_CHANNEL`, `QVOS_USER_NAME`,
`QVOS_USER_EMAIL`, `/var/tmp/qvos-install-completed`, and the exact
`99-qvos-installer` and `99-qvos-installer-reboot` temporary policies.
`QVOS_CHROOT_INSTALL=1` is the only native target-chroot signal; reject every
other non-empty value before invoking a stage. The ISO passes the credited
mirror channel and user metadata only through qvOS names; never accept
inherited environment names inside the installer. The finished owner removes the native temporary policy and its
exact legacy predecessor without extending either into persistent state. It
validates every candidate before one final removal so an unsafe predecessor or
interrupted cleanup cannot revoke the active installer authorization halfway.
The ISO gives Archinstall ownership of Gum as the target-side presentation
bootstrap, then executes the tracked native `install.sh` directly under the
installed account. Do not add a hidden pre-installer Pacman transaction or
source the entry point through a login shell.

`qvcore/install/post-install/run` singularly owns the ordered post-install stage.
Stop the install log before handing control to the finished presentation, and
keep both the ISO TUI finale and the non-ISO fallback in the qvOS finished
owner. Never restore inherited post-install orchestration or presentation as a
fallback. Its temporary reboot privilege is installed through the singular
`post-install/reboot-policy` owner. Validate the desktop account and complete
sudoers payload with `visudo`, preserve every modified or unsafe target, and
publish one root-owned policy atomically; never restore a direct sourced
sudoers writer.

`qvcore/install/config/run` singularly owns the ordered fresh-install configuration
stage. Every selected reviewed configuration and hardware leaf is now native;
keep its order explicit and call it through `run_logged`. The specialized qvOS
MIME and corrected ASUS B9406 owners replace their superseded upstream leaves.
The theme leaf translates the exact reviewed chroot signal into qvOS's offline
theme-rendering mode: install the complete theme state and safe file or hardware
integrations, but never probe a user bus, mutate GNOME settings, restart desktop
components, launch a wallpaper, or run user hooks before first login.
Its Branding leaf installs the singular root-owned qvOS `/etc/os-release`
through `qvcore/branding/system-identity` before reconciling private user
branding; never write a second product identity directly from the installer.
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
support. A caller may define `qvos_install_exit_cleanup` for an owner-specific,
idempotent final cleanup; its failure replaces only an otherwise successful
status and never hides the original installation failure. Online retry replaces
the failed installer process from the validated `QVOS_PATH`; signals stop
promptly with conventional exit codes. `run_logged` transports only the exact
stage path into its clean shell and clears positional parameters before sourcing;
an installer leaf must never observe the helper's path as its own `$1`.
Presentation must prefer inherited terminal descriptors and treat every size
probe as optional under strict error handling; an ISO target user may inherit
the live console while being unable to reopen `/dev/tty`. Environment logging
records identity inputs only as set or empty and never persists their values.
Clearing an unavailable terminal is cosmetic and must never turn a completed
installer stage into a failure.

`qvcore/install/first-run/prepare` creates the native marker only after it
installs and validates the root-owned helper and exact `apply`/`cleanup`
sudoers commands. `qvcore/install/first-run/run` owns the ordered login lifecycle,
keeps the marker on failure, serializes concurrent starts, and removes the
narrow privilege policy only after all required user-session work succeeds.
Never grant passwordless access to general system, firewall, package, or file
commands for first run. Keep notifications non-fatal after successful cleanup.
The tracked Hyprland autostart source invokes only the native `qv-first-run`
route; the Omarchy route is a metadata-free compatibility adapter.
The active marker and private lock live only under `.local/state/qvos/install`;
the retired inherited marker is not scanned or migrated.
The native GNOME and icon owners replace the inherited GNOME theme rather than
running after it.
Walker startup files are ordinary native sources under
`qvcore/config/files/`; the singular base config copy installs them. Provider
links, menu runtime, and service reloads
remain singularly owned by `qvcore/menu/install` during first run. Never
restore the duplicate `walker-elephant.sh` stage or a root Pacman hook that
executes a home-directory checkout.
The same menu owner seeds the personal extension at
`~/.config/qvos/extensions/menu.sh` only when absent and never scans an
inherited menu path. Existing native personal content remains user-owned.
Install Walker and only the official Elephant providers referenced by qvOS
configuration explicitly; never depend on `omarchy-walker` or restore its
unused Bluetooth, runner, todo, and Unicode providers. Install official Neovim
with the native minimal config seed and palette-generated theme; never restore
`omarchy-nvim`, its setup stage, LazyVim preload, or bundled theme catalog.
Before first-run services are enabled, run the native config toggle-state and
user-service reconcilers. The target chroot has no user manager: config, menu,
Thunar, and power owners use the shared manager probe to stage units without a
reload, and first run activates them after the desktop session exists. Battery
monitoring and internal-monitor recovery use
only `qvos-*` unit identities. Retired inherited unit names and toggle roots
remain absent and are not existing-system reconciliation inputs.
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
weather, idle, notification, and configuration owners never enter
`~/.local/lib/qvos/waybar`.
Install private About and screensaver customization only through
`qvcore/branding/install`; desktop reconciliation invokes it before the
screensaver runtime. Never copy top-level logo assets or write active
`.config/omarchy/branding` state from an install, reset, or update path.
Custom hooks are reconciled through `qvcore/hooks/reconcile` during desktop
installation. Never copy qvOS update jobs into the user-writable hook tree or
restore the retired delayed Voxtype prompt. Current reconciliation seeds only
missing native samples and never scans historical roots; optional software
remains an explicit menu action.

`qvcore/install/packaging/base.packages` is the singular installed base manifest.
Keep `rtkit` with the PipeWire desktop runtime so audio processes retain their
realtime scheduling path instead of silently falling back on every fresh boot.
Keep Tumbler's `libgepub`, `libgsf`, and `libopenraw` optional libraries with
the file-manager runtime: Tumbler ships and loads those EPUB, ODF, and RAW
plugins, so omitting their libraries creates loader faults instead of a slimmer
working thumbnail service.
`qvcore/install/packaging/other.packages` is the singular ISO inventory for
conditional hardware paths that remain verifiably signed.
It also caches the Limine integration packages and `inotify-tools` required by
the native boot owner; the owner installs that set only when Limine is present.
`qvcore/install/packaging/resolve` validates and emits them; never restore an
inherited manifest plus additions/exclusions model or an unsupported hardware
stack merely to preserve upstream coverage.
Provider-branded application and meta-packages are not qvOS base packages.
The credited repository/keyring may supply official upstream-named packages,
but qvOS owns their selection, configuration, theme, and lifecycle.
`qvcore/install/packaging/all.sh` calls the native qvOS fixed NPX-wrapper and
empty bundled Web App owners directly, and `qv refresh applications` uses
those same owners. Application refresh delegates the fixed desktop payload to
`qvcore/desktop/applications/install`; it never stages a second icon tree under
`~/.local/share/applications/icons`. The optional Foot launcher is owned by
`qvcore/software/foot.desktop` and is installed only when Foot is already
present; it never enters the fixed base inventory. The fixed wrapper owner may
replace only its current output
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
Treat user hicolor cache generation as a best-effort optimization: the fixed
payload does not own a complete local icon theme, so a missing local
`index.theme` must not abort fresh install or application refresh.
Keep Pi and GHUI in the singular fixed wrapper owner until their product
ownership changes deliberately. Never restore a generic package-to-command
generator or make application refresh download an npm package.
All native wrappers and install paths share Mise's `node@lts` contract. Online
installation selects LTS directly; the ISO resolves one official LTS archive,
verifies its published digest, and the Mise config leaf validates and stages it
atomically without following an existing runtime link. Create and trust
`~/Work/.mise.toml` only when it is the exact qvOS seed. Preserve every custom,
linked, or foreign Work config without trusting it automatically. The
pre-release inherited global Node channel migration is retired; there is no
second convergence mode beside the normal `mise use -g node@lts` selection.

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
