# Windows VM Lifecycle

Read this file when changing Windows VM setup, removal, state detection, TUI
configuration, or installed runtime payloads.

- `qv/windows/manage` owns qvOS Install and Uninstall; the inherited Omarchy
  command continues to own VM launch, stop, and status. Its small guarded seam
  sends only Install and Remove through `qv/windows/launch` to the checked TUI.
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
- Uninstall defaults to keeping `~/.windows`. Delete it only after the explicit
  in-TUI `Delete Virtual Disk` choice. Always preserve `~/Windows`.
- Reject symlinked managed files and unsafe storage targets. Restore only the
  exact files captured by owner-state rollback, and refuse a sealed rollback
  after concurrent file changes.

Verify the form schema, private file modes, absent and installed states, both
uninstall scopes, interrupted and completed Stop rollback, preserved shared
files, shell checks, owner contracts, and the full qvOS suite.
