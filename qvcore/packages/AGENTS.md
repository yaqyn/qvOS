# qvOS Package Provider Workflow

Read this file completely when changing Pacman repository configuration,
package signatures, Omarchy keyring handling, package channels, package
manifests, or qvsync package-infrastructure monitoring.

qvOS owns package selection, compatibility, update orchestration, and health
checks. Omarchy remains the credited provider of the Stable Arch mirror, the
`[omarchy]` curated package repository, and `omarchy-keyring`. Preserve those
truthful names and the published signing fingerprint; never introduce or imply
a qvOS mirror, binary repository, build farm, CDN, or package-signing key.

- Installed qvOS uses Omarchy Stable. Edge and RC configuration may exist only
  for reviewed ISO-builder compatibility; no installed channel switcher may
  move a user to them.
- `qvcore/install/packaging/` owns the singular qvOS package manifests and
  resolver. Package presence never implies qvOS, Service, or Development
  ownership.
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
  no-op, uses arrays rather than `xargs`, and refreshes the locate database only
  when its owner is installed. Do not hide repository-listing or package-manager
  failures as cancellation.
- `qvcore/packages/configure` owns an explicit reset to Stable. It backs up the
  current Pacman files, installs the credited provider configuration, invokes
  the existing security owner before synchronizing packages, and restores both
  files if configuration or hardening fails. `qv refresh pacman` owns public
  metadata; `omarchy-refresh-pacman` is a metadata-free compatibility adapter.
- Package signatures from `[omarchy]` are required while its unsigned database
  remains optional. `qvcore/security/install` owns that installed policy; never
  weaken global Arch trust or another repository to make Omarchy work.
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
  Their inherited raw stage commands are retired, not compatibility APIs.

Run `qvcore/packages/check`, Bash syntax, ShellCheck, the package, security,
source-lifecycle, qvsync, and full qvOS suites. Package upgrades and live channel
changes are never part of source-only verification.
