# qvOS Optional Software Lifecycle

Read this file completely when changing qvOS-owned optional software install or
removal owners, their package boundaries, local configuration, services,
downloads, launches, or reboot handoff.

- Public inherited command names are metadata-only adapters. Put mutation in
  one `qv/software/` owner and keep state, presentation, sudo, and probe fields
  truthful in the menu/TUI catalogs.
- Optional owners never claim or remove a qvOS base package. Normal uninstall
  preserves user configuration, models, credentials, and other application
  data unless a separately scoped TUI choice explicitly owns deletion.
- Captured installs are noninteractive after their explicit flag, never launch
  the application or a file manager, and defer reboot through the shared qvOS
  signal only when current state requires it.
- Preserve existing user configuration. Install defaults only when their exact
  destination is absent; application-specific theme owners may update only
  their declared theme fields.
- Stop and remove exact service units before final daemon reload, but retain
  configuration and downloaded data for reinstall. Notifications and desktop
  refreshes after verified installation are best-effort.

Run `qv/software/check`, Bash syntax, ShellCheck, focused software/TUI tests,
`qv/tui/owner-contracts --check`, and the full qvOS suite. Do not install,
remove, authenticate, download models, or reboot live for source verification.
