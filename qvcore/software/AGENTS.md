# qvOS Optional Software Lifecycle

Read this file completely when changing qvOS-owned optional software install or
removal owners, their package boundaries, local configuration, services,
downloads, launches, or reboot handoff.

- Native routes are `qv install nordvpn`, `qv install vscode`, and
  `qv voxtype config/install/model/remove/status`. Public inherited names are
  metadata-free adapters only. Put mutation in one `qvcore/software/` owner
  and keep state, presentation, sudo, and probe fields truthful in menu, TUI,
  and Waybar consumers.
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
- Native owners use qvOS package, command, restart, and reboot helpers. Until
  hardware and theme commands are promoted, declare the exact inherited
  Voxtype Vulkan probe and VS Code theme setter in their TUI source contracts.
- Voxtype model setup passes `voxtype`, `setup`, and `model` as exact argument
  boundaries through native presentation. Its Waybar status owner keeps one
  exact follower PID, terminates only that child, validates JSON objects, and
  never signals a whole process group. The qvOS Waybar overlay owns all three
  Voxtype routes while preserving the reviewed inherited module styling.

Run `qvcore/software/check`, Bash syntax, ShellCheck, focused software/TUI tests,
`qvcore/tui/owner-contracts --check`, and the full qvOS suite. Do not install,
remove, authenticate, download models, or reboot live for source verification.
