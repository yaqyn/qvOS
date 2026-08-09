# Windows VM Lifecycle

Read this file when changing Windows VM setup, removal, state detection, TUI
configuration, or installed runtime payloads.

- `qvcore/windows/manage` owns qvOS Install and Uninstall. `qvcore/windows/command`
  owns launch, stop, status, and help. `bin/qv-windows-vm` carries the one
  metadata record and native `qv windows` route; `bin/omarchy-windows-vm` is a
  metadata-free compatibility adapter. Install and Remove enter the same
  checked TUI through `qvcore/windows/launch`.
- Windows owners run from the installed qvOS source. Do not duplicate the
  source tree under `~/.local/lib/qvos/windows`; only generated user state and
  the shared TUI runtime belong outside the source checkout. The Windows icon
  is owned beside these sources at `qvcore/windows/windows.png`; never stage it
  through a general fixed-application icon tree.
- Collect resources and credentials through the shared owner-form contract
  before sudo. Pass values only through the TUI's private `0600` form file,
  write the Compose file as `0600`, and never print credentials.
- Install configures the VM but never starts its image download. This keeps
  Stop exactly reversible and leaves first launch responsible for downloading
  and starting Windows.
- After verified Install, the shared completion action may call the owner's
  `--qvos-post-success` route. Escape returns without starting the image
  download. Enter treats first launch as the second Install phase: keep it in
  the same TUI, expose the real Docker and Windows download stream immediately,
  and keep Ctrl+C/Z Stop active. Stop must remove only the container, image,
  and VM-storage data absent from the pre-launch snapshot while preserving the
  configuration, prior image/storage state, and `~/Windows`. Keep the TUI owner
  attached through the real Compose pull and container preparation stream.
  Only after the container reports Windows ready may it hand the running VM to
  the inherited desktop/RDP owner, complete the TUI, and close Stop.
  When this phase fails or is interrupted after configuration remains, reopen
  it through the shared post-success resume route. Its title, retry, logs, and
  Stop belong to Launch Windows; never send the user through Install or the
  configuration form again.
- Before Docker receives a Compose file, require the exact qvOS-generated
  service shape, localhost-only ports, expected devices and capability, owned
  regular paths, and private `0600` credentials. Refuse extensions and
  symlinks rather than trying to interpret arbitrary YAML.
- `qvcore/windows/lib` singularly owns that Compose parser. Active Compose and
  Docker state use `qvos-windows`. `qvcore/windows/reconcile` is the only
  legacy-identity migration owner: validate the full generated profile before
  Docker, refuse conflicting containers, stage and back up both files, rename
  an existing exact `omarchy-windows` container without recreating it, publish
  atomically, and roll back on failure. When Docker cannot be inspected, defer
  the identity migration without changing either file. Desktop installation
  invokes this absent-safe reconciliation; no fresh install creates legacy
  identity.
- Pass the Windows password to FreeRDP only through `/from-stdin:force`; never
  place it in arguments, output, notifications, or logs.
- Uninstall defaults to keeping `~/.windows`. Delete it only after the explicit
  in-TUI `Delete Virtual Disk` choice. Always preserve `~/Windows`.
- Reject symlinked managed files and unsafe storage targets. Restore only the
  exact files captured by owner-state rollback, and refuse a sealed rollback
  after concurrent file changes.

List the promoted command in sorted `native-paths`. Run `qvcore/windows/check`
and verify the form schema, private file modes, Compose allowlist, credential
transport, display scaling, absent and installed states, both uninstall scopes,
interrupted and completed Stop rollback, state-compatible identity migration,
deferred and conflict paths, preserved shared files, shell checks, CLI and
upstream-overlay guards, owner contracts, and the full qvOS suite.
