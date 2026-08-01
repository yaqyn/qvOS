# qvCORE Workflow

Read this file completely when changing the qvCORE catalog, stack lifecycle,
direct-tool updater, removal, migration, or menu integration.

`Settings > Software > qvCORE` exposes exactly two optional stacks: Proton and
qvDEV. qvOS must remain complete and healthy with neither installed.

## Stack Contract

- Every stack has exactly two user actions: Install and Uninstall. The
  underlying command remains the stack removal owner. Keep detection,
  convergence, and verification internal; do not expose status, health,
  repair, adopt, disable, group-install, or partial-app lifecycle routes.
- `catalog.tsv` is the stack source of truth. A successful Install writes
  `~/.local/state/qvos/qvcore/<stack>` only after all missing software,
  configuration, integrations, and verification complete.
- Install only missing pieces and safely reuse compatible installed software.
  Remove only an enrolled stack, remove its entire declared software and
  qvOS-owned integrations, and preserve personal files, browser profiles,
  credentials, authentication state, projects, and cloud data.
- Proton Pass readiness probes can create `pass-cli.db` without an authenticated
  `session.json`. Treat only that exact database-only state as disposable probe
  cache; preserve and stop on every other unverified Pass file.
- Replacing an unverified isolated Codex Pass session requires explicit user
  confirmation and a temporary full-access login. Revoke at most one exact
  qvOS Codex-named PAT, refuse ambiguous matches, clear the local session only
  through `logout --force`, then recreate viewer-only `Codex Vault` access.
- Proton Pass PAT creation returns the token in the JSON `env_var` field. Accept
  both the current raw `pst_...::...` value and the older environment-assignment
  form, validate it without printing it, and keep it only in process memory.
- Verify Pass sessions with `info --output json` plus the narrow scoped
  `vault list --output json`; current Pass CLI releases no longer expose the
  former `test` command.
- Stack scripts own package preflight, confirmation, resumable removal, and
  final verification. Do not add a coordinated cross-stack removal layer.
- qvDEV owns its Pacman/AUR manifest, all qvDEV direct tools, and Codex
  workbench integration. Codex itself remains Omarchy-owned through its
  on-demand NPM installation and must survive qvDEV removal. Wrangler, Convex,
  Playwright dependencies, and Playwright browser assets stay project-local.
  qvDEV owns the official global Playwright CLI.
- qvDEV Install is convergent and never short-circuits on enrollment state.
  Check every manifest entry, reuse each compatible managed installation,
  install only missing entries, reconcile the workbench integration, then
  verify the complete stack.
- Steam and the reviewed gaming runtime are not qvCORE.
- Browsers already owned by Omarchy, including Brave Origin, stay on
  Omarchy's native install and removal owners and out of qvCORE.
- Software guaranteed by Omarchy, including LocalSend, stays base-owned and
  out of qvCORE. qvOS-only desktop adapters for it belong to their base feature
  owner and must never uninstall the inherited package.
- WARP belongs exclusively to the DNS selector. That owner may install and
  configure WARP when selected, but it must not write qvCORE enrollment state.
- Curated application bundles such as the retired Media stack do not belong in
  qvCORE. Removing bundle ownership must preserve already-installed packages
  and their settings, projects, and personal files.

## Direct Tools

`qv/direct/manifest.tsv` is the only direct-tool update registry. Its manager
must use bounded downloads, authoritative checksums or release digests,
candidate verification, and atomic replacement.

The post-update runner executes after normal Pacman/AUR updates. It updates
only already-installed direct tools in the qvDEV and Proton scopes,
skips absent tools, continues through independent failures, and returns
nonzero after reporting every failure. It must never install a stack, restore
a missing tool, authenticate an account, repair an integration, or change
networking. Do not add one updater per tool. Update Proton Pass from its
official release manifest without running the credential-aware CLI, and keep
all qvOS Pass sessions on the persistent D-Bus keyring backend.

Verify catalog and manifest guards, affected stack Install/Uninstall tests,
direct updater tests, menu tests, Bash syntax, ShellCheck, and the full qvOS
suite. Base-manifest changes additionally require ISO prepare-only
verification. Desktop launchers must call `~/.local/bin/codex` explicitly so
they use Omarchy's installed wrapper.
