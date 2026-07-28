# qvOS TUI Workflow

Read this file completely when changing `qv/tui/`, a qvOS TUI launch route,
the installed `qvos-tui` binary, or an action rendered inside the TUI. Also
read the owner workflow for any external surface being routed into the TUI,
such as `qv/menu/AGENTS.md` or `qv/iso/AGENTS.md`.

## Ownership

- `qv/tui/` owns the shared palette, responsive composition, 3D stage,
  confirmation, authorization, progress, logs, and result presentation.
- Put each action-specific contract and adapter under `qv/tui/<action>/`.
  Every direct mode and the main hub must reuse the same action flow.
- Keep mutation, recovery, package, and update behavior in its existing qvOS or
  Omarchy owner. TUI adapters delegate once and never reproduce an engine.
- Preserve plain CLI and TTY fallbacks. The TUI must not become a prerequisite
  for update or recovery, and ISO flows retain their inherited fallback.
- Treat progress as milestones, not elapsed-time prediction. Unknown output
  stays in logs and must not fabricate progress or overwrite the active stage.
- Complete confirmation and non-mutating preflight before sudo. Cancellation
  is safe before mutation; do not offer cancellation after a non-interruptible
  owner starts.

## Change Workflow

1. Read the action owner, its TUI adapter, every launch surface, and focused
   tests before editing.
2. Keep shared visual behavior at the TUI root and action-specific behavior in
   its owner directory. Keep package boundaries minimal and use an action
   package only for a real independently tested contract.
3. Preserve exit `0` for success, `130` for user cancellation, and nonzero for
   failures. Never render success after an owner failure.
4. Run `gofmt`, `go test -count=1 ./...`, Bash syntax and ShellCheck for shell
   adapters, focused action/menu tests, then `test/qvos/run.sh` when shared
   contracts or lifecycle wiring changes.
5. Build and install the live binary through `qv/tui/install`, apply affected
   launch/config owners, exercise the safe presentation path, then capture and
   inspect a fullscreen screenshot with
   `omarchy capture screenshot fullscreen save`.

When an ISO surface changes, follow `qv/iso/AGENTS.md` in addition to this
workflow and verify both boot fallback and the installed-system binary.
