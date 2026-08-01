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
- Never copy a renderer, geometry rule, key handler, state transition, output
  transform, or lifecycle branch between TUI models. Reuse its existing shared
  owner; when a second consumer appears, extract the behavior in the same
  change and remove both local implementations. Thin model adapters carry only
  model-specific state and copy.
- Keep mutation, package, and update behavior in its existing qvOS or Omarchy
  owner. TUI adapters delegate once and never reproduce an engine.
- Preserve plain CLI and TTY fallbacks. The TUI must not become a prerequisite
  for update, and ISO flows retain their inherited fallback.
- Treat progress as milestones, not elapsed-time prediction. Unknown output
  stays in logs and must not fabricate progress or overwrite the active stage.
- Success guidance names the stable destination or next action, never a key
  binding; bindings change independently from the completed lifecycle.
- Use exactly one start gate: information runs directly, privileged actions
  complete non-mutating preflight and proceed to sudo, and consequential
  unprivileged actions use an Action/Cancel confirmation.
- Render every short transition before sudo or the first owned milestone as
  the shared `Preparing`/`Preparing.`/`Preparing..`/`Preparing...` animation;
  never flash internal preflight, authorization, or startup status text.
- Put runnable snapshots under the user runtime directory, never inside the
  Omarchy checkout, and stop active children when a TUI window exits.
- Install the binary, launchers, action/task/update adapters, task catalogs,
  presenters, and success guidance as one checked payload under
  `~/.local/share/qvos/tui`. Every desktop launch route uses that payload;
  runtime adapters may resolve delegated owners from `OMARCHY_PATH`, but never
  mix a current binary with presentation or cancellation adapters from the
  live Omarchy checkout.

## Durable UX Contract

### Lifecycle screen matrix

Before changing or routing a TUI, derive its complete state matrix from owners.
Treat availability, active/default/applied state, behavior, and privilege as
independent facts; never infer one from another.

For a TUI-managed installable or defaultable lifecycle, Walker and shell menus
are navigation only: show the concept or program name and pass its identity to
the checked TUI. Never render or preselect lifecycle state or
Install/Uninstall/Apply/Default choices in a menu; the TUI owns every probe,
status, choice, start gate, action, and result.

- Read-only information runs directly. One-shot mutations keep their normal
  start gate and never gain invented lifecycle states.
- Ordinary installable software shows Install when absent and Uninstall when
  present only when an exact removal owner exists. Never offer Install twice or
  invent Apply, Default, or Uninstall from package presence.
- A managed choice such as a font, terminal, browser, editor, theme, or other
  default shows Install when absent; when present but inactive it offers
  Apply/Make Default and exact Uninstall when supported; when active it shows
  centered `Already Applied`/`Already Default` status plus only still-meaningful
  actions. Status is never selectable. Without another action, show information
  directly.
- Toggles show only the truthful opposite action for the current state. Updates
  show `Up to date` when current and Update when outdated; reboot choices appear
  only after a verified result requires them.

For every reachable matrix row, account for entry and Preparing, information,
selection and empty inventory, confirmation or authorization, auth failure,
running progress, logs and full output, Stop, cancellation and rollback,
success and guidance, reboot choice, calm failure, and Return. Mark a screen
inapplicable only with owner evidence. Cover desktop, tablet, and mobile. Stop
exists only for Install, qvOS Update, and ISO Build; non-install mutations never
retain Stop UI or rollback plumbing. Re-probe before execution and reject state
drift instead of running an action that is no longer valid.
Required scope and item selections precede authorization; they are action
inputs, not duplicate confirmation. Default to the least destructive choice
and make authorization copy describe the final selected scope exactly.
Bounded configuration uses the shared `owner-json-v1` form before
authorization. Pass values only through the private captured-runtime file;
passwords never enter arguments, logs, catalogs, or process-wide values.

- Launch desktop TUI windows through `qv/tui/launch`; the shared
  `org.qvos.tui` class owns the centered 1024x509 floating stage.
- Model roles are semantic: CORE (beating red/grayscale) is the hub identity,
  three rings are system-critical or high-impact operations, two rings are
  simple Software installs/removals, and one ring is an ordinary safe task or
  About. ISO build/install remains system-critical.
  Ring count controls visual role only; never infer whether a task mutates
  state from its ring count.
- Information actions are direct read-only surfaces, not miniature
  transactions. Start them immediately, authorize first only when sudo is
  required, and make their sanitized owner output the primary panel. Never add
  confirmation, synthetic progress, percentages, success ceremony, or a
  hidden log step. When an owner succeeds without output, show one truthful
  completion line. Present
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
  Declare `information` only for read-only output and `mutation` for every
  state-changing task. Unprivileged mutations confirm; privileged mutations
  use sudo as their only start gate. This behavior classification is
  independent from the visual ring tier.
  Stream-safe tasks use `task/launch` and `task/run`; owners with prompts,
  authentication, hardware interaction, secret entry, selection, or reboot
  choices stay `native` until a dedicated contract preserves that interaction.
  Searchable single- and multi-selection tasks use
  `task/selections.psv`: collect the allowlisted owner selection first, then
  authorize privileged work or use the normal unprivileged start gate and
  delegate once. Owners expose read-only `--list` output and accept selected values
  after `--`; never synthesize input for Gum or another child interface.
  Center the selector as one block. Center the empty `search` placeholder, but
  left-align an entered query with the option labels. Use the available panel
  width before truncating names, and show up to six rows when the height allows
  it. Reserve that inventory-sized viewport while
  filtering so the title, search row, and persistent control row never move.
  Use the compact `•` cursor. Space is normal search input; Tab toggles an item
  in multi-selection lists. Enter continues with every Tab-toggled item, or
  uses the current row when none were toggled.
  An expected empty inventory shows its short catalog message and Return,
  never a red failure, progress rail, percentage, or retry state.
  A task changes tiers only with its risk or interaction contract and changes
  behavior only when its effects change.
- Configuration refreshes overwrite user state and are always three-ring
  actions. Unprivileged refreshes require start confirmation; privileged
  refreshes use sudo as their only gate. Never classify a reset as a one-ring
  information surface.
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
- Fonts reuse the same two-ring action flow through the dedicated font adapter.
  An absent font opens Install. An installed inactive font offers `Apply Now`
  and `Uninstall`; Apply starts immediately without Stop plumbing, while
  Uninstall moves directly from that choice to authorization. The active font
  shows centered `Already Applied` status and only the meaningful `Uninstall`
  action. Capture the observed font state in the adapter and reject drift
  before listing or running an action. Never add a Walker sheet, a selectable
  status row, or a second Apply confirmation.
  Uninstall delegates exact package removal and restores JetBrains Mono before
  removing an active font.
- Terminals are the other managed install-only family. An absent terminal
  opens privileged Install. An installed non-default terminal opens one
  unprivileged `Make Default` confirmation and exposes no Stop controls. The
  current default opens direct read-only `Already default` information. Derive
  package and active state from `qv/menu/terminal-action`, delegate to the
  inherited terminal owners once, and keep every menu route on
  `action/terminal-launch`. Terminal Install declares `owner-state-v1` so Stop
  restores the previous default plus files created or replaced by the owner.
- Route a software owner through `--action` only when it is safe to consume as
  a captured command stream. Keep owners that require interactive prompts,
  authentication, or configuration in their native terminal until they expose
  a noninteractive contract; never fake input inside the TUI. A captured owner
  with an optional native prompt must receive its explicit noninteractive flag
  in the catalog and have a regression test that rejects the prompt path.
  Resolve repository `qv/` and `omarchy-*` owners from the active
  `OMARCHY_PATH` before `PATH`, so development source and installed owners
  cannot be mixed. Run each captured owner in its own process group while
  retaining the TUI terminal session, so its already-authorized sudo ticket
  remains valid. Prepend the captured-command guard that rejects interactive
  Gum subcommands while preserving noninteractive formatting; an unreviewed
  nested prompt must fail rather than hang.
- A captured owner that may require reboot emits
  `qvOS action: reboot required: <reason>` instead of prompting or rebooting.
  After verified success, the shared result stage offers `Reboot Now` and
  `Later`, defaults to `Later`, and invokes the existing reboot owner only
  after an explicit choice. qvOS Update must defer inherited kernel,
  Hyprland, and state-file reboot prompts to this stage while preserving
  native Omarchy updater behavior outside the qvOS TUI.
- Route a non-Software script through the same `--action` presentation only
  from its fixed task-catalog row. Never accept an arbitrary command from a
  menu or environment variable, and never treat a native catalog row as
  capturable merely because it currently exits successfully.
- Keep `--prototype` as the Codex design and interaction harness. Its simulated
  actions are intentionally separate from the production catalog and do not
  establish product availability.
- Generic non-install mutations never bind, advertise, or react to `Ctrl+C` or
  `Ctrl+Z` while their owner is running. This includes Apply, Make Default,
  Uninstall, refresh, restart, and other `task` operations. Keep those keys as
  cancel-before-start controls only; do not retain per-action Stop copy,
  rollback catalogs, snapshots, probes, or result branches. Information
  commands may still cancel directly.
  Captured Install, qvOS Update, and ISO Build retain the safe-default
  full-terminal Stop confirmation that temporarily replaces the model,
  identity, progress, logs, terminal output, and Help. Keep unpausable work
  running and keep that modal open until Enter confirms Keep or Stop.
  Repeating `Ctrl+C` or `Ctrl+Z` confirms Stop directly and has one visible
  modal hint; no escape shortcut dismisses the decision. Then interrupt the
  full owned process group
  first so Pacman and other transactional owners can clean up, continue a
  job-control-stopped group so its pending interruption can complete, and
  force-reap descendants that ignore the graceful interruption before rendering
  a result. External TUI or terminal closure still stops the complete owned
  process tree; Install, Update, and Build drain the same rollback-aware stop
  path. The Update log consumer must survive the initial signal long enough to
  preserve the updater's exit and cleanup. Captured installs suppress detached
  application launches; their verified success guidance is the entry point
  instead. After Stop,
  probe the declared final state and distinguish no detected result, a target
  reached before Stop, and an owner with no final-state probe. Never claim that
  Stop reversed arbitrary side effects. Run owner rollback only for Install
  through an explicit contract that proves it restores the exact pre-action
  state; never reuse a destructive Uninstall owner as cancellation cleanup.
  Declare those contracts in `action/rollbacks.psv` as `owner-state-v1`.
  The existing mutation owner must implement the checked
  `--qvos-rollback-check`, `--qvos-rollback-snapshot <state>`,
  `--qvos-rollback-seal <state>`, and `--qvos-rollback-restore <state>`
  protocol. Snapshot before delegation, seal the verified owner result, reject
  concurrent drift, and restore owner state before removing packages created
  by the attempt. If owner restoration fails, retain packages needed by that
  state and report the residue.
  Snapshot the Pacman lock before starting. Remove it after cancellation only
  when it was absent before the action, an owned Pacman process was observed,
  the complete process group has stopped, no package manager is active, and the
  lock is still the expected empty root-owned regular file. Preserve and report
  every pre-existing, foreign, active, malformed, or unverified lock.
  A captured install snapshots Pacman's installed package names and versions,
  configured cache, new AUR helper trees, mise installs/downloads/config/lock
  state, and Mix/Hex state before delegation. After the complete owned process
  group and every package manager exit, Stop removes only exact package names and
  cache/build/runtime paths created by that attempt, removes new empty runtime
  roots, restores changed mise files atomically, and reshims. Never use
  Pacman's recursive removal for rollback. Keep the sudo ticket and manager
  observation alive while a completed install waits behind the Stop decision.
  Preserve and report every pre-existing version or path that changed, every
  concurrent or foreign manager result, and every malformed or unverified
  entry; never turn incomplete verification into a clean result. Update keeps
  its dedicated process cleanup, and Boot/ISO installation keeps its stricter
  interruption guard and the same exclusive modal rule.
- Opening logs must not move or resize the active action, progress rail, or
  controls. Landscape logs replace the identity/model column while preserving
  the normal action column. In true fullscreen, every log-capable TUI renders
  the log panel in the 3D model's exact stage slot. Empty running logs use the
  shared `Preparing` animation rather than waiting copy. A confirmed
  cancellation freezes progress immediately; canceled results say canceled,
  never animate toward `100%` or imply success.
- Output-only ISO progress ignores key messages but retains Bubble Tea's input
  reader so terminal capability replies are consumed instead of leaking into
  visible logs. Its exit-message filter remains the interruption boundary.
- Keep the active operation, real milestone, percentage, and a visible bar in
  non-mobile progress views. Use one quiet selection marker for choices; do not
  frame action labels as buttons.
- The smallest progress view may omit the bar, but it must keep the active
  operation, static dimmed dot, and percentage centered as one stable line.
  On completion, keep the semantic result such as `UPDATED` or `INSTALLED`
  instead of replacing it with `100%` or a generic `DONE`.
- Failure is a result, never completed progress. Every domain uses the shared
  calm failure surface: a white `COULD NOT COMPLETE` title, the full wrapped
  explanation in neutral text, and retry or return controls. Never show
  `FAILED`, a red wall of text, a rail, a percentage, or truncated details.
- Every captured install has one concise entry point in
  `success-guidance.psv`. Show it as quiet wrapped copy only after verified
  success. Use a real route, shortcut, command, sign-in surface, or required
  follow-up; never add generic filler, and never show guidance while running,
  after failure, on cancellation, or on read-only information.
- A verified Install may expose one optional owner-backed completion action
  through `action/post-actions.psv`. Enter runs it and Escape returns. A
  completion action that performs a long download or installation must reuse
  `action/post-run`: transition the same TUI into its live owner stream, open
  the shared log panel, omit invented progress, and keep Install Stop plus an
  exact owner rollback. If configured state remains after that phase stops or
  fails, resume it through `action/launch --post-success`; the shared contract
  must render and retry the completion action itself, never the original
  Install. Never detach long work or hide it behind a notification.
  Immediate application launches may return after a verified handoff; never
  use this route for destructive work.
- Keep persistent controls to one context-critical action plus quiet dim-gray
  Help when the hint area has room. Compact hint areas show only the primary
  action. Label Help consistently as `F1`; also accept `Shift+?` outside text
  fields so passwords and filters keep their full character set. Put every other
  active keyboard action in the contextual help overlay. Labels describe the
  action result, not implementation details. Completed, stopped, and failed
  log-producing results keep `V` and `Ctrl+V` active until the user leaves, but
  keep those known shortcuts in contextual Help instead of the persistent
  result row. Never discard captured history at a result transition.
- Authorization surfaces use the shared frameless password rail under the
  generic `Auth Required` title; the model identity owns the action name. Keep
  one blank row between the title and rail and another between the rail and one
  short dimmed, unlabeled sentence describing what will run. Wrap that sentence
  on word boundaries, center each complete line, and never truncate it. The
  empty state is a quiet centered rail. The first character replaces that rail
  completely with a mask whose complete bullet group remains centered at every
  length. Do not add a cursor, side brackets, or an input box.
- `Ctrl+V` on a log-producing flow opens the captured original command output
  inside the same TUI process. Never launch, attach, detach, or duplicate a
  mutating command to imitate a terminal view. Capture owner stdout and stderr
  through one ordered pseudo-terminal stream so terminal-aware tools expose
  live progress. Retain the complete normalized history without line-count or
  line-length truncation; carriage-return redraws replace the current line.
  An open side log may show one borderless, non-red `ctrl+v switch` cue directly
  below its panel; the full terminal view renders the same action as a normal
  persistent control.
- Internal `qvOS action:` progress protocol drives status only. Never retain it
  in visible logs, terminal output, copied history, or result details; preserve
  every real owner output line unchanged.
- Normalize ANSI redraws, carriage returns, backspaces, tabs, and other control
  characters through the shared virtual terminal before rendering captured
  output so child processes cannot move the TUI cursor or break panel geometry.
  Cursor movement and erased-line repaints replace their existing virtual rows;
  never expand spinner or progress repaints into transcript history. Log views
  follow the newest output by default and support line, page, oldest, and newest
  navigation. Disable
  application mouse capture only in full terminal output so normal terminal
  selection and copy work there. Native selection covers rendered cells, not
  internally scrolled history; provide `y` to copy the full captured log.
  Logs remain read-only and never execute pasted content.

## Change Workflow

1. Read the action owner, its TUI adapter, every launch surface, and focused
   tests before editing.
2. Complete the lifecycle screen matrix above for every affected route. A
   shared renderer, key binding, lifecycle, or result change applies to every
   action mode that can reach it. Implement the shared cause, add regression
   coverage for every changed row and transition and at least two consuming
   flows, and inspect every affected visual state. Never accept only the
   reported route, happy path, layout, or screenshot.
3. Keep shared visual behavior and capability configuration at the TUI root
   and action-specific data or delegation in its owner directory. Keep package
   boundaries minimal and use an action package only for a real independently
   tested contract. The ownership test must continue rejecting presentation
   imports from domain packages.
4. Preserve exit `0` for success, `130` for user cancellation, and nonzero for
   failures. Never render success after an owner failure.
5. Run `qv/tui/owner-contracts --check`; if it reports drift, review the owner
   before deliberately refreshing the manifest. Then run `gofmt`,
   `go test -count=1 ./...`, Bash syntax and ShellCheck for shell adapters,
   focused action/menu tests, and `test/qvos/run.sh` when shared contracts or
   lifecycle wiring changes.
6. Build and install the live binary through `qv/tui/install`, apply affected
   launch/config owners, verify the semantic model and responsive log/result
   states, then capture and inspect a fullscreen screenshot with
   `omarchy capture screenshot fullscreen save`.

When an ISO surface changes, follow `qv/iso/AGENTS.md` in addition to this
workflow and verify both boot fallback and the installed-system binary.
