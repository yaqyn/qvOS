# qvOS TUI

This directory owns the qvOS terminal interface, its ISO installer surfaces,
and the ISO build entry point. The Go program is one visual shell with these
modes:

- default: qvOS Update and ISO Build
- `--prototype`: safe fake script, sudo, application, and boot sessions
- `--update`: qvOS Update preflight, authorization, progress, logs, and result
- `--action`: classified Software or fixed-task presentation; two-/three-ring
  actions use progress and exactly one start gate, while one-ring actions run
  directly into their information output after any required authorization
- `--iso-installer`: boot installation information and confirmation
- `--iso-progress`: one persistent installation progress and log surface
- `--iso-finished`: installation result and reboot choice

## Shared flow architecture

The TUI root owns reusable presentation and capability configuration:

- `flow.go` declares model, start confirmation, preflight, authorization, and
  progress needs
- `authorization.go` renders every password authorization surface
- `progress.go` renders compact and full progress for Update, Software, ISO,
  and the prototype
- `logs.go` renders the shared scrolling log panel
- `accessibility.go` owns persistent controls, Help, and terminal output
- `text.go` keeps shared copy within real terminal-cell widths

Domain packages under `qv/tui/<action>/` provide copy, milestones, preflight,
verification, and one delegation to the real owner. They do not render screens
or choose responsive behavior. A domain selects only the shared capabilities
its flow needs.

## Responsive contract

The composition follows the terminal's visual orientation. Its aspect is
calibrated against the live Alacritty cell geometry:

- desktop special TUI routes share the centered `org.qvos.tui` 1024x509
  floating stage
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
Landscape logs use a dedicated 3:7 progress/log split, up to a 96x16-cell log
panel, instead of inheriting the compact identity-column limits.
Non-mobile progress views keep the active operation, real milestone, percentage,
and a visible loading bar.
The smallest progress view keeps the active operation, static dimmed dot, and
percentage instead of collapsing to an unexplained number.
Compact completion keeps the semantic result (`UPDATED`, `INSTALLED`, and so
on) instead of replacing it with `100%` or a generic `DONE`.
Confirmation choices use one quiet marker instead of framed terminal buttons.
Every mode uses the same `#020202` background.

## Accessibility

Every responsive surface prioritizes its single most important action. Help is
dim gray when the hint area has room and yields entirely in compact hint areas;
its persistent label is always `F1`. `Shift+?` also opens contextual Help
outside text fields, while `F1` opens it everywhere so passwords, search
filters, and other input retain the `?` character. The help screen inventories
the current state's navigation, confirmation, editing, exit, retry, log, and
interruption keys.
The production hub lists only complete working actions. Each row has a stable
action key, so navigation coordinates never define behavior. Future actions
must delegate to their real qvOS or Omarchy owner.

`v` toggles the composed qvOS log panel. `Ctrl+V` switches log-producing flows
to a same-process `TERMINAL OUTPUT` view of the captured original command
stream. Both remain documented in contextual Help without competing with the
screen's primary action. The terminal view never spawns a second terminal or
duplicates the running action.

Open log views show a quiet, non-red `ctrl+v switch` cue below the log pane.
The full terminal view promotes that switch to the normal high-contrast
control row. Arrow or `j`/`k` keys scroll one line, Page Up and Page Down scroll
one page, Home opens the oldest retained output, and End resumes the newest
output. Mouse capture is disabled only in full terminal output, where
terminal-native selection and `Ctrl+Shift+C` copy work normally. Native
selection covers the currently rendered cells; press `y` to copy the full
captured log, including output outside the viewport. Captured output is
read-only.

The four model roles carry meaning across surfaces:

- CORE: beating red/grayscale hub identity
- three rings: system-critical or high-impact operations, including Update and
  ISO
- two rings: simple Software install/remove operations
- one ring: ordinary safe tasks and About

One-ring actions make the owner's sanitized output the main content. They have
no confirmation, percentage, progress bar, or separate log toggle. A required
sudo prompt still appears before the owner runs; an owner with no output gets
one truthful completion line. Key-value output renders as compact rows with
dim uppercase labels aligned to one column, a middle-dot separator, bold
values, and a red priority accent after a normal dash instead of raw clipped
logs. Multi-field reports use a normal dash, align continued values beneath
the value column, and keep explanatory sentences as prose after the grid. The
grid, collection markers, and prose are centered independently beneath the
title. Single-member collections omit a redundant heading; multiple members
use centered `<Name N>` section markers.

An optional executable at `task/presenters/<slug>` may normalize a one-ring
owner whose successful output is only a vague activity line. It invokes the
catalog owner exactly once, preserves failures, and prints verified readback;
it never owns the mutation.

`owner-contracts.psv` inventories every owner referenced by the fixed-task,
paired Software, and install-only catalogs, regardless of ring count or
whether the route uses the shared TUI or a native terminal. It fingerprints
each repository entrypoint and its static qvOS dependencies recursively. Run
`qv/tui/owner-contracts --check` during verification. When it reports drift,
inspect the complete owner change and re-evaluate presentation, sudo,
interaction, output, and verification before deliberately running
`qv/tui/owner-contracts --write`; never accept a changed hash as the review.
Owners declare dependencies assembled from relative or dynamic paths with
`# qvos:contract=qv/<path>`; a directory declaration includes every regular
payload file.
System owners outside the repository are explicitly classified in
`external-owners.psv`.

The future About owner will present `Abdulrahman M. Yaqyn`, website, contact,
and guides without scattering those values through shared rendering code.

## Software actions

`action/` is the shared adapter for software leaves opened from Elephant:

1. Resolve the selected owner contract and refresh paired lifecycle state at
   activation.
2. Show the selected operation with the two-ring operational model.
3. Complete non-mutating preflight. Privileged actions proceed to sudo;
   consequential unprivileged actions confirm before preflight.
4. Delegate once to the existing Omarchy or qvOS owner and map only owned
   milestones into progress.
5. Verify the paired state change or install-only result probe before rendering
   success.

The registry selects this flow only for owners that are safe captured command
streams. Installers that require an interactive prompt, authentication, or
configuration retain their native floating terminal rather than receiving
synthetic input. Both routes remain direct from the software row; neither adds
an intermediate action sheet.

State-aware leaves use `software-actions.psv` for paired Install and Uninstall
owners. Install-only selectors remain selectors and use
`software-installers.psv`; their safe leaves share the same two-ring flow and
must pass a real installed-result probe without inventing an Uninstall owner.

## Fixed tasks

`task/actions.psv` classifies non-Software desktop scripts. A stream-safe row
delegates once through the same shared action presentation with its declared
one- or three-ring role. Interactive owners remain `native`; the catalog still
records their intended tier so a later dedicated adapter can preserve prompts,
authentication, secrets, hardware interaction, and reboot choices.

One-ring task rows start immediately and print only owner information. The
adapter's synthetic progress milestones are reserved for guarded two- and
three-ring transaction flows.

Every configuration refresh is a three-ring transaction because it overwrites
user state. Its owner may create backups. An unprivileged refresh confirms
before delegation; a privileged refresh uses sudo as its only start gate.

## Update

`update/` owns the TUI-specific Update contract and thin engine adapter. The
main hub and `--update` direct mode reuse one flow:

1. Run the qvOS update owner's read-only preflight.
2. Reuse the shared sudo authorization surface as the only start gate.
3. Delegate once to `omarchy-qvos-update -y`, show known stage milestones, and
   retain all other output in the optional log view.
4. End on an explicit success or actionable failure screen.

`Ctrl+C` or `Ctrl+Z` opens a stop confirmation while the update continues in
the background. `Keep Updating` is the safe default; only explicitly choosing
`Stop Update` stops the owned process group and returns a canceled result.
Closing the Update window still stops an active update. The non-interruptible
keyboard guard remains exclusive to boot/ISO installation. If the TUI is
unavailable, `omarchy-qvos-update` retains its plain terminal confirmation and
update path. A stopped Update renders `UPDATE CANCELED`; it never presents
`100%`, `UPDATED`, or `update complete`.

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

Use arrow keys or `hjkl`, Enter to open, `v` to toggle logs, `Ctrl+V` for
terminal output, `r` to retry the fake failure session, and Escape to return
or exit. Press `F1` or `Shift+?` for the complete contextual control list.

Run the focused checks and renderer benchmarks from this directory:

```bash
go test -count=1 ./...
go test -run '^$' -bench 'Benchmark(RenderShapes|HubView)$' -benchmem
```
