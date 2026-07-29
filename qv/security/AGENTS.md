# qvOS Security Audit And Hardening Workflow

Read this file completely when auditing qvOS security, interpreting Lynis,
changing a security default, or planning a hardening batch.

`qv/security/lynis-audit` is the baseline runner. It preserves LinUtil's full
live Lynis output and saves private report copies under
`${XDG_STATE_HOME:-$HOME/.local/state}/qvos/security/lynis/`. Reports contain
system inventory: never commit, upload, or quote private contents.

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
instructions change.
