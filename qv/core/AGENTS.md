# qvCORE Workflow

Read this file completely when changing the qvCORE catalog, stack lifecycle,
direct-tool updater, removal, migration, or menu integration.

`Settings > Software > qvCORE` exposes exactly six optional stacks: WARP,
Share, Proton, Brave, Media, and qvDEV. qvOS must remain complete and healthy
with none installed.

## Stack Contract

- Every stack has exactly two user actions: Install and Remove. Keep detection,
  convergence, and verification internal; do not expose status, health, repair,
  adopt, disable, group-install, or partial-app lifecycle routes.
- `catalog.tsv` is the stack source of truth. A successful Install writes
  `~/.local/state/qvos/qvcore/<stack>` only after all missing software,
  configuration, integrations, and verification complete.
- Install only missing pieces and safely reuse compatible installed software.
  Remove only an enrolled stack, remove its entire declared software and
  qvOS-owned integrations, and preserve personal files, browser profiles,
  credentials, authentication state, projects, and cloud data.
- Stack scripts own package preflight, confirmation, resumable removal, and
  final verification. Do not route qvCORE through personal-software ownership
  or coordinated removal machinery.
- qvDEV owns its Pacman/AUR manifest, all qvDEV direct tools, and Codex
  workbench integration. Codex itself is base-owned and must survive qvDEV
  removal. Wrangler, Convex, and Playwright stay project-local.
- Steam and the reviewed gaming runtime are not qvCORE. qvOS Recovery is a
  separate base subsystem and never grades, installs, or repairs qvCORE.

## Direct Tools

`qv/direct/manifest.tsv` is the only direct-tool update registry. Its manager
must use bounded downloads, authoritative checksums or release digests,
candidate verification, and atomic replacement.

The post-update runner executes after normal Pacman/AUR updates. It updates
only already-installed direct tools in the base, qvDEV, and Proton scopes,
skips absent tools, continues through independent failures, and returns
nonzero after reporting every failure. It must never install a stack, restore
a missing tool, authenticate an account, repair an integration, or change
networking. Do not add one updater per tool.

Verify catalog and manifest guards, affected stack Install/Remove tests, direct
updater tests, menu tests, Bash syntax, ShellCheck, Codex doctor checks, and the
full qvOS suite. Base-manifest changes additionally require ISO prepare-only
verification.
