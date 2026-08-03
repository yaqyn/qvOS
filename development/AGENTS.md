# qvOS Development Workflow

Read this file completely when changing Devel, its package or direct-tool
inventory, Codex workbench integration, enrollment state, or Software routing.

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
- Wrangler, Convex, Playwright dependencies, and browser assets remain
  project-local. Devel owns only the official global Playwright CLI.
- Removal preserves projects, credentials, personal files, configuration, and
  base software. Do not infer enrollment from package presence.

Run Bash syntax, ShellCheck, the focused Devel, direct-tool, menu, TUI
owner-contract, product-contract, and full qvOS suites. Do not install or
remove the live workstation solely for source verification.
