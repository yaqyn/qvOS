# qvOS Menu Workflow

Read this file completely when changing `qv/menu/`, Omarchy menu extensions,
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
- Keep each concept and breadcrumb in `qv/menu/concepts.psv`; browse screens
  derive from that catalog. Use no separator or placeholder rows.
- Keep browsing curated and shallow while search exposes detailed actions.
  `Update qvOS` is direct; component updates belong to their concept sheet.
- Keep `Settings > Software` as a focused Elephant view backed by
  `software-actions.psv`. Each actionable software row has one read-only,
  owner-derived `Install` or `Uninstall` subtext and activates that action
  directly after a fresh state check. Do not add an intermediate action sheet
  or per-app Learn action.
- Preserve generic Package, Web App, and TUI workflows plus software selectors
  that lack a paired lifecycle owner. Show selectors as `Browse` and delegate
  directly to their inherited list; never invent an Uninstall owner from a
  package name.
- `software-state` owns batched menu detection only. It must not mutate state,
  infer lifecycle state from menu history, or reproduce an installer's own
  convergence checks.
- Keep the interface menu-only. Delegate actions to their existing owners; do
  not add an embedded terminal or terminal mode to the menu.
- Keep qvOS actions in their normal product menus and mirror useful direct
  access in `show_qvos_menu` for user-friendly direct access and testing. Both
  surfaces delegate to the same owner.
- Keep qvOS Elephant provider deltas under `qv/menu/elephant/`. Install them
  through `qv/menu/install` and link inherited providers from Omarchy source.

## Change workflow

1. Read the catalog, extension, provider, installer, and one or two analogous
   routes before editing.
2. Reuse command owners. Do not put install, removal, setup, or update
   implementation in menu code. Route stream-safe owners through the shared
   two-ring TUI action adapter; keep owners that require interactive prompts,
   authentication, or configuration in their native floating terminal.
3. Update focused menu tests for catalog uniqueness, routing, query-preserving
   Tab behavior, runtime installation, and startup ordering.
4. Run Bash syntax and ShellCheck for shell changes and `luac -p` for Lua.
5. Run the focused menu suites, then `test/qvos/run.sh` when shared contracts
   change.
6. Apply with `OMARCHY_PATH=$PWD bash -c 'source qv/install/desktop'`, require
   Elephant and Walker active, query the live provider, and inspect a fullscreen
   screenshot.

During qvsync, compare upstream menu behavior with this catalog. Adopt or
combine better upstream capability, preserve qvOS differentiators on the new
seam, and remove superseded provider, runtime, config, and test plumbing.
