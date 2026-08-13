# qvOS Update Workflow

Read this file completely when changing qvOS source updates, the public update
wrapper, update stages, update failure handling, or reboot handoff.

`qvcore/update/source-check` singularly validates the resolved checkout,
OS branch, cleanliness, and official qvOS origin. Product preflight, source
update, and availability checks all call it; mutation paths recheck immediately
before use to close time-of-check gaps.

`qvcore/update/update-source` owns source synchronization. The public inherited
command is a thin compatibility adapter. Native update owners resolve source
only through `QVOS_PATH` and never propagate `OMARCHY_PATH`. Require a clean
non-symbolic checkout on branch `OS`, accept only the official qvOS origin, and
pull `origin/OS` with fast-forward-only semantics and bounded network time.
Never autostash, reset, merge another branch, or conceal source changes.
qvOS has one installed source channel: official `origin/OS`. The inherited
branch and channel switchers are retired; experimental upstream refs belong in
separate development checkouts and never mutate the installed OS.

`qvcore/update/qvos-update` owns product preflight and presentation, then delegates
once to `qvcore/update/run`. Its read-only check must reject a dirty or non-OS
live checkout before authorization. It also requires the root-owned base Go
toolchain before source mutation, because an unseen fast-forward may change the
compiled TUI and post-update reconciliation must never mix that source with an
older binary or adapter payload. `qv update` is the native public route;
matching inherited public routes are metadata-free compatibility adapters only,
while raw internal stage commands are retired.

`run` serializes the complete transaction, writes its PTY output only to the
private fixed qvOS state log, creates an optional pre-update snapshot, updates
source, then delegates once to `perform`. Reject links, foreign ownership, and
caller-selected log paths. The TUI may capture the same pipeline once but must
use the same log owner and qvOS environment names. Never restore a predictable
`/tmp` log or a second update engine. Suppress compositor config errors before
the source changes and retain the already-loaded settings through migrations
and post-update reconciliation. Restore error reporting on every exit, reload
only after complete success, and never reload a newly pulled source before its
replacement configuration has been published.

`perform` owns stage ordering only. Package mutation belongs to
`qvcore/packages/`, migration to `qvcore/migrations/run`, and post-update hooks
to their hook owner. Any no-idle tag must be removed through an EXIT trap after
success, failure, or interruption. Initramfs log analysis fails closed before
restart when success cannot be proven.

`update-available` aggregates two independent read-only owners so package
security updates remain visible even when qvOS source is current.
`source-available` compares the installed commit with the official remote OS
head using bounded network time. Equal and provably locally-ahead source are
current. When the remote SHA differs, fetch it into one process-private ref,
delete that ref on exit, and offer an update only when the installed commit is
its ancestor. Fail closed on divergent or unpublished shallow history because
the fast-forward-only updater cannot reconcile it. Tags are not the release or
availability authority. One failed probe must not conceal a positively proven
update from the other owner; when neither proves an update, any probe failure
fails the aggregate check closed.

`snapshot`, `time-sync`, and `firmware` are native qvOS owners. Snapshot config
names are validated and descriptions consume the singular commit-derived qvOS
version owner; time sync verifies the service after restarting it; and firmware
installation delegates package installation to the native package owner.
Never invoke these mutations during source-only verification.

`qvcore/migrations/run` is the update pipeline's only migration engine. It reads
only native numeric owners, serializes runs, keeps private atomic qvOS markers,
prunes only safe empty markers for retired native owners, and stops the update
on failure without allowing a skip. Update paths call the owner directly;
`qv migrate` is the native frontend and `omarchy-migrate` is a metadata-free
compatibility frontend to that same engine. No path may read or replay an
Omarchy migration tree or state root.

`qvcore/update/state` owns only `reboot-required` and validated
`restart-<service>-required` markers under the private qvOS update-state
directory. It accepts the separately owned regular `0600` `update.log` in that
shared private directory without reading, changing, or deleting it. It
atomically records markers and serializes changes. Reject arbitrary names,
contents, links, and foreign ownership. Completed pre-release marker migration
is retired; the owner neither scans nor recreates an inherited state root.
`restart` clears a service marker only after its exact restart command succeeds.

`qvcore/update/restart` singularly detects post-update reboot and service-restart
requirements. Use only package-owned kernel images, inspect one running
Hyprland process safely, accept only exact restart-marker service slugs, and
clear each marker only after its restart owner succeeds. Delegate every reboot
choice to `qvcore/update/reboot-request`; never restore an inherited fallback.
Reboot deferral accepts only `QVOS_UPDATE_DEFER_REBOOT`; inherited environment
names must not alter a native update transaction.
`analyze-log` also recognizes completed Pacman upgrade, downgrade, or reinstall
lines for Walker and Elephant and records `restart-walker-required` through the
private state owner. This replaces the retired root Pacman hook; keep matching
bounded to package tokens so unrelated log text cannot create restart state.

Run `qvcore/update/check`, `qvcore/packages/check`, Bash syntax, ShellCheck, the focused update and source
lifecycle tests, and the full qvOS suite. A source-only audit must not invoke
the interactive updater or package upgrades. Live verification requires a
clean checkout and exact development/live commit parity.
