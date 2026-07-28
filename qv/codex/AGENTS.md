# qvOS Codex Workflow

Read this file completely when changing the Codex base installer, capability
contract, doctor, runtime deployment, sandbox checks, or qvDEV boundary.

## Ownership

- Codex is guaranteed qvOS base software. `qv/codex/install` delegates to the
  shared verified direct-tool manager, fresh install runs it, and the direct
  updater updates an existing canonical standalone installation.
- `capabilities.tsv` is the source of truth for command ownership. Every entry
  has one layer (`base`, `qvdev`, `project`, or `avoid`), one owner, and one
  exact action route.
- Base capabilities must have an independent qvOS, inherited Omarchy, gaming,
  hardware, or desktop purpose. qvDEV owns developer-specific
  Pacman/AUR packages, mise tools, verified direct tools, Semgrep, Dev
  Container CLI, and Codex workbench integration.
- System Python and mise are base-owned. qvDEV owns uv and its isolated
  Semgrep runtime but must not configure a global mise Python. Wrangler,
  Convex, Playwright dependencies, and Playwright browser assets remain
  project-local. qvDEV owns the official global Playwright CLI.
- qvDEV removal must leave canonical Codex, `~/.codex`, projects, credentials,
  and personal files untouched.
- `doctor` is read-only and secret-safe. It may prove authentication by exit
  status with output suppressed, but never prints tokens, environment values,
  credential contents, or private configuration.

## Doctor Contract

1. Inspect canonical `~/.local/bin/codex` and require it to resolve under the
   OpenAI standalone package root.
2. Prove the canonical Codex doctor and Linux sandbox, then inventory the
   capability registry without mutating anything.
3. Report only boolean credential readiness, MCP and skill counts, unique
   command paths, session-storage totals, and exact missing-capability routes.
4. Optional qvDEV absence never makes qvOS unhealthy. `--check` fails only for
   the guaranteed base, canonical Codex, or sandbox contract.

Deploy `doctor` and `capabilities.tsv` together under
`~/.local/share/qvos/codex/`; the real `qv` front door delegates to that runtime.
Verify source/runtime parity, focused Codex and direct-tool tests, desktop
install tests, the full qvOS suite, and the live JSON report.
