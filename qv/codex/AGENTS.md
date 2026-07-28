# qvOS Codex Workflow

Read this file completely when changing the Codex base installer, capability
contract, doctor, runtime deployment, sandbox checks, or qvDEV boundary.

## Ownership

- Codex is guaranteed qvOS base software. `qv/codex/install` delegates to the
  shared verified direct-tool manager, fresh install runs it, and the direct
  updater updates an existing canonical standalone installation.
- `capabilities.tsv` is the source of truth for command ownership. Every entry
  has one layer (`base`, `qvcore`, `project`, or `avoid`), one profile, one
  owner, and an exact install route.
- Base capabilities must have an independent qvOS, inherited Omarchy, gaming,
  hardware, desktop, or Recovery purpose. qvDEV owns developer-specific
  Pacman/AUR packages, mise tools, verified direct tools, Semgrep, Dev
  Container CLI, and Codex workbench integration.
- System Python and mise are base-owned. qvDEV owns uv and its isolated
  Semgrep runtime but must not configure a global mise Python. Wrangler,
  Convex, and Playwright remain project-local.
- qvDEV removal must leave canonical Codex, `~/.codex`, projects, credentials,
  and personal files untouched.
- `doctor` is read-only and secret-safe. It may prove authentication by exit
  status with output suppressed, but never prints tokens, environment values,
  credential contents, or private configuration.

## Doctor Contract

1. Inspect canonical `~/.local/bin/codex` and require it to resolve under the
   OpenAI standalone package root.
2. Prove the canonical Codex doctor and Linux sandbox, then inventory the
   capability registry without installing or repairing anything.
3. Report only boolean credential readiness, MCP and skill counts, unique
   command paths, session-storage totals, and exact missing-capability routes.
4. Optional qvDEV absence never makes qvOS unhealthy. `--check` fails only for
   the guaranteed base, canonical Codex, or sandbox contract.
5. Keep Browser and Documents planned until a real owner, install route, and
   focused tests exist.

Deploy `doctor` and `capabilities.tsv` together under
`~/.local/share/qvos/codex/`; the real `qv` front door delegates to that runtime.
Verify source/runtime parity, focused Codex and direct-tool tests, desktop
install/status tests, the full qvOS suite, and the live JSON report.
