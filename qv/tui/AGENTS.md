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
- Domain packages provide only copy, truthful milestones, preflight,
  verification, and delegation. They never import Bubble Tea or Lip Gloss,
  choose breakpoints, or render a parallel screen. Map their needs into the
  root-owned flow requirements and shared renderers.
- Keep reusable flow configuration and composition in focused root files such
  as `flow.go`, `authorization.go`, `progress.go`, `logs.go`, and
  `accessibility.go`; keep cell-aware shared text fitting in `text.go`. A
  shared TUI improvement or bug fix must land there and cover at least two
  consuming flows in its regression test.
- Keep mutation, package, and update behavior in its existing qvOS or Omarchy
  owner. TUI adapters delegate once and never reproduce an engine.
- Preserve plain CLI and TTY fallbacks. The TUI must not become a prerequisite
  for update, and ISO flows retain their inherited fallback.
- Treat progress as milestones, not elapsed-time prediction. Unknown output
  stays in logs and must not fabricate progress or overwrite the active stage.
- Never stack a start confirmation in front of sudo authorization. Information
  actions open directly; privileged transactions complete non-mutating
  preflight and proceed to authorization; only consequential unprivileged
  transactions use a start confirmation.
- Put runnable snapshots under the user runtime directory, never inside the
  Omarchy checkout, and stop active children when a TUI window exits.

## Durable UX Contract

- Launch desktop TUI windows through `qv/tui/launch`; the shared
  `org.qvos.tui` class owns the centered 1024x509 floating stage.
- Model roles are semantic: CORE (beating red/grayscale) is the hub identity,
  three rings are system-critical or high-impact operations, two rings are
  simple Software installs/removals, and one ring is an ordinary safe task or
  About. ISO build/install remains system-critical.
- One-ring actions are information surfaces, not miniature transactions. Start
  them immediately, authorize first only when sudo is required, and make their
  sanitized owner output the primary panel. Never add confirmation, synthetic
  progress, percentages, success ceremony, or a hidden log step. When an owner
  succeeds without output, show one truthful completion line. Present
  `Label: value` output as compact structured rows with dim uppercase labels,
  one widest-label column, and bold white primary values. Compact summaries
  use a middle-dot separator; multi-field reports use a normal dash, keep
  continuations aligned under the value column, and reserve red for priority
  thresholds such as percentages. Explanatory sentences remain prose after
  the structured rows rather than becoming fake status fields. Center grids,
  collection section markers, and prose independently under the title so a
  long note cannot pull a shorter grid sideways. Omit redundant single-member
  collection headings; multiple members use centered `<Name N>` markers. Do
  not dump, split, or clip values.
  When successful owner output is only a vague activity line, use an optional
  fixed-slug presenter under `task/presenters/` to delegate once, preserve
  exact failures, and emit verified readback. Presenters never own or repeat
  mutation.
- Keep fixed desktop task classification in `qv/tui/task/actions.psv`.
  Stream-safe tasks use `task/launch` and `task/run`; owners with prompts,
  authentication, hardware interaction, secret entry, selection, or reboot
  choices stay `native` until a dedicated contract preserves that interaction.
  A task changes tiers only with its risk or interaction contract.
- Configuration refreshes overwrite user state and are always three-ring
  actions. Unprivileged refreshes require start confirmation; privileged
  refreshes proceed from preflight to sudo without a duplicate gate. Never
  classify a reset as a one-ring information surface.
- Keep every fixed task, paired Software operation, and install-only leaf in
  `owner-contracts.psv`, including native handoffs and explicitly classified
  external owners. The manifest fingerprints repository entrypoints and their
  static qvOS dependencies recursively. Never refresh it mechanically after
  owner drift. Declare a dependency assembled from relative or dynamic paths
  with `# qvos:contract=qv/<path>` in its nearest contracted owner; directory
  declarations include every regular payload file. After drift, inspect the
  complete owner change, confirm presentation, sudo, interaction, output, and
  verification remain truthful, adapt the TUI contract when needed, then run
  `qv/tui/owner-contracts --write` and review the exact manifest diff.
- About will present `Abdulrahman M. Yaqyn`, website, contact, and guides.
  Keep those values in its future owner contract rather than duplicating them.
- Keep the production hub catalog limited to working actions. Give every row a
  stable action key and route activation by that key, never by tab or cursor
  coordinates. Add a section only with its first complete vertical slice.
- State-aware Install and Uninstall labels come from `qv/menu/software-state`
  using real qvOS or Omarchy state. `qv/tui/action/launch` refreshes state at
  activation and `qv/tui/action/run` delegates the selected mutation once; the
  TUI does not copy package or lifecycle logic.
- Install-only selectors keep their inherited browse shape and use
  `software-installers.psv` to classify every leaf as `tui` or `native`.
  Stream-safe leaves use the same action flow and verify their declared probe;
  never invent an Uninstall owner merely to flatten a selector.
- Route a software owner through `--action` only when it is safe to consume as
  a captured command stream. Keep owners that require interactive prompts,
  authentication, or configuration in their native terminal until they expose
  a noninteractive contract; never fake input inside the TUI.
- Route a non-Software script through the same `--action` presentation only
  from its fixed task-catalog row. Never accept an arbitrary command from a
  menu or environment variable, and never treat a native catalog row as
  capturable merely because it currently exits successfully.
- Keep `--prototype` as the Codex design and interaction harness. Its simulated
  actions are intentionally separate from the production catalog and do not
  establish product availability.
- Important two- or three-ring loading and mutation flows never bind `Ctrl+C`
  or `Ctrl+Z` directly
  to cancellation. Open a safe-default confirmation, keep unpausable work
  running until an explicit stop choice, then stop the full owned process
  group. One-ring information commands cancel directly. Boot/ISO installation
  keeps its stricter interruption guard.
- Give logs responsive priority over the model and use the shared expanded
  panel. Canceled results must say canceled, never `100%` or success.
- Keep the active operation, real milestone, percentage, and a visible bar in
  non-mobile progress views. Use one quiet selection marker for choices; do not
  frame action labels as buttons.
- The smallest progress view may omit the bar, but it must keep the active
  operation, static dimmed dot, and percentage centered as one stable line.
  On completion, keep the semantic result such as `UPDATED` or `INSTALLED`
  instead of replacing it with `100%` or a generic `DONE`.
- Keep persistent controls to one context-critical action plus quiet dim-gray
  Help when the hint area has room. Compact hint areas show only the primary
  action. Label Help consistently as `F1`; also accept `Shift+?` outside text
  fields so passwords and filters keep their full character set. Put every other
  active keyboard action in the contextual help overlay. Labels describe the
  action result, not implementation details.
- Authorization surfaces use the shared frameless, left-origin password rail
  and one blank row between the title and field. The mask never shifts while
  typing. Do not add a cursor, side brackets, or an input box.
- `Ctrl+V` on a log-producing flow opens the captured original command output
  inside the same TUI process. Never launch, attach, detach, or duplicate a
  mutating command to imitate a terminal view. An open side log may show one
  borderless, non-red `ctrl+v switch` cue directly below its panel; the full
  terminal view renders the same action as a normal persistent control.
- Normalize ANSI redraws, carriage returns, backspaces, tabs, and other control
  characters before rendering captured output so child processes cannot move
  the TUI cursor or break panel geometry. Log views follow the newest output by
  default and support line, page, oldest, and newest navigation. Disable
  application mouse capture only in full terminal output so normal terminal
  selection and copy work there. Native selection covers rendered cells, not
  internally scrolled history; provide `y` to copy the full captured log.
  Logs remain read-only and never execute pasted content.

## Change Workflow

1. Read the action owner, its TUI adapter, every launch surface, and focused
   tests before editing.
2. Keep shared visual behavior and capability configuration at the TUI root
   and action-specific data or delegation in its owner directory. Keep package
   boundaries minimal and use an action package only for a real independently
   tested contract. The ownership test must continue rejecting presentation
   imports from domain packages.
3. Preserve exit `0` for success, `130` for user cancellation, and nonzero for
   failures. Never render success after an owner failure.
4. Run `qv/tui/owner-contracts --check`; if it reports drift, review the owner
   before deliberately refreshing the manifest. Then run `gofmt`,
   `go test -count=1 ./...`, Bash syntax and ShellCheck for shell adapters,
   focused action/menu tests, and `test/qvos/run.sh` when shared contracts or
   lifecycle wiring changes.
5. Build and install the live binary through `qv/tui/install`, apply affected
   launch/config owners, verify the semantic model and responsive log/result
   states, then capture and inspect a fullscreen screenshot with
   `omarchy capture screenshot fullscreen save`.

When an ISO surface changes, follow `qv/iso/AGENTS.md` in addition to this
workflow and verify both boot fallback and the installed-system binary.
