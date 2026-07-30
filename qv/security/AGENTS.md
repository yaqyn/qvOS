# qvOS Security Audit And Hardening Workflow

Read this file completely when auditing qvOS security, interpreting Lynis,
changing a security default, or planning a hardening batch.

`qv/security/lynis-audit` is the baseline runner. It preserves LinUtil's full
live Lynis output and saves private report copies under
`${XDG_STATE_HOME:-$HOME/.local/state}/qvos/security/lynis/`. Reports contain
system inventory: never commit, upload, or quote private contents.

`qv/security/60-qvos-security.conf` is the small default hardening baseline.
It may protect common local boundaries without disabling user capabilities.
Keep root debugging, hot-loadable modules, emergency SysRq, routing and
hotspots, removable storage, compilers, and developer tooling available unless
a concrete qvOS threat and explicit user approval justify a narrower system.
`qv/security/install` also removes group and other write access from root-owned
regular files under `/usr/install`. System package code must not remain
writable by unprivileged users, and the reconciliation must run after package
updates without following symlinks or changing files outside that tree.
The same installer requires trusted signatures for packages from the Omarchy
repository while leaving its unsigned database optional. Reject ambiguous
repository configuration instead of weakening global policy or changing other
repositories.
Docker publishes to loopback by default. This is a base network boundary, not
Supabase ownership: never install, enroll, or require Supabase from the
security owner. `omarchy qvos dev-share` may temporarily proxy one existing
localhost frontend and the current project's configured Supabase API port to
one private IPv4 interface. It must never auto-share the database, Studio,
mail, analytics, wildcard addresses, public addresses, or more than two ports.
Keep its firewall rule runtime-only, subnet-scoped, process-bound, and
automatically expiring.

1. Inspect the current source, worktree, installed state, and prior report,
   then run `qv/security/lynis-audit` before changing anything.
2. Classify each result as an actionable qvOS issue, a user-choice tradeoff, a
   desktop-inapplicable baseline, a false positive, or an upstream limitation.
   Verify the real owner and runtime state before deciding.
3. Fix small coherent groups at their qvOS or upstream owner. Prefer reversible
   defaults, targeted protection, and detection over blanket restriction.
4. Run focused functional, security, performance, and lifecycle checks after
   each group. Re-run Lynis to measure the result, not to maximize its score.
5. Keep a concise ledger of the finding, evidence, decision, change, user
   impact, verification, and remaining risk.

The Lynis hardening index is evidence, not a target. Do not disable normal
desktop hardware, networking, printing, gaming, development tools, compilers,
or user workflows merely to remove suggestions. Server controls such as legal
banners, password expiry, remote logging, process accounting, and blanket
service confinement require a relevant qvOS threat before adoption.

Ask before changes to Secure Boot, disk encryption, kernel LSMs or command
line, authentication, privilege, accounts, firewall exposure, remote access,
package removal, or persistent services. Stop if a proposed control would make
ordinary qvOS use meaningfully slower, less compatible, or more restrictive
without a concrete risk reduction.

Run `bash -n` and ShellCheck on changed shell, then
`test/qvos/qvos-security-audit-test.sh`. Re-run the full qvOS shell suite when
package policy, install/update wiring, shared security defaults, or root
instructions change. After baseline changes, verify the installed file and
effective values directly before rerunning Lynis.
