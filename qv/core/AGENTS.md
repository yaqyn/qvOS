# qvCORE Workflow

Read this file completely when changing the qvCORE catalog, component lifecycle,
health, removal, post-update maintenance, or menu integration.

`Settings > Software > qvCORE` is the opt-in profile for qvOS-integrated daily
software. qvOS must remain complete, healthy, and usable with no qvCORE
component installed.

- Keep new integrations out of base install and package lists unless explicitly
  promoted to the base system.
- The reviewed gaming runtime is explicitly promoted to
  `qv/install/packaging/base.packages`. Steam is not a qvCORE component; use
  Omarchy's standard Steam install and removal commands.
- Reuse an existing `omarchy-install-*` or `omarchy-setup-*` owner. Add
  `qv/core/<component>.sh` only when qvOS must own persistent integration.
- Ordinary apps remain personal software. Only managed setups participate in
  qvCORE status, repair, adopt, disable, and post-update maintenance.
- A persistent owner must be independently rerunnable for installation,
  `--status`, `--repair`, `--adopt`, `--disable`, removal cleanup, and
  post-update repair where those lifecycle states apply.
- Menus, Thunar actions, desktop adapters, and hooks are thin delegates to the
  same owner. Optional dependencies must never weaken the base system.
- Catalog changes require an explicit curation decision, installer route,
  personal-software ownership, health inventory, removal behavior, and focused
  integration tests.
- Healthy output stays quiet. Report actionable drift only for enabled or
  explicitly adopted managed setups; package presence alone is not ownership.

Verify the affected component independently, then run its focused tests,
`test/qvos/qvcore-health-test.sh`, personal-software coverage when removal
changes, post-update coverage when maintenance changes, and the full qvOS suite
for shared contracts. Gaming-base changes additionally run
`test/qvos/qvos-gaming-base-test.sh` and prove Steam has no qvCORE catalog,
health, removal, or menu route.
