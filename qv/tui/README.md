# qvOS TUI

This directory owns the qvOS terminal interface, its ISO installer surfaces,
and the ISO build entry point. The Go program is one visual shell with these
modes:

- default: qvOS actions and navigation
- `--prototype`: safe fake script, sudo, application, and boot sessions
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
