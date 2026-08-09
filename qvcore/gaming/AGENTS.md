# qvOS Gaming Lifecycle

Read this file completely when changing qvOS gaming packages, controller
drivers, RetroArch configuration, gaming install/removal owners, or their TUI
lifecycle.

- `qvcore/gaming/apps.psv` is the singular package boundary for Heroic, Lutris,
  Minecraft, Moonlight, and Steam. `qvcore/gaming/app` installs or removes only
  those declared packages. Captured installs never launch an application, and
  normal removal always preserves configuration, credentials, caches, saves,
  and game libraries. Steam's separately scoped TUI owner may delete only its
  four exact local data directories after preflighting them as owned real
  directories; the default scope preserves them.
- `qvcore/gaming/gpu-lib32` is the singular optional 32-bit graphics-driver
  selector. App installs combine its detected packages with the app in one
  qvOS package transaction. Keep hardware inspection read-only and fixture it;
  never install or remove gaming packages during source verification.
- Xbox Cloud Gaming remains a user-invoked optional Web App owner. It delegates
  to the native Web App lifecycle, uses no downloaded icon, and never launches
  automatically. Fresh install and application refresh must keep the bundled
  Web App inventory empty. Optional installers are not preinstalled apps.
- GeForce NOW remains an interactive opt-in vendor installer. Require explicit
  confirmation before package/download execution, HTTPS-only curl policy, a
  private temporary directory with cleanup, regular-file ownership and size
  validation, and a verified Flatpak result. Do not claim a vendor checksum,
  auto-launch a browser, or delete its user data during normal removal.
- qvOS base owns Wine and the shared gaming runtime. The Lutris owner installs
  only Lutris plus detected graphics support; never install a conflicting Wine
  variant, duplicate base dependencies, or modify package-managed executables.
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

Run `qvcore/gaming/check`, Bash syntax, ShellCheck, focused gaming, Web App,
software, and TUI tests, `qvcore/tui/owner-contracts --check`, and the full qvOS
suite. Use fixtures for packages, downloads, Web Apps, modules, GPU policy, and
data lifecycles; do not download vendor installers, mutate live drivers, or
install/remove gaming packages for source verification.
