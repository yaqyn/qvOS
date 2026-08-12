# qvOS Desktop Runtime Workflow

Read this file completely when changing desktop process reloads, user-service
restarts, session lock/logout/wake behavior, Hyprland window cleanup, radio
resets, trackpad recovery, or shared desktop launch helpers.

`qvcore/desktop/hyprland/` owns shared compositor context, validated window and
workspace mutations, focused-monitor detection, display scaling, monitor-event
recovery, and all-window closure.
`qvos-runtime-config` is the only runtime configuration bridge. It accepts a
small typed operation catalog, validates every value, and alone may pass a
constructed expression to `hyprctl eval`; callers never provide Lua or an
arbitrary expression. Its fixed window-action catalog may dispatch only a
source-owned Lua action; never translate a legacy dispatcher name at runtime.
Persistent compositor policy remains in native Lua.
`qvcore/desktop/launch/` owns default application, web-app, terminal-app, and
focus-or-launch behavior. Native launchers preserve argv boundaries, use fixed
substring window matching against fully validated Hyprland JSON, generate
`org.qvos.*` application IDs, and never parse a caller command with `eval` or a
shell. Normal custom browser desktop entries remain launchable; private mode
and app-window mode require an explicitly supported browser executable. Treat
radio unblock failure as a warning and still open its accessible controls.
`qvcore/desktop/web/url-lib` singularly owns strict HTTP and HTTPS authority
validation for both direct web-app launches and the website normalizer.
`qvcore/desktop/webapp/` owns custom Web App installation, inventory, and
removal. Fresh qvOS carries no preinstalled Web Apps, fixed web-service
shortcuts, protocol handlers, or service-specific assets. Keep only the
generic website keybinding and the on-demand installer.
Never overwrite an existing desktop entry, accept an arbitrary Exec string,
fetch an icon without explicit input, or remove a desktop file or icon without
proving its bounded native qvOS Web App marker and launch route. Historical
Omarchy launch entries are foreign user data and remain untouched. Keep
compatibility adapters thin and metadata-free.
`qvcore/desktop/applications/` singularly owns the fixed base desktop entries,
intentional package-menu suppressors, and the imv icon. Its installer validates
the complete source and destination set before mutation, serializes refreshes,
and publishes atomically with rollback. Every suppressor remains a standards-valid
`Desktop Entry` with `Type`, `Name`, and `Hidden`; do not rely on a permissive
menu parser. Record the last installed hashes in the private, atomic
`~/.local/state/qvos/desktop/applications.psv` manifest; replace only matching
prior qvOS content and fail before publication on modified, foreign, malformed,
or linked state. Completed Typora, duplicate-icon, and invalid-suppressor
convergence stays retired. Do not rewrite an exact payload. Never put a Web App,
optional application, service URL, or Windows-owned icon in this payload;
optional Web Apps exist only after an explicit user install.
`qvcore/desktop/session/` owns lock, logout, wake, the delayed logout worker,
and session-scoped Idle Lock and Nightlight toggles. Use the shared exact-process
helper for Hypridle, validate one bounded Hyprsunset temperature before changing
it, and treat notifications or an optional Waybar refresh as secondary to the
desktop mutation. `qvcore/desktop/restart/` is the singular owner for supported
runtime restart operations. Public `qv-restart-*` commands carry metadata; matching
`omarchy-restart-*` files are metadata-free compatibility adapters only.
qvOS-owned consumers call the native command or owner, never the compatibility
name. Waybar and the monitor watcher use stable qvOS UWSM units; their restart
owners stop their fixed unit and exact process before relaunching. Completed
pre-release transient-unit convergence is retired; never enumerate random
inherited UWSM scope or service patterns during a normal restart. Keep process
names exact, preserve argument boundaries, treat an absent optional process as
an idempotent success, and propagate failures from the component that must be
restored. Walker restarts act only through the invoking desktop user's manager
and refuse root execution; never serialize restart logic into a shell command
or bridge from root into a guessed user session.

Lock accepts only `QVOS_LOCK_ONLY`, validates its bounded policy, starts at most
one observed Hyprlock instance, locks 1Password only when its exact process and
command are present, closes screensaver windows through their shared owner, and dims only
while Hyprlock remains active. Historical `OMARCHY_LOCK_ONLY` is migration
input only and must not alter a native session. Logout
schedules one fixed worker before closing a prevalidated Hyprland client
inventory so cleanup failure cannot cancel the requested session exit. Never
exercise lock, logout, wake, all-window closure, or display dimming on the live
desktop merely to test routing.

Prevalidate every Hyprland JSON result, bounded geometry, monitor name, window
address, and workspace identifier before the first compositor mutation.
Focused-monitor scaling must preserve the monitor's exact placement, update
only a singular generic adaptive rule, publish that config atomically, and roll
the live scale back when persistence fails. Custom monitor layouts remain
untouched. Monitor-event recovery calls the native config owners directly;
`qvcore/config/base/hypr/autostart.lua` calls the native monitor-watch route.
Never exercise
window, workspace, or display mutations on the live desktop merely to test a
route.

`restart/process-lib` owns graceful exact-process termination with a bounded
forced fallback. Reuse it for restarts and session toggles; never copy a
TERM/wait/KILL loop. Process-aware tests must replace discovery inside their fixture. They must not
observe, signal, lock, or otherwise depend on real desktop processes belonging
to the developer session. Process inspection must tolerate a process
disappearing between discovery and `/proc` access without leaking a misleading
error.

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
unique. The inherited top-level `applications/` tree is retired; fixed desktop
sources remain source-owned here and are not generic runtime helpers.
`runtime-paths` is the exact source-independent desktop payload; never
copy policy, checks, inventories, or source-only restart owners into the user
runtime. Runtime deployment stages only that inventory and restores the prior
payload if replacement fails. Run `qvcore/desktop/check`, the focused fixed-
application, launch, Web App, restart, and session suites, CLI and TUI
owner-contract checks, Bash syntax and ShellCheck for changed shell, then the
full qvOS suite. Live verification is read-only: inspect CLI help and adapter
resolution unless the user explicitly requests an actual application, window,
radio, or session mutation.
