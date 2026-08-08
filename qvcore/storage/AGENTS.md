# qvOS Storage Workflow

Read this file completely when changing drive discovery, drive selection, or
the interactive LUKS passphrase lifecycle under `qvcore/storage/`.

`info` owns bounded drive presentation, `select` owns interactive selection,
and `password` owns LUKS-device discovery and delegates exactly one key change.
Native `qv-drive-*` commands own metadata; their Omarchy names are metadata-free
compatibility adapters. Keep command implementations out of `bin/`.

Canonicalize production device paths beneath `/dev`, require a real block
device recognized by `lsblk`, reject control characters and traversal, and
sanitize hardware strings before terminal output. Preserve newline-separated
drive-list input only for the established shell compatibility caller. Selection
cancellation exits `130`, and a selected LUKS device must be revalidated
immediately before invoking Cryptsetup.

Keep passphrases inside Cryptsetup's interactive TTY. Never accept them through
arguments, files, environment, clipboard, logs, or a captured TUI. Use the
format-compatible Cryptsetup defaults and require new-passphrase verification;
do not force a LUKS2-only PBKDF onto arbitrary user drives. The unprivileged
owner performs selection first and invokes only the absolute Cryptsetup path
through sudo. Never run the live key-change operation for source verification.

Fixture tools require `QVOS_STORAGE_TESTING=1` and a caller-owned, non-linked
tool directory beneath `/tmp`. Run `qvcore/storage/check`, the focused storage,
menu, TUI-owner, CLI, product, and upstream-overlay tests, Bash syntax,
ShellCheck, and the full qvOS suite when shared routing changes.
