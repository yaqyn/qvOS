# qvOS Application Defaults Workflow

Read this file completely when changing browser, editor, terminal, XDG
association, UWSM editor, or `xdg-terminal-exec` default selection.

`qvcore/defaults/` is the singular read and mutation owner. Native consumers
use metadata-bearing `qv-default-*` routes; matching `omarchy-default-*` names
are metadata-free compatibility adapters only.

- Accept only the fixed supported slugs and reject extra arguments. Refuse to
  select an unavailable editor, terminal, or browser desktop entry.
- Browser selection delegates once to `xdg-settings`, verifies its complete
  default-browser contract, and restores the previous browser on failure. Do
  not scatter direct XDG browser association writes across install or removal.
- Editor and terminal configuration rejects links, foreign ownership, unsafe
  file types, and linked path components. Replace user files atomically in the
  same directory, preserve existing modes, and keep unrelated UWSM content.
- Reuse `qvos_defaults_check_target` for mutation-free path preflight and
  `qvos_defaults_atomic_write` for the eventual file transaction. Preflight
  must reject the same unsafe target that mutation would reject.
- Missing read-only state is empty, not fabricated. A malformed or unsafe
  existing file is an error. Notifications are best-effort and never convert
  a verified settings change into failure.
- Test path and application-directory overrides are read or written only
  within the explicitly selected fixture; they never weaken validation.

Run `qvcore/defaults/check`, Bash syntax and ShellCheck, the defaults, browser,
menu, terminal TUI, product, CLI, upstream-overlay, and full qvOS suites. When
terminal delegation changes, review and refresh `qvcore/tui/owner-contracts.psv`
through its owner. Do not change the live default merely to verify source.
