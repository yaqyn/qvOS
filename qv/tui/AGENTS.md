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
- Complete confirmation and non-mutating preflight before sudo.
- Put runnable snapshots under the user runtime directory, never inside the
  Omarchy checkout, and stop active children when a TUI window exits.

## Durable UX Contract

- Launch desktop TUI windows through `qv/tui/launch`; the shared
  `org.qvos.tui` class owns the centered 1024x509 floating stage.
- Model roles are semantic: CORE (beating red/grayscale) is the hub identity,
  three rings is Update, two rings is every other operational terminal, and
  one ring is About only.
- About will present `Abdulrahman M. Yaqyn`, website, contact, and guides.
  Keep those values in its future owner contract rather than duplicating them.
- Important loading or mutation flows never bind `Ctrl+C` or `Ctrl+Z` directly
  to cancellation. Open a safe-default confirmation, keep unpausable work
  running until an explicit stop choice, then stop the full owned process
  group. Boot/ISO installation keeps its stricter interruption guard.
- Give logs responsive priority over the model and use the shared expanded
  panel. Canceled results must say canceled, never `100%` or success.
- Keep a visible bar with the percentage in non-mobile progress views. Use one
  quiet selection marker for choices; do not frame action labels as buttons.
- Every active keyboard action must be discoverable in a high-contrast
  persistent hint or the contextual help overlay at every responsive size.
  Use `?` outside text fields and `F1` everywhere so passwords and filters keep
  their full character set; labels must describe the current result, such as
  `v close logs`, rather than only the initial action.
- `Ctrl+V` on a log-producing flow opens the captured original command output
  inside the same TUI process. Never launch, attach, detach, or duplicate a
  mutating command to imitate a terminal view.

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
   launch/config owners, verify the semantic model and responsive log/result
   states, then capture and inspect a fullscreen screenshot with
   `omarchy capture screenshot fullscreen save`.

When an ISO surface changes, follow `qv/iso/AGENTS.md` in addition to this
workflow and verify both boot fallback and the installed-system binary.
