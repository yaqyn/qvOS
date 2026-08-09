# qvOS Screensaver Workflow

Read this file completely when changing `qvcore/screensaver/`, screensaver launch
or exit behavior, cursor handling, or its Hypridle interaction.

`qvos-launch-screensaver` owns the multi-monitor screensaver lifecycle and
global compositor state. `qvos-screensaver` owns one terminal animation and
input detection. It reads only the bounded, user-owned
`~/.config/qvos/branding/screensaver.txt` file installed and migrated by the
Branding owner; never restore active Omarchy branding state.

Public `qv-launch-screensaver` and `qv-screensaver` commands carry metadata;
matching `omarchy-*` commands are metadata-free source compatibility adapters.
Runtime aliases are direct symlinks to the two installed `qvos-*` owners, not
copied adapters. Keep `org.omarchy.screensaver` only as the existing Hyprland
window-class ABI until window rules and live-window matching migrate together.
`qvcore/screensaver/close` is the singular close transaction shared by the
runner and desktop lock owner. It prevalidates the complete matching Hyprland
window inventory before issuing any close dispatch; never restore broad
process-pattern termination.

`qvcore/screensaver/toggle` is the only screensaver-availability mutation. It
delegates the private `screensaver-off` flag to the shared config toggle owner;
menus and concepts use `qv-toggle-screensaver`, never its compatibility name.

- Never use `cursor:invisible true`. It is compositor-wide state and can leave
  the desktop cursor hidden when lock, DPMS, or an external process closes the
  screensaver terminal before local cleanup completes.
- Hide the cursor with its inactivity timeout so pointer movement is always a
  recovery path. Capture the prior value once in the launcher, supervise every
  screensaver window, and restore it on normal, signal, input, and external
  closure paths.
- Keep one launcher under the runtime lock, launch one terminal per active
  monitor, restore the previously focused monitor, and close every screensaver
  window when any runner detects keyboard or pointer input.
- Preserve the Hypridle ordering: screensaver first, lock second, then guarded
  suspend. Do not restore external state from an unsupervised per-monitor
  runner.
- `qvcore/screensaver/install` owns the complete user runtime. Stage each
  replacement before removing stale content. Its Alacritty, Foot, and Ghostty
  profiles live only in `qvcore/screensaver/` and are installed atomically into
  `~/.local/lib/qvos/screensaver`; launch never reads the development checkout.
  Run this owner before privileged desktop owners so a later sudo or system
  failure cannot leave the screensaver config or commands missing.

List promoted inherited paths in sorted `native-paths`, list removed inherited
trees in `retired-paths`, and run
`qvcore/screensaver/check`, Bash syntax, and ShellCheck for changed scripts, then
`test/qvcore/qvos-screensaver-test.sh` and the full qvOS shell suite when shared
idle or install contracts change. Apply through `qvcore/install/desktop`, compare
installed payloads with source, launch the screensaver, inspect a fullscreen
screenshot, close it externally, and require the prior cursor option and a
visible pointer to recover.
