# qvOS Desktop Runtime Workflow

Read this file completely when changing desktop process reloads, user-service
restarts, session lock/logout/wake behavior, Hyprland window cleanup, radio
resets, trackpad recovery, or shared desktop launch helpers.

`qvcore/desktop/hyprland/` owns shared compositor context such as
focused-monitor detection and validated all-window closure.
`qvcore/desktop/session/` owns lock, logout, wake, and the delayed logout
worker. `qvcore/desktop/restart/` is the singular owner for supported runtime restart
operations. Public `qv-restart-*` commands carry metadata; matching
`omarchy-restart-*` files are metadata-free compatibility adapters only.
qvOS-owned consumers call the native command or owner, never the compatibility
name. Keep process names exact, preserve argument boundaries, treat an absent
optional process as an idempotent success, and propagate failures from the
component that must be restored.

Lock validates its bounded lock-only policy, starts at most one observed
Hyprlock instance, locks 1Password only when its exact process and command are
present, closes screensaver windows through their shared owner, and dims only
while Hyprlock remains active. Preserve `OMARCHY_LOCK_ONLY` only as an external
environment compatibility input; native config uses `QVOS_LOCK_ONLY`. Logout
schedules one fixed worker before closing a prevalidated Hyprland client
inventory so cleanup failure cannot cancel the requested session exit. Never
exercise lock, logout, wake, all-window closure, or display dimming on the live
desktop merely to test routing.

Prefer graceful process termination before a bounded forced fallback. User
services stay in the invoking user's systemd manager. Privileged hardware
recovery must minimize sudo, restore an unbound device after interruption or
failure, and report when no supported device was found instead of claiming a
restart. Never exercise radio, audio, trackpad, or session mutations on the
live installation merely to test an adapter.

All exact-name process signaling uses `restart/process-lib`. It scopes matches
to the effective user, excludes the calling owner, revalidates `/proc` before
each signal, and treats a vanished or reused PID as success. Never use raw
`pkill` or `killall` in a restart owner: a Bash script whose basename matches
the target can otherwise signal itself.

List every promoted inherited restart path in `native-paths`, sorted and
unique. `runtime-paths` is the exact source-independent desktop payload; never
copy policy, checks, inventories, or source-only restart owners into the user
runtime. Runtime deployment stages only that inventory and restores the prior
payload if replacement fails. Run `qvcore/desktop/check`, the focused restart
and session suites, CLI and TUI
owner-contract checks, Bash syntax and ShellCheck for changed shell, then the
full qvOS suite. Live verification is read-only: inspect CLI help and adapter
resolution unless the user explicitly requests the actual session mutation.
