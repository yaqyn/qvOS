# qvOS Presentation Workflow

Read this file completely when changing result terminals, command
presentation, completion or failure screens, or their window identity.

`qvcore/presentation/` owns the complete terminal result flow. Public native
commands are `qv-launch-floating-terminal-with-presentation`, `qv-show-done`,
and `qv-show-failed`; matching `omarchy-*` names are metadata-free compatibility
adapters only.

Its window identity is owned once in
`qvcore/config/base/hypr/windows.lua`, which keeps only base applications and
explicit qvOS installer capabilities. Never retain service-specific Web App or
unowned application classes there.

- Preserve command arguments exactly. Never rebuild, evaluate, or implicitly
  pass a caller string through a shell. A caller that needs a shell passes an
  explicit reviewed shell and argument vector.
- Use `org.qvos.terminal` for result windows; the native Hyprland base floats
  that exact identity.
- Treat exit 130 as cancellation with no false success or failure result.
  Validate explicit statuses and propagate the command status unchanged.

Run `qvcore/presentation/check`, the focused presentation, package, menu,
Thunar, TUI, and product tests, Bash syntax, ShellCheck, and
the full qvOS suite. Fixture terminal executors must prove exact argument
boundaries without opening a real terminal.
