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
- `qvcore/packages/configure` owns an explicit reset to Stable. It backs up the
  current Pacman files, installs the credited provider configuration, invokes
  the existing security owner before synchronizing packages, and restores both
  files if configuration or hardening fails.
- Package signatures from `[omarchy]` are required while its unsigned database
  remains optional. `qvcore/security/install` owns that installed policy; never
  weaken global Arch trust or another repository to make Omarchy work.
- A provider outage, signing-key rotation, repository rename, package removal,
  or Stable/Edge compatibility change is qvsync review input. Keep the monitored
  upstream paths in `upstream/qvsync/package-provider-paths`; every match must be
  assessed before advancing the reviewed upstream SHA.
- AUR is optional and user-initiated. Required qvOS base capability must not
  silently move from the curated providers to an unreviewed AUR recipe.

Run `qvcore/packages/check`, Bash syntax, ShellCheck, the package, security,
source-lifecycle, qvsync, and full qvOS suites. Package upgrades and live channel
changes are never part of source-only verification.
