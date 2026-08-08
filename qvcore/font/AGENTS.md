# qvOS Font Workflow

Read this file completely when changing font discovery, active-font reporting,
font application, or a font lifecycle consumer.

`qvcore/font/` is the singular font configuration owner. Native consumers use
the metadata-bearing `qv-font-*` routes; matching `omarchy-font-*` names are
metadata-free compatibility adapters only.

- List only exact installed monospace family names reported by Fontconfig.
  Reject extra arguments and propagate discovery failures.
- Accept one bounded printable family name and require an exact match in the
  current list. Never pass user input through a regular expression or shell
  command string.
- Treat Hyprlock, Waybar, SwayOSD, and Fontconfig as required configuration.
  Update supported terminal configuration only when its file exists.
- Reject symbolic links, foreign ownership, unsafe path components, malformed
  schemas, or ambiguous duplicate settings before changing any file.
- Serialize changes, stage and validate every output first, detect concurrent
  edits, replace each file atomically in its own directory, and restore every
  already-replaced file if the configuration transaction fails.
- Configuration commit is the durable result. Desktop restarts, terminal
  signals, notifications, and the native custom-hook call are
  best-effort integrations and cannot turn a verified commit into partial
  rollback.
- Fixture path overrides must remain inside the explicitly selected user-owned
  config root and never weaken the production checks. Do not change the live
  font merely to verify source.

Run `qvcore/font/check`, Bash syntax and ShellCheck, the focused font and TUI
font suites, menu, CLI, product, upstream-overlay, and full qvOS suites. Review
and refresh `qvcore/tui/owner-contracts.psv` when the font lifecycle dependency
closure changes.
