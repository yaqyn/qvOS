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
- Native routes are `qv install/remove gaming retroarch` and
  `qv install/remove gaming xbox controllers`. Inherited names are
  metadata-free compatibility adapters only; native owners use `QVOS_PATH`,
  qvOS package helpers, and the native system-reboot route.
- Preserve unrelated `input` group membership. Swap xpad/xpadneo live when
  safe and request a reboot only when the group or running driver cannot take
  effect immediately. Captured TUI owners use explicit `--defer-reboot`.
- Keep installs noninteractive and stream-safe. Do not launch applications or
  file managers from a captured install; success guidance owns the next step.

`qvcore/gaming/hybrid-gpu-*` singularly owns optional NVIDIA hybrid-GPU
switching. Fresh qvOS never installs `supergfxctl` or a GPU policy. Require both
a non-NVIDIA integrated display controller and an NVIDIA display controller,
confirm before package or policy mutation, and refuse pending or unsupported
modes. Install fixed root-owned payloads under
`/usr/lib/qvos/gaming/hybrid-gpu/`; the root helper serializes changes, preserves
unrelated valid JSON fields, stages files atomically, accepts only exact qvOS or
known inherited hooks, restores files and service enablement on failure, and
never starts the daemon before the requested reboot. Integrated mode alone owns
the qvOS sleep hook and startup delay. Hybrid mode removes only exact managed
copies. Never execute a user-writable checkout from system sleep or systemd.
Use fixture roots for all mutations; source verification must never install the
package, change the live GPU, enable `supergfxd`, or reboot.

Run `qvcore/gaming/check`, Bash syntax, ShellCheck, focused gaming/software/TUI
tests, `qvcore/tui/owner-contracts --check`, and the full qvOS suite. Use
fixtures for package, module, GPU-policy, and data-lifecycle checks; do not
mutate live drivers or install/remove gaming packages for source verification.
