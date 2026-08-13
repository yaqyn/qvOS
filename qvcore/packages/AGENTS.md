# qvOS Package Provider Workflow

Read this file completely when changing Pacman repository configuration,
package signatures, Omarchy keyring handling, package channels, package
manifests, or qvsync package-infrastructure monitoring.

qvOS owns package selection, compatibility, update orchestration, and health
checks. Omarchy remains the credited provider of the Stable Arch mirror, the
`[omarchy]` curated package repository, and `omarchy-keyring`. Preserve those
truthful names and the published signing fingerprint; never introduce or imply
a qvOS mirror, binary repository, build farm, CDN, or package-signing key.
Native package owners resolve source only through `QVOS_PATH`; the provider
name never grants `OMARCHY_PATH` source authority.
`omarchy-keyring` is the only retained provider-branded package requirement.
Application and meta-package selection uses official upstream package names;
qvOS owns the corresponding config and theme instead of depending on
`omarchy-nvim`, `omarchy-walker`, or future provider-branded app bundles. The
one pre-release handoff to official packages is complete and its transition
code is retired; prevent those bundles from entering fresh manifests instead
of carrying a permanent removal path.

- Installed qvOS uses Omarchy Stable. Edge and RC configuration may exist only
  for reviewed ISO-builder compatibility; no installed channel switcher may
  move a user to them.
- Package availability in the credited repository does not make an alternate
  kernel qvOS-owned. Fresh and release inventories retain the signed standard
  Arch `linux` kernel and exclude `linux-ptl`, its headers, and hardware boot
  overrides.
- Credited provider files live under `qvcore/packages/provider/omarchy/` and
  require signed packages at source. `qvcore/packages/provider-files` is the
  only channel resolver; it accepts Edge or RC only in the reviewed ISO chroot
  and never interpolates unchecked environment input into a source path.
- `qvcore/install/packaging/` owns the singular qvOS package manifests and
  resolver. Package presence never implies qvOS, Service, or Development
  ownership. Keep provider-branded applications out of both manifests and
  list only the explicit official packages needed by an active qvOS owner.
- `qvcore/packages/{add,drop,missing,present}` owns package mutation and
  readback through configured repositories. AUR operations are separate,
  explicit owners. Validate package names before Pacman or Yay, terminate
  option parsing with `--`, preserve exact argument boundaries, and verify
  every requested installation from the local package database.
- Native package commands use `bin/qv-pkg-*` and `# qv:*` metadata. The command
  engine prefers each native route; matching `bin/omarchy-pkg-*` files are
  metadata-free compatibility adapters to the same owner, never a second
  implementation.
- Interactive package selection treats ordinary FZF cancellation as a clean
  no-op and uses arrays rather than `xargs`. Package actions never rebuild the
  host-wide locate database; the package-provided daily timer under qvOS's
  AC-only policy is its sole lifecycle owner. Do not hide repository-listing or
  package-manager failures as cancellation.
- Interactive Pacman and AUR selection source the bounded native
  `sudo-keepalive` helper, start it only after validated selection, and stop its
  exact child on every exit. Never restore a public or inherited keepalive
  command or let a package picker leave a credential-refresh process behind.
- `qvcore/packages/configure` owns an explicit reset to Stable. It backs up the
  current Pacman files, installs the credited provider configuration, invokes
  the existing security owner before synchronizing packages, and restores both
  files if configuration or hardening fails. `qv refresh pacman` owns public
  metadata; `omarchy-refresh-pacman` is a metadata-free compatibility adapter.
- Package signatures from `[omarchy]` are required while its unsigned database
  remains optional. Provider source and `qvcore/security/install` agree on that
  policy; never create a weak bootstrap interval or weaken global Arch trust or
  another repository to make Omarchy work.
- The release builder resolves those same provider files before its first
  Omarchy package, retains every detached package signature in the offline
  mirror, and uses `Required DatabaseOptional` for that mirror. Never accept
  `TrustAll`, `SigLevel = Never`, an unsigned hardware repository, or an
  unsigned cached package in a qvOS image. The ISO builder retains the exact
  online repository databases that resolved the signed package set. After
  Archinstall, publish those databases atomically alongside the temporary
  `offline` database so native package staging remains fully offline. Only
  after the installer selects the final provider configuration may it validate
  every online database and retire `offline`; a fresh target must not require a
  partial online sync for its first package action.
- A provider outage, signing-key rotation, repository rename, package removal,
  or Stable/Edge compatibility change is qvsync review input. Keep the monitored
  upstream paths in `upstream/qvsync/package-provider-paths`; every match must be
  assessed before advancing the reviewed upstream SHA.
- AUR is optional and user-initiated. Required qvOS base capability must not
  silently move from the curated providers to an unreviewed AUR recipe.
- `qvcore/packages/update-{keyring,system,aur}` and `remove-orphans` own package
  stages inside the native qvOS update transaction. The keyring stage may use
  one partial database refresh only to establish the credited provider and
  Arch keyrings immediately before the full `pacman -Syu`. Update AUR packages
  only when foreign packages exist and AUR is reachable. Remove all verified
  orphans in one argument-safe transaction and report failures honestly.
  The keyring stage requests sudo visibly before any quiet privileged probe;
  never hide an authentication prompt behind redirected key validation.
  Their inherited raw stage commands are retired, not compatibility APIs.
- `qvcore/packages/update-available` owns the non-mutating package probe used by
  the public update indicator. It synchronizes only a private user-owned cache,
  links the read-only installed package database, and never runs a partial sync
  against `/var/lib/pacman`. Bound its network time, serialize its cache, refuse
  an active Pacman transaction, and preserve the public availability exit-code
  contract: `0` available, `1` current, `2` unavailable or unsafe.

Run `qvcore/packages/check`, Bash syntax, ShellCheck, the package, security,
source-lifecycle, qvsync, and full qvOS suites. Package upgrades and live channel
changes are never part of source-only verification.
