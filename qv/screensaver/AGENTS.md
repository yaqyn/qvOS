# qvOS Screensaver Workflow

Read this file completely when changing `qv/screensaver/`, screensaver launch
or exit behavior, cursor handling, or its Hypridle interaction.

`qvos-launch-screensaver` owns the multi-monitor screensaver lifecycle and
global compositor state. `qvos-screensaver` owns one terminal animation and
input detection.

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
- `qv/screensaver/install` owns the complete user runtime. Stage each
  replacement before removing stale content, and run this owner before
  privileged desktop owners so a later sudo or system failure cannot leave the
  screensaver config or commands missing.

Run Bash syntax and ShellCheck for changed scripts, then
`test/qvos/qvos-screensaver-test.sh` and the full qvOS shell suite when shared
idle or install contracts change. Apply through `qv/install/desktop`, compare
installed payloads with source, launch the screensaver, inspect a fullscreen
screenshot, close it externally, and require the prior cursor option and a
visible pointer to recover.
