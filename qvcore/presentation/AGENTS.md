# qvOS Presentation Workflow

Read this file completely when changing result terminals, command
presentation, completion or failure screens, or their window identity.

`qvcore/presentation/` owns the complete terminal result flow. Public native
commands are `qv-launch-floating-terminal-with-presentation`, `qv-show-done`,
and `qv-show-failed`; matching Omarchy names are metadata-free compatibility
adapters only.

- Preserve command arguments exactly. Never rebuild, evaluate, or implicitly
  pass a caller string through a shell. A caller that needs a shell passes an
  explicit reviewed shell and argument vector.
- Use `org.qvos.terminal` for new result windows. Retain the old class only in
  the floating-window match while compatibility callers may still exist.
- Treat exit 130 as cancellation with no false success or failure result.
  Validate explicit statuses and propagate the command status unchanged.

Run `qvcore/presentation/check`, the focused presentation, package, menu,
Thunar, TUI, product, and config-migration tests, Bash syntax, ShellCheck, and
the full qvOS suite. Fixture terminal executors must prove exact argument
boundaries without opening a real terminal.
