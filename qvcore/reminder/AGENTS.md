# qvOS Reminder Workflow

Read this file completely when changing desktop reminders, their transient
systemd units, runtime message state, or reminder menu and binding consumers.

`qvcore/reminder/` owns reminders. New units use `qvos-reminder-*`; private
ephemeral messages live only under `$XDG_RUNTIME_DIR/qvos/reminders`. The
matching `omarchy-reminder` command is a metadata-free compatibility adapter.

- Accept only a whole number from 1 minute through 1 year and one printable
  message of at most 512 characters. Keep message text in private runtime
  state and out of transient-unit argv; never treat it as shell source.
- Require an absolute, user-owned, non-link runtime directory. Never fall back
  to shared `/tmp`, follow links, or accept foreign state.
- Create collision-resistant transient units and private message files. If
  scheduling fails, remove only the exact new message file.
- A scheduled notification revalidates and reads its exact private file, then
  removes that state even if desktop notification delivery fails. Clearing
  stops only validated pending reminder timers and preserves state on a stop
  failure plus unrelated runtime entries.

Run `qvcore/reminder/check`, `qvos-reminder-test.sh`, menu, binding, CLI,
product, upstream-overlay, Bash syntax, ShellCheck, and the full qvOS suite.
Live verification is read-only unless the user has requested a real reminder;
use fixture units and notifications for behavior tests.
