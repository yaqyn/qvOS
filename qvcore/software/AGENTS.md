# qvOS Optional Software Lifecycle

Read this file completely when changing qvOS-owned optional software install or
removal owners, their package boundaries, local configuration, services,
downloads, launches, or reboot handoff.

- Native routes include
  `qv install dropbox/helix/nordvpn/once/tailscale/terminal/vscode/zed` and
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
- The Voxtype configuration seed lives only at
  `qvcore/software/voxtype-config.toml`; `default/voxtype/` is retired. Never
  install that seed unless the user's exact configuration path is absent.
- Terminal installation delegates default selection to `qv-default-terminal`,
  copies only a missing approved config and desktop entry, and never writes the
  XDG terminal preference itself. The optional Foot desktop entry lives only at
  `qvcore/software/foot.desktop`; it is not part of the fixed base application
  inventory and application refresh installs it only when Foot is present.
  Helix tracks the rendered theme through the
  `qvos` theme name; its `hx` alias belongs to the qvOS shell overlay, not the
  installer. Its package-free reconciliation mode creates only missing native
  configuration and preserves every existing file; desktop updates invoke it
  only when Helix is installed. Historical Omarchy seed and link convergence
  is retired. Zed installs only
  `zed`, delegates its generated local theme to
  `qvcore/theme/set-zed`, preserves existing settings, and never restores the
  retired Omazed helper or launches the editor.
- Stop and remove exact service units before final daemon reload, but retain
  configuration and downloaded data for reinstall. Notifications and desktop
  refreshes after verified installation are best-effort.
- Native owners use qvOS package, command, restart, and reboot helpers. Until
  hardware and theme commands are promoted, declare the exact inherited
  Voxtype Vulkan probe and VS Code theme setter in their TUI source contracts.
- Voxtype model setup passes `voxtype`, `setup`, and `model` as exact argument
  boundaries through native presentation. Its Waybar status owner keeps one
  exact follower PID, terminates only that child, validates JSON objects, and
  never signals a whole process group. The complete qvOS Waybar config owns
  all three Voxtype routes and their module styling.
- Dropbox installs only its CLI, signature support, and current tray library;
  never restore its retired Nautilus extension or detach the application from
  a captured install. Tailscale authentication stays native, never accepts
  advertised routes implicitly, and never creates a Web App. ONCE may open its
  nested TUI only after its exact packaged service starts successfully.

Run `qvcore/software/check`, Bash syntax, ShellCheck, focused software/TUI tests,
`qvcore/tui/owner-contracts --check`, and the full qvOS suite. Do not install,
remove, authenticate, download models, or reboot live for source verification.
