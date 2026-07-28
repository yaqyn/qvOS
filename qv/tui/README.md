# qvOS TUI

This directory owns the qvOS terminal interface, its ISO installer surfaces,
and the ISO build entry point. The Go program is one visual shell with these
modes:

- default: qvOS actions and navigation
- `--prototype`: safe fake script, sudo, application, and boot sessions
- `--update`: qvOS Update confirmation, preflight, authorization, progress,
  logs, and result
- `--iso-installer`: boot installation information and confirmation
- `--iso-progress`: one persistent installation progress and log surface
- `--iso-finished`: installation result and reboot choice

## Responsive contract

The composition follows the terminal's visual orientation. Its aspect is
calibrated against the live Alacritty cell geometry:

- landscape: actions on the left and the 3D stage on the right
- portrait or square: the 3D stage centered above the active content
- constrained: preserve the composition but hide the 3D stage below its
  40x20 quality floor instead of rendering a tiny object
- true fullscreen window or boot TTY: override to a centered cinematic
  composition while keeping the normal 64x32 model ceiling

Menu titles and descriptions use catalog-wide measured columns. Descriptions
yield first when space is constrained; complete rows share one measured width
so identifiers, titles, and descriptions stay aligned.
Opening logs prioritizes progress and log content over the 3D stage.
Every mode uses the same `#020202` background.

## Update

`update/` owns the TUI-specific Update contract and thin engine adapter. The
main hub and `--update` direct mode reuse one flow:

1. Confirm `Update qvOS` or cancel before any work starts.
2. Run the qvOS update owner's read-only preflight.
3. Reuse the shared sudo authorization surface.
4. Delegate once to `omarchy-qvos-update -y`, show known stage milestones, and
   retain all other output in the optional log view.
5. End on an explicit success or actionable failure screen.

Update cannot be canceled after the original Omarchy updater starts. If the TUI
is unavailable, `omarchy-qvos-update` retains its plain terminal confirmation
and update path.

## Boot phases

The boot installer keeps one TUI lifecycle:

1. `--iso-installer` gathers the keyboard, account, host, timezone, and encrypted
   installation target required by the Omarchy installer.
2. `--iso-progress` remains active across both the Arch installation and the
   target-root Omarchy/qvOS installation while reading their shared log.
3. `--iso-finished` takes over after logging stops and offers reboot.

The temporary Omarchy ISO builder integration lives in
`../iso/omarchy-iso-qvos-tui.patch`. `bin/qvos-build` stages a fresh official
builder and applies that patch without modifying upstream source.

## Development

Run the prototype without real system actions:

```bash
go run . --prototype
```

Use arrow keys or `hjkl`, Enter to open, `v` to toggle logs, `r` to retry the
fake failure session, and Escape to return or exit.

Run the focused checks and renderer benchmarks from this directory:

```bash
go test -count=1 ./...
go test -run '^$' -bench 'Benchmark(RenderShapes|HubView)$' -benchmem
```
