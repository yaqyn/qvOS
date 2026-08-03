# qvOS Installation And Package Workflow

Read this file completely when changing base packages, conditional hardware
packages, package installation, source reinstall, config reset, online install,
repair, ISO caching, or live package removal.

Fresh install and source reinstall must never delete an existing checkout.
Validate repository and ref inputs before privileged work, clone the official
`OS` branch into same-filesystem staging, verify it, and move it into place.
Source reinstall may replace only the same installed commit, must preserve the
complete previous checkout in a uniquely named backup, and must roll back if
the final move fails. It never returns qvOS to upstream Omarchy.

Resolve and validate the complete native package manifest before changing
mirrors or invoking Pacman. A config reset copies from `$OMARCHY_PATH`, runs
the native theme configuration directly, and finishes through the shared
Hyprland reconciliation owner.
Remove obsolete qvOS state only through `qv/install/cleanup-obsolete`, and only
when its former owner is absent and the installed payload is an exact known
qvOS artifact. Preserve symbolic links, modified files, and foreign data.

`qv/install/post-install/run` singularly owns the ordered post-install stage.
Stop the install log before handing control to the finished presentation, and
keep both the ISO TUI finale and the non-ISO fallback in the qvOS finished
owner. Never restore inherited post-install orchestration or presentation as a
fallback.

`qv/install/first-run/prepare` creates the compatibility marker only after it
installs and validates the root-owned helper and exact `apply`/`cleanup`
sudoers commands. `qv/install/first-run/run` owns the ordered login lifecycle,
keeps the marker on failure, serializes concurrent starts, and removes the
narrow privilege policy only after all required user-session work succeeds.
Never grant passwordless access to general system, firewall, package, or file
commands for first run. Keep notifications non-fatal after successful cleanup.
The native GNOME and icon owners replace the inherited GNOME theme rather than
running after it; retain `yaru-icon-theme` only for compatible external themes.

`qv/install/packaging/base.packages` is the singular installed base manifest.
`qv/install/packaging/other.packages` is the singular ISO inventory for
conditional hardware paths. `qv/install/packaging/resolve` validates and emits
them; never restore an inherited manifest plus additions/exclusions model.

- Keep qvOS complete without qvCORE. Stack packages stay in their qvCORE owner;
  base packages may provide only shared prerequisites such as `mise`.
- Preserve the reviewed gaming-ready runtime in the marked base section.
  Steam and hardware-specific graphics drivers remain optional owners.
- Treat upstream package changes as capability-review input. Adopt a package
  only with a named qvOS capability and one lifecycle owner.
- Before removing a package, trace command/config/service consumers, reverse
  dependencies, optional-stack ownership, user data, and live installation
  state. Present the exact source and live removal set for approval.
- Never remove a user-installed or qvCORE-owned package merely because it is
  outside the base manifest. Use `omarchy-pkg-drop` only after approval and
  verify the computed Pacman transaction before mutation.

Run `qv/install/check`; the resolver for `base`, `other`, and `all`; package,
first-run, source-lifecycle, product, security, and upstream-boundary tests;
Bash syntax and ShellCheck; and the full qvOS suite. Package-manifest changes
also require ISO prepare-only verification. Do not run package upgrades during
source or live parity work.
