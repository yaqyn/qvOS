# Windows VM Lifecycle

Read this file when changing Windows VM setup, removal, state detection, TUI
configuration, or installed runtime payloads.

- `qv/windows/manage` owns qvOS Install and Uninstall. `qv/windows/command`
  owns launch, stop, status, and help; `bin/omarchy-windows-vm` is only its
  stable public compatibility adapter. Install and Remove enter the same
  checked TUI through `qv/windows/launch`.
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
- Pass the Windows password to FreeRDP only through `/from-stdin:force`; never
  place it in arguments, output, notifications, or logs. Keep the legacy
  `omarchy-windows` container and `omarchy-windows-vm` command names until an
  explicit state-compatible internal migration owns their replacement.
- Uninstall defaults to keeping `~/.windows`. Delete it only after the explicit
  in-TUI `Delete Virtual Disk` choice. Always preserve `~/Windows`.
- Reject symlinked managed files and unsafe storage targets. Restore only the
  exact files captured by owner-state rollback, and refuse a sealed rollback
  after concurrent file changes.

Verify the form schema, private file modes, Compose allowlist, credential
transport, display scaling, absent and installed states, both uninstall scopes,
interrupted and completed Stop rollback, preserved shared files, shell checks,
owner contracts, and the full qvOS suite.
