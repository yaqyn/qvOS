# qvOS Share Workflow

Read this file completely when changing LocalSend routing, clipboard staging,
file selection, transient sharing, or cleanup.

`qvcore/share/share` is the only LocalSend mutation owner. `qv-share` is the
native command and `omarchy-share` is its metadata-free compatibility adapter.
Former nonmatching `omarchy-menu-share` and `omarchy-qvos-share` routes are
retired; do not recreate duplicate Share frontends.

- Preserve exact argument boundaries and validate selected file or directory
  types before launching LocalSend.
- Stage clipboard data only in the private user runtime directory. The
  detached sender owns deletion after LocalSend exits; failures must not leave
  a public or persistent clipboard copy.
- Keep sharing explicit and outbound. Do not open another listener or firewall
  rule here; base LocalSend network policy has its own installer owner.

Run Bash syntax, ShellCheck, the focused share and menu tests, CLI and product
contracts, and the full qvOS suite. Use fixture commands instead of sending
real user data during tests.
