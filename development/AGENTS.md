# qvOS Development Workflow

Read this file completely when changing Devel, local development services,
their package or direct-tool inventory, Codex workbench integration, enrollment
or credential state, containers, or Software routing.

`development/devel/` owns the optional Devel workstation formerly named
qvDEV. Devel appears under Development and is not part of an optional qvCORE
bundle. qvOS and qvCORE remain complete without it.

- Devel exposes exactly Install and Uninstall through
  `development/devel/manage`. Install converges every declared package,
  direct tool, and integration before recording enrollment.
- Base refresh may call the internal `reconcile` action only for an enrolled
  Devel workstation. It may refresh the qvOS-owned workbench integration, but
  must never install or remove packages or direct tools.
- Write enrollment only after verification to
  `~/.local/state/qvos/development/devel`. Migrate the exact former
  `qvos/qvcore/qvdev` marker and managed-tool root atomically; reject links,
  foreign ownership, malformed parents, and conflicting new state. Keep the
  category private at `0700` and its empty enrollment marker at `0600`.
- Devel owns its package manifest, `devel` direct-tool scope, and Codex
  workbench integration. Codex itself remains base-owned and must survive
  Devel removal.
- Devel resolves packages and commands only through native `qv-pkg-*` and
  `qv-cmd-*` helpers. Compatibility command names are external ABI, never an
  internal dependency.
- Wrangler, Convex, Playwright dependencies, and browser assets remain
  project-local. Devel owns only the official global Playwright CLI.
- Removal preserves projects, credentials, personal files, configuration, and
  base software. Do not infer enrollment from package presence.

`development/docker-dbs/` owns opt-in local database containers. Offer one
database per invocation, bind every published port to `127.0.0.1`, use unique
qvOS names and labels, generate strong credentials into owner-only state under
`~/.local/state/qvos/development/docker-dbs`, and retain persistent data across
reruns. Never adopt unlabeled containers or volumes, print a credential, put a
secret in Docker command arguments, restore empty/trust/default passwords, or
describe these containers as production deployments. Redis uses a private
owner-validated configuration and runs as the desktop UID so neither its data
nor password needs public permissions.

`development/environments/` owns the optional language and framework
installers. Its manifest is the single supported inventory; public `qv`
commands and metadata-free Omarchy adapters delegate to one manager.

- Record enrollment only after every declared component verifies. Keep exact
  private markers and the shared qvOS-created component registry under
  `~/.local/state/qvos/development/environments`; serialize all changes.
- Install runtimes through Mise and packages through qvOS package helpers.
  Never pipe remote scripts into a shell, edit global PHP configuration,
  overwrite shell startup files, or infer qvOS ownership from presence.
- Removal may touch only registry-owned components no longer required by
  another enrolled environment, the base, or enrolled Devel. Preserve
  projects, configuration, caches, pre-existing tools, modified command paths,
  and the qvOS OPAM switch; never recursively delete a language home.
- Record new ownership before mutation and retain a private transaction until
  verification. A failure or retry cleans only that transaction. Keep the
  declared dependency order for install and reverse it for removal.
- Captured menu actions use enrollment-state probes. Request sudo only for
  environments that can add or remove system packages; Mise-only lifecycles
  remain unprivileged.

Run the focused environment suite for language lifecycle changes and
`development/docker-dbs/check` when its owner changes, then Bash syntax,
ShellCheck, the focused Devel, Docker DB, direct-tool, menu, TUI owner-contract,
product-contract, upstream-overlay, and full qvOS suites. Do not install or
remove a live environment or workstation, or start a live database, solely for
source verification.
