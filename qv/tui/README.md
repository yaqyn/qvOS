# qvOS TUI

This directory owns the qvOS terminal interface, its ISO installer surfaces,
and the ISO build entry point. The Go program is one visual shell with these
modes:

- default: qvOS Update and ISO Build
- `--prototype`: safe fake script, sudo, application, and boot sessions
- `--update`: qvOS Update preflight, authorization, progress, logs, and result
- `--action`: classified Software or fixed-task presentation; mutations use
  progress and exactly one start gate, while information runs directly after
  any required authorization
- `--iso-installer`: boot installation information and confirmation
- `--iso-progress`: one persistent installation progress and log surface
- `--iso-finished`: installation result and reboot choice

## Shared flow architecture

The TUI root owns reusable presentation and capability configuration:

- `flow.go` declares model, start confirmation, preflight, authorization, and
  progress needs
- `selection.go` owns searchable single- and multi-selection for allowlisted
  action values
- `post_action.go` owns shared post-success transitions and Reboot Now/Later
- `action/post-run` keeps long completion work in the live action stream
- `authorization.go` renders every password authorization surface
- `progress.go` renders compact and full progress for Update, Software, ISO,
  and the prototype
- `logs.go` renders the shared scrolling log panel
- `accessibility.go` owns persistent controls, Help, and terminal output
- `text.go` keeps shared copy within real terminal-cell widths

`install` deploys `qvos-tui` together with its launchers, action/task/update
adapters, task catalogs, presenters, and success guidance under
`~/.local/share/qvos/tui`. Desktop routes execute that checked runtime payload,
while adapters resolve only their delegated mutation owners from the active
`OMARCHY_PATH`. This prevents a current binary from calling stale cancellation
or presentation adapters in the live Omarchy checkout.

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

Every composition paints its complete viewport `#000000`; placement padding
is not transparent terminal whitespace. The palette stays neutral grayscale
with `#5f0000`, `#b00000`, and `#d00000` as its only chromatic tonal accents;
the reduced-color ISO console uses the normal and hot variants.

Menu titles and descriptions use catalog-wide measured columns. Descriptions
yield first when space is constrained; complete rows share one measured width
so identifiers, titles, and descriptions stay aligned.
Opening logs preserves the action panel's exact position and dimensions.
Landscape logs replace the identity/model column without changing the normal
column split. In true fullscreen, every log-capable TUI places logs in the 3D
model's exact stage slot, so progress and controls do not move. An empty
running log uses the shared `Preparing` animation instead of a waiting message.
Confirmed cancellation freezes the visible progress immediately and never
animates toward completion.
Output-only ISO progress still consumes terminal protocol replies while
ignoring key actions, preventing raw capability responses from appearing after
the log controls.
Ctrl+C or Ctrl+Z on a guarded mutation replaces the complete TUI with the stop
decision. The model, identity, progress, logs, terminal output, and Help remain
hidden until Enter explicitly confirms Keep or Stop. Pressing Ctrl+C or Ctrl+Z
again confirms Stop directly, as shown by the modal hint. Captured repository
owners resolve from the active `OMARCHY_PATH` and use their own process group
inside the TUI terminal session, preserving the sudo authorization ticket.
Captured commands reject interactive Gum subcommands while retaining safe Gum
formatting, so a stale or unreviewed prompt fails instead of suspending the
action. Confirmed Stop interrupts transactional owners cleanly and then
force-reaps that complete owned process group before rendering a result.
External terminal closure drains the same stop path. Captured installs do not
launch detached applications; the success guidance tells the user where to
continue.
The result probes the route's declared state and reports whether the target was
reached before Stop or could not be detected. It never runs a generic
Uninstall: rollback requires an owner that can prove exact restoration without
deleting pre-existing packages, configuration, or user data.
`action/rollbacks.psv` opts reviewed owners into the `owner-state-v1` protocol.
Those owners snapshot their exact state before delegation, seal the completed
result, reject concurrent drift, and restore that state before generic package
cleanup. A failed owner restoration retains any package needed by the changed
configuration and reports it instead of creating a broken partial rollback.
Installed inactive fonts offer `Apply Now` and `Uninstall`. The active font
shows `Already Applied` with only `Uninstall`; the status is not selectable.
Apply starts immediately without Stop plumbing. Uninstall moves directly to
authorization and restores JetBrains Mono before removing an active font
package. Generic non-install mutations do not expose or react to
`Ctrl+C`/`Ctrl+Z` while running.

Menu surfaces remain name-only navigation for TUI-managed lifecycle items.
They pass the selected slug to the checked TUI; availability, current/default
status, action choices, authorization, progress, and results stay inside the
TUI.
Terminals are state-aware: missing terminals use Install with exact owner
rollback, installed non-default terminals use an unprivileged `Make Default`
confirmation, and the current default opens direct `Already default`
information.
If the canceled process group contained Pacman, the TUI removes `db.lck` only
when the lock did not exist before that action, no package manager remains, and
the lock is still the expected empty root-owned file. Every pre-existing or
unverified lock is preserved and reported for inspection.
Captured installs also snapshot installed Pacman package names and versions, every
configured Pacman cache, new `yay`/`paru` build trees, mise install/download
paths, the global mise config and lockfile, and Mix/Hex state. Stop removes
only the exact package names and entries created by that attempt, removes new
empty runtime roots, restores changed mise files atomically, and reshims. The
sudo ticket and manager observation remain active while a completed install is
waiting behind the Stop decision. Pre-existing or concurrently modified
packages, caches, runtimes, configuration, symlinks, and uncertain paths are
preserved and reported instead of being silently called clean. Update and ISO
Build retain their dedicated Stop contracts; removal and general task actions
carry no unused Stop or rollback machinery.
Non-mobile progress views keep the active operation, real milestone, percentage,
and a visible loading bar.
The smallest progress view keeps the active operation, static dimmed dot, and
percentage instead of collapsing to an unexplained number.
Compact completion keeps the semantic result (`UPDATED`, `INSTALLED`, and so
on) instead of replacing it with `100%` or a generic `DONE`.
Verified captured installs also show one quiet, wrapped next step from
`success-guidance.psv`, such as the command, setup screen, or application that
makes the new capability usable. Guidance never names a key binding because
bindings change independently from the completed lifecycle. Self-contained tasks,
removals, information, failures, and cancellations do not receive filler copy.
Failures use one calm shared result with `COULD NOT COMPLETE`, a complete
wrapped explanation, and retry or return controls. They never reuse progress,
percentages, rails, all-red styling, or truncated error copy.
Confirmation choices use one quiet marker instead of framed terminal buttons.
Short transitions before sudo or the first owned milestone use only the shared
four-step `Preparing` dot animation, never internal status flashes.
When a model is visible during an action, its identity places the action name
directly beneath `qvOS`; authorization keeps only the generic `Auth Required`
title in the action panel. Long action summaries wrap into independently
centered lines without truncation.
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
screen's primary action while work is running. Completed, stopped, and failed
results with captured output retain both keys without adding another persistent
hint; F1 Help remains the discoverable reference. The reboot-required choice
and final ISO reboot screen preserve the same route. The terminal view never
spawns a second terminal or duplicates the running action.
Internal `qvOS action:` milestones still drive progress but never appear in
either log view or copied history. Those surfaces retain only real owner
output.

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

Ring count chooses the visual model, not the workflow. Read-only
`information` actions make the owner's sanitized output the main content and
have no confirmation, percentage, progress bar, or separate log toggle. A
required sudo prompt still appears before the owner runs; an owner with no
output gets one truthful completion line. State-changing `mutation` actions
use an Action/Cancel confirmation when unprivileged and use sudo as their only
start gate when privileged, even when their visual role is one ring.

Information key-value output renders as compact rows with dim uppercase labels
aligned to one column, a middle-dot separator, bold values, and a red priority
accent after a normal dash instead of raw clipped logs. Multi-field reports use
a normal dash, align continued values beneath the value column, and keep
explanatory sentences as prose after the grid. The grid, collection markers,
and prose are centered independently beneath the title. Single-member
collections omit a redundant heading; multiple members use centered `<Name N>`
section markers.

An optional executable at `task/presenters/<slug>` may normalize an owner whose
successful output is only a vague activity line. It invokes the
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
6. When the owner reports that reboot is required, replace ordinary completion
   with the shared safe-default Reboot Now/Later result.

The registry selects this flow only for owners that are safe captured command
streams. Installers with a bounded `owner-json-v1` schema use the shared form
stage and receive values through a private captured-runtime file. Owners with
unresolved authentication, hardware interaction, or a nested TUI retain their
native floating terminal rather than receiving synthetic input. Both routes
remain direct from the software row; neither adds an intermediate action sheet.

State-aware leaves use `software-actions.psv` for paired Install and Uninstall
owners. Install-only selectors remain selectors and use
`software-installers.psv`; their safe leaves share the same two-ring flow and
must pass a real installed-result probe without inventing an Uninstall owner.
`action/choices.psv` adds owner-backed scope choices before authorization when
one lifecycle action has materially different effects. The first choice is the
safe default, and the authorization summary follows the selected scope.
`action/forms.psv` opts a bounded owner into the shared form before
authorization. Text, password, bounded number, and finite select fields share
one validator and renderer; secrets never appear in arguments, logs, or a
process-wide value.
`action/post-actions.psv` may give a verified Install result one owner-backed
primary action. Enter runs that action; Escape still returns without it. The
shared `action/post-run` keeps long completion work in the same live output and
Stop flow. `action/launch --post-success` resumes a configured but unfinished
completion phase with that action's own copy and retry instead of reopening
Install.

## Fixed tasks

`task/actions.psv` classifies non-Software desktop scripts. A stream-safe row
delegates once through the same shared action presentation with its declared
ring role and explicit `information` or `mutation` behavior. Interactive owners
remain `native`; the catalog still records their intended tier and behavior so
a later dedicated adapter can preserve prompts, authentication, secrets,
hardware interaction, and reboot choices.

Information task rows start immediately and print only owner information.
Mutation rows use the required start gate and transaction milestones regardless
of ring count.

`task/selections.psv` gives selected tasks a searchable single- or multi-choice
stage. Required selections come before authorization; unprivileged mutations
then continue to the Action/Cancel gate. Options come from the owner’s
read-only `--list` mode, and selected values return after `--`; the TUI never
types into a nested prompt. The selector centers its empty `search` placeholder,
then left-aligns an entered query with the option labels. It uses the available
panel width for names and shows up to six rows in a roomy landscape view.
Filtering preserves that viewport so the title, search row, and persistent
controls stay anchored. An empty owner inventory shows the catalog’s quiet
empty-state sentence and returns without entering a mutation result state.
The compact `•` cursor marks the active row. Space remains normal search input,
while Tab toggles items in a multi-selection list. Enter continues with every
toggled item, or uses the current row directly when none were toggled.

Every configuration refresh is a three-ring transaction because it overwrites
user state. Its owner may create backups. An unprivileged refresh confirms
before delegation; a privileged refresh uses sudo as its only start gate.

## Update

`update/` owns the TUI-specific Update contract and thin engine adapter. The
main hub and `--update` direct mode reuse one flow:

1. Run the qvOS update owner's read-only preflight.
2. Reuse the shared sudo authorization surface as the only start gate. It uses
   the generic `Auth Required` title and places the dimmed, unlabeled action
   summary beneath the password rail.
3. Delegate once to `omarchy-qvos-update -y`, show known stage milestones, and
   retain all other output in the optional log view.
4. Defer inherited kernel, Hyprland, and reboot-required prompts to the shared
   post-success Reboot Now/Later screen.
5. End on an explicit success, reboot decision, or actionable failure screen.

`Ctrl+C` or `Ctrl+Z` opens a stop confirmation while the update continues in
the background. `Keep Updating` is the safe default; only explicitly choosing
`Stop Update` stops the owned process group and returns a canceled result.
Closing the Update window drains the same active-update stop path. The
non-interruptible
keyboard guard remains exclusive to boot/ISO installation. If the TUI is
unavailable, `omarchy-qvos-update` retains its plain terminal confirmation and
update path. A stopped Update renders `UPDATE STOPPED`; it never presents
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
