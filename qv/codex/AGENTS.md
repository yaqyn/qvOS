# qvOS Codex Workflow

Read this file completely when changing the Codex capability contract, doctor,
runtime deployment, sandbox checks, or Workbench profile boundaries.

## Ownership

- `capabilities.tsv` is the source of truth for command ownership. Every entry
  has one layer (`base`, `qvcore`, `project`, or `avoid`), one profile, one
  owner, and an exact install or repair route.
- Base capabilities must be guaranteed by
  `qv/install/packaging/base.packages`. qvCORE capabilities delegate to their
  independently rerunnable component. Project tools stay version-pinned in the
  project; avoid entries must never leak into base or Devel.
- `doctor` is read-only and secret-safe. It may prove authentication by exit
  status with output suppressed, but never prints tokens, environment values,
  credential contents, or private configuration.

## Doctor Contract

1. Inspect the canonical `~/.local/bin/codex` standalone installation with
   stale parent-session package-manager provenance removed.
2. Prove the canonical Codex doctor and Linux sandbox, then inventory the
   capability registry without installing or repairing anything.
3. Report only boolean credential readiness, MCP and skill counts, unique
   command paths, session-storage totals, and exact missing-capability routes.
4. Optional profile absence never makes qvOS unhealthy. `--check` fails only
   for the guaranteed base, canonical Codex, or sandbox contract.
5. Keep Browser and Documents `planned` until a real owner, install route, and
   focused tests exist. Never imply a future profile is available.

Deploy `doctor` and `capabilities.tsv` together under
`~/.local/share/qvos/codex/`; the real `qv` front door must delegate to that
runtime so inspection survives source-tree damage. Verify source/runtime parity,
focused Codex tests, desktop install/status tests, the full qvOS suite, and the
live JSON report.
