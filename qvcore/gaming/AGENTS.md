# qvOS Gaming Lifecycle

Read this file completely when changing qvOS gaming packages, controller
drivers, RetroArch configuration, gaming install/removal owners, or their TUI
lifecycle.

- `qvcore/gaming/retroarch.packages` is the singular RetroArch package inventory.
  Both owners resolve it through `qvcore/gaming/retroarch-packages`; never duplicate
  package lists. Normal uninstall removes packages only and preserves config,
  saves, cache, ROMs, BIOS files, shaders, and other user data.
- `qvcore/gaming/xbox-files` owns the two xpadneo module files. Preflight both files
  before package mutation, accept only absent or exact qvOS content, and never
  overwrite or delete a foreign file or symbolic link.
- Preserve unrelated `input` group membership. Swap xpad/xpadneo live when
  safe and request a reboot only when the group or running driver cannot take
  effect immediately. Captured TUI owners use explicit `--defer-reboot`.
- Keep installs noninteractive and stream-safe. Do not launch applications or
  file managers from a captured install; success guidance owns the next step.

Run `qvcore/gaming/check`, Bash syntax, ShellCheck, focused gaming/software/TUI
tests, `qvcore/tui/owner-contracts --check`, and the full qvOS suite. Use fixtures
for package, module, and data-lifecycle checks; do not mutate live drivers or
install/remove gaming packages for source verification.
