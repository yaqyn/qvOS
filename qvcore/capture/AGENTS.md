# qvOS Capture Workflow

Read this file completely when changing screenshots, OCR, screen recording,
selection behavior, capture output, recording state, or the Waybar recording
indicator.

`qvcore/capture/` is the only Capture implementation owner. Public commands
are `qv-capture-screenshot`, `qv-capture-screenrecording`, and
`qv-capture-text-extraction`; matching Omarchy names are metadata-free
compatibility adapters only. Hyprland, menus, Elephant, and Waybar use native
qv routes.

- Keep picker and recording state private under
  `${XDG_RUNTIME_DIR}/qvos-capture`. Serialize picker and recorder actions,
  validate state ownership and exact paths, and signal or stop only the PID and
  process-start token recorded by qvOS. Never use broad `pkill` or shared
  `/tmp` state. Treat a process disappearing during `/proc` inspection as a
  normal no-match and suppress only that race's procfs diagnostic.
- Freeze the screen until a selection has been captured, return cancellation
  as 130, support negative monitor coordinates and transformed outputs, and
  use the focused monitor for fullscreen capture. Refuse a powered-off focused
  output and bound compositor frame requests so DPMS cannot hang Capture.
- Validate options, tools, OCR languages, output directories, webcam devices,
  and media before mutation. Bound OCR output and debug logs. Test-only process
  matching requires an unprivileged temporary HOME and runtime.
- Create image and video outputs privately with mode 0600 and publish by a
  no-clobber hard link. Never overwrite an existing capture or leave a partial
  output after a failed start. Preserve a stale valid recording for recovery;
  reject unsafe state for manual inspection.
- Missing clipboard, editor, notification, or post-processing tools may reduce
  convenience but must not discard an otherwise complete capture. Missing
  validation tools fail closed while preserving recoverable recording state.
- `QVOS_*` variables are authoritative. Accept matching `OMARCHY_*` variables
  only as transition input, and migrate active UWSM examples to qvOS names.
- The Waybar indicator calls `qvcore/capture/status` directly and performs no
  process discovery of its own. Inactive status stays invisible; active,
  recoverable, and unsafe state remain distinguishable.

Run `qvcore/capture/check`, Bash syntax, ShellCheck, the focused Capture, CLI,
menu, config-migration, product, install, and upstream tests, then the full
qvOS suite. Use fixture capture tools for failure and recovery coverage. After
live alignment, apply desktop/config reconciliation, verify inactive status,
and use a real screenshot for any changed visual behavior. Do not start a real
recording or webcam merely to verify source.
