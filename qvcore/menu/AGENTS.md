# qvOS Menu Workflow

Read this file completely when changing `qvcore/menu/`, Omarchy menu extensions,
Walker or Elephant integration, menu search, or qvOS menu routes.

## Product contract

- Keep Home to `All Apps`, `Update qvOS`, `Settings`, and `More`.
- Global search is exhaustive. Tab switches Apps/Menu without clearing the
  query.
- Keep natural-language aliases in `search-intents.psv`. Exact intents must be
  high-confidence and map to one unique visible result; leave ambiguous words
  to exhaustive fuzzy search.
- Organize browse screens by nouns. Verbs are actions on one canonical concept
  sheet, never duplicate Install, Uninstall, Style, or Update folders.
- Keep each concept and breadcrumb in `qvcore/menu/concepts.psv`; browse screens
  derive from that catalog. Use no separator or placeholder rows.
- Activate a concept's sole action directly. Render a concept sheet only when
  it presents two or more meaningful choices.
- Keep browsing curated and shallow while search exposes detailed actions.
  `Update qvOS` is direct; component updates belong to their concept sheet.
- Keep `Settings > Software` as a focused Elephant view backed by
  `software-actions.psv`. Each row shows only the program or concept name and
  passes its slug to the checked TUI; Walker never shows lifecycle state,
  Install/Uninstall/Apply labels, or an action sheet. The TUI performs the fresh
  state check and owns every status, choice, authorization, progress, and
  result. Do not add a per-app Learn action.
- Never bundle optional user-data deletion into a generic Uninstall. Put the
  exact removal scope inside the TUI before authorization, default to preserving
  data, and make the authorization summary match the selected scope.
- Preserve generic Package and Web App workflows plus software selectors that
  lack a paired lifecycle owner. Show selectors as `Browse` and delegate
  directly to their inherited list; never invent an Uninstall owner from a
  package name.
- Web App creation and removal are the native exception to that inherited
  selector seam: route them only through `qv-webapp-install`, the shared
  searchable selector, and `qv-webapp-remove`. Inventory and mutation remain
  singularly owned by `qvcore/desktop/webapp`.
- Optional fixed Web App installers may delegate to that same native lifecycle,
  but fresh qvOS and application refresh keep the bundled Web App inventory
  empty. An installer row is not authorization to pre-create its desktop entry.
- Do not expose a generic TUI-shortcut installer. The qvOS TUI is the product
  interface, not an arbitrary-command desktop-wrapper lifecycle; terminal tools
  remain accessible through their ordinary CLI or dedicated owner.
- `software-state` owns batched menu detection only. It must not mutate state,
  infer lifecycle state from menu history, or reproduce an installer's own
  convergence checks.
- Keep install-only leaves in `software-installers.psv`. Route every
  noninteractive captured stream through the shared two-ring TUI, retain
  prompts, authentication, configuration sessions, and nested TUIs as
  `native`, and verify TUI installs through `software-installer-state` with a
  real declared probe. If an owner also supports a native prompt, put its
  explicit noninteractive flag in the TUI catalog and test that Gum is never
  reached; do not rely on closed stdin as implicit confirmation.
- Fonts are the deliberate install-only exception with a small managed
  lifecycle. An absent font opens Install directly. An installed inactive font
  opens the shared TUI with `Apply Now` and `Uninstall`; the active font shows
  `Already Applied` with only `Uninstall`. Keep status as text, never a dummy
  selectable action, and never put the action sheet in Walker. Keep package
  package state, Apply, exact removal, and the JetBrains Mono fallback in
  `qvcore/menu/font-install`; active-font detection and safe configuration
  mutation belong only to `qvcore/font/`. Menu routes only hand the selected
  font to the TUI.
- Terminals are a second deliberate managed exception. Route Alacritty, Foot,
  Ghostty, and Kitty through `action/terminal-launch` from every menu surface.
  `qvcore/menu/terminal-action` reports `available`, `installed`, or `active`,
  delegates missing installs to `qv-install-terminal`, and delegates an
  installed non-default choice to `qv-default-terminal`. Never present
  Install for an installed terminal or request sudo merely to make it default.
  The active terminal opens direct `Already default` information.
- A concept with both availability and active/default/applied state follows the
  lifecycle screen matrix in `qvcore/tui/AGENTS.md`. Probe those states separately,
  expose only actions backed by exact owners, render current-state labels as
  status rather than selectable actions, and reject drift before mutation.
  Every menu surface passes only the selected concept or program identity; it
  never preselects, labels, or renders a lifecycle action.
- Fixed non-Software scripts use `qvcore/tui/task/actions.psv`: three rings for
  system-critical/high-impact operations, one ring for ordinary safe tasks,
  and `native` for any unresolved interaction. Keep ring presentation separate
  from behavior: `information` is read-only, while every state-changing task
  is `mutation`. Route by catalog slug or exact owner match; never place
  arbitrary menu shell in the captured task runner.
- Fixed tasks with an explicit `task/selections.psv` contract use the shared
  searchable single- or multi-selector and pass only owner-listed values.
  Captured Software owners may defer a required reboot to the shared
  Reboot Now/Later result; neither case justifies an embedded terminal.
- Keep the interface menu-only. Delegate actions to their existing owners; do
  not add an embedded terminal or terminal mode to the menu.
- Keep qvOS actions in their normal product menus. Do not maintain a parallel
  qvOS feature submenu.
- Keep qvOS Elephant provider deltas under `qvcore/menu/elephant/`. Install them
  through `qvcore/menu/install` and link inherited providers from Omarchy source.
- `qvcore/menu/menu` is the singular menu orchestrator. It sources `base` and
  `routes` exactly once, then loads the user-owned
  `~/.config/omarchy/extensions/menu.sh` compatibility ABI last so personal
  overrides remain possible. Keep every built-in function in exactly one of
  `base` or `routes`; neither module may call an Omarchy command route. The
  metadata-bearing `qv-menu` adapter is native and `omarchy-menu` delegates only.
- Never reinstall the former generated `qvos-menu.sh` override. Menu install
  backs up and removes only its exact source line from the personal extension,
  deletes only the reviewed generated overlay hash, and leaves any modified
  overlay preserved but inert. Reject links, foreign ownership, and unsafe
  personal extension targets before cleanup.
- Native qvOS provider, Walker set, and theme identifiers use `qvos-menu`.
  Treat former `qvos-omarchy-menu` artifacts as generated migration residue:
  remove only their exact owned block, link, and theme while preserving foreign
  files and user-selected themes.
- The menu runtime under `~/.local/lib/qvos/menu` is generated payload, not
  user configuration. Retire obsolete payload files only when their exact
  reviewed hash matches; refuse links, foreign ownership, and modified
  lookalikes so cleanup cannot erase an administrator's evidence.
- Launch every TUI-backed menu action through the checked
  `~/.local/lib/qvos/tui` payload. Menu state may come from the active
  Omarchy owner, but no route may pair that owner with launch, task, or
  cancellation adapters from the live checkout.
- `qvcore/menu/{menu,launch-walker,file,input,select,keybindings}` owns native
  Walker helpers. `qv-launch-walker` and `qv-menu-*` are the public commands;
  matching Omarchy names are metadata-free compatibility adapters. Validate
  prompts, choices, search directories, formats, monitor data, and arguments
  before handing them to Walker. Active qvOS config and owners use only the
  native routes.
- `qvcore/menu/refresh-walker` owns explicit restoration of Walker startup,
  Walker, and Elephant config. Preflight every source before the first backup,
  restore through `qvcore/config/refresh`, then reconcile the menu once. The
  native command is `qv-refresh-walker`; its Omarchy name is compatibility
  only. Fresh install receives startup files from `config/` and never creates
  a Pacman hook that executes a user-writable checkout. qvOS update-log analysis
  records a private Walker restart marker after Walker or Elephant changes.
- `retire-pacman-hook` removes only the exact historical qvOS/Omarchy Walker
  hook schema and preserves links, foreign ownership, and modified content.
  Its system-root override is test-only and must remain confined to a
  caller-owned directory under `/tmp`.
- Capture menu leaves delegate once to `qv-capture-screenshot`,
  `qv-capture-screenrecording`, or `qv-capture-text-extraction`; selection,
  media, process, and recovery behavior remains in `qvcore/capture/`.

## Change workflow

1. Read the catalog, `base`, `routes`, provider, installer, and one or two
   analogous routes before editing.
2. Reuse command owners. Keep only thin stable adapters for inherited inline
   package routes. Route stream-safe Software through the shared two-ring
   action adapter and fixed non-Software scripts through their classified task
   row; keep prompts, authentication, configuration, secrets, hardware
   interaction, reboot choices, and nested TUIs in the native owner.
3. Update focused menu tests for catalog uniqueness, routing, query-preserving
   Tab behavior, runtime installation, and startup ordering. Run
   `qvcore/tui/owner-contracts --check`; after a reviewed catalog or owner change,
   refresh its manifest deliberately and inspect the exact diff.
   Walker fixtures must distinguish terminal stdin from piped choice input so
   tests remain bounded in both interactive and noninteractive runners.
4. Run Bash syntax and ShellCheck for shell changes and `luac -p` for Lua.
5. Run the focused menu suites, then `test/qvcore/run.sh` when shared contracts
   change.
6. Apply with `QVOS_PATH=$PWD bash -c 'source qvcore/install/desktop'`, require
   Elephant and Walker active, query the live provider, and inspect a fullscreen
   screenshot.

## qvsync software reconciliation

When the exact upstream target changes optional software, its menus, or an
install/removal owner:

1. Inspect `<reviewed-upstream-sha>:bin/omarchy-menu` plus every changed
   `omarchy-install-*`, `omarchy-remove-*`, package helper, and setup owner at
   that same exact SHA. Compare new, renamed, and removed software leaves with
   `concepts.psv`, `software-actions.psv`, selectors, aliases, installed
   payloads, and focused tests; do not infer coverage from filenames alone.
2. Add a review-ledger row for each upstream leaf: upstream name and owners,
   qvOS slug or selector, decision, independent availability and
   active/default/applied probes, complete state-to-action and screen matrix,
   per-operation presentation, sudo requirement, Stop/cleanup behavior, and
   verification. Use the root qvsync decisions and explain every preserved
   selector, omission, and `no-impact`.
3. Adopt a flat row only with a stable concept, real read-only state, and real
   install and uninstall owners. Reuse those owners exactly once. If upstream
   has no safe paired lifecycle, keep the software reachable through an
   inherited `Manage` or `Browse` selector, reintroducing that selector when
   its category was previously flattened; never invent an Uninstall owner from
   a package name.
4. Choose `tui` independently for Install and Uninstall only when that owner is
   a safe captured command stream. Keep interactive questions, authentication,
   configuration, reboot choices, and owner-controlled destructive
   confirmations `native`.
5. Determine sudo per operation by tracing the complete owner path, including
   transitive helpers such as `omarchy-pkg-add` and `omarchy-pkg-drop`; do not
   trust missing top-level command metadata as proof that sudo is unnecessary.
6. Update the catalog, action registry, probes, selectors, intents, tests,
   runtime payload, and stale residue as one adaptation. Retire a stale row
   when its upstream owner disappears unless qvOS deliberately preserves a
   complete independent owner. Verify unique global and focused search results,
   both Install and Uninstall routing, state flips, source/runtime parity, the
   live Elephant provider, and the shared two-ring TUI where selected before
   approving the reviewed upstream SHA.

Adopt or combine better upstream capability, preserve qvOS differentiators on
the supported seam, and remove superseded provider, runtime, config, and test
plumbing.
