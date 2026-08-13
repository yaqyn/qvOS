# qvOS Security Audit And Hardening Workflow

Read this file completely when auditing qvOS security, interpreting Lynis,
changing a security default, or planning a hardening batch.

`qvcore/security/lynis-audit` is the baseline runner. It preserves LinUtil's full
live Lynis output and saves private report copies under
`${XDG_STATE_HOME:-$HOME/.local/state}/qvos/security/lynis/`. Reports contain
system inventory: never commit, upload, or quote private contents.
Lynis remains an explicit operator-installed audit tool, not a qvOS base
package; the minimal base carries `arch-audit` for native package-vulnerability
checks. Tests for the absolute privileged Lynis route must remain hermetic on a
clean system where `/usr/bin/lynis` is correctly absent.
Lynis does not currently follow qvOS's `ID_LIKE=arch`, so its root helper must
validate the root-owned native `ID=qvos` identity and package-owned
`/usr/lib/os-release` `ID=arch` identity, then expose the latter only inside a
private mount namespace for the audit subprocess. Never rewrite, replace, or
temporarily modify the host's `/etc/os-release`; fail closed when either
identity is missing, writable, linked, ambiguous, or inconsistent.
`qvcore/security/debug` owns local system diagnostics. Public `qv-debug`
metadata and its exact metadata-free Omarchy adapter share that owner. Keep its
temporary directory and saved files private, bound journal and total output,
remove terminal control bytes, label non-repository packages truthfully as
foreign, report installed rather than available package versions, and never
upload. Kernel logs require sudo unless the user explicitly chooses
`--no-sudo`; `--print` is an explicit local disclosure. Interactive saves
publish atomically under a unique qvOS filename in the chosen current
directory and never overwrite an existing path. qvOS has no diagnostic upload
service.

`qvcore/security/60-qvos-security.conf` is the small default hardening baseline.
It may protect common local boundaries without disabling user capabilities.
Keep root debugging, hot-loadable modules, emergency SysRq, routing and
hotspots, removable storage, compilers, and developer tooling available unless
a concrete qvOS threat and explicit user approval justify a narrower system.
`qvcore/security/boot-mount` protects the vfat EFI system partition with root-only
file and directory masks. Change only one unambiguous `/boot` fstab entry,
preserve a private backup, reload systemd's mount definitions, and verify the
generated unit immediately. FAT permission masks are fixed for the lifetime of
the mount: never unmount or pretend to remount the running EFI partition to
activate them. Report that a reboot is required when the live mount still has
the prior masks, and restore and reload the prior fstab policy if generation
fails. A successful policy change retains its one private recovery file; a
failed change removes that transaction's backup only after the prior fstab has
been restored. Boot owners must use privileged reads for EFI payloads after
this boundary is active.
During the reviewed ISO chroot, persist the validated fstab policy but do not
query the live ISO's systemd generator, apply sysctls to its shared kernel, or
restart its services. The installed system activates those persistent defaults
on first boot; live-system reconciliation keeps immediate reload and rollback.
`qvcore/security/install` also removes group and other write access from root-owned
regular files under `/usr/install`. System package code must not remain
writable by unprivileged users, and the reconciliation must run after package
updates without following symlinks or changing files outside that tree.
The same installer requires trusted signatures for packages from the Omarchy
repository while leaving its unsigned database optional. Reject ambiguous
repository configuration instead of weakening global policy or changing other
repositories. During an ISO chroot install, defer only the exact temporary
signed `[offline]` mirror contract at
`file:///var/cache/qvos/mirror/offline/`; its packages use
`Required DatabaseOptional`, never `TrustAll`. The inherited Pacman
post-install step must then
run first, followed immediately by `qvcore/security/install`, so the final
`[omarchy]` repository is hardened before reboot is allowed.
`docker-policy` singularly owns the Docker daemon and resolver configuration.
It validates the daemon configuration with Docker, preserves unrelated secure
administrator keys, enforces loopback-only default publishing, and publishes
the tracked resolver drop-in atomically. It refuses unsafe or modified managed
paths and rolls back a failed live activation. The installer Docker stage only
delegates policy, enables the on-demand socket, and enrolls the desktop account
in the existing Docker access model; do not restore a Docker service ordering
override. Target-chroot policy persists without restarting the builder's
services. Changing Docker-group access is a separate privilege-model decision.
This is a base network boundary, not Supabase ownership: never install, enroll,
or require Supabase from the security owner. `qv dev share` may temporarily
proxy one existing localhost frontend and the current project's configured
Supabase API port to one private IPv4 interface. It must never auto-share the
database, Studio, mail, analytics, wildcard addresses, public addresses, or
more than two ports.
Keep its firewall rule runtime-only, subnet-scoped, process-bound, and
automatically expiring.

qvOS does not expose broad passwordless sudo. The inherited timed toggle was
unsafe across reboot because its `/etc/sudoers.d` rule outlived its transient
timer. The inherited wheel-wide timezone rule was also unnecessary because the
native timezone flow already requests sudo normally. `retire-passwordless-sudo`
preflights every candidate, removes only exact root-owned legacy rules as one
bounded transaction, and refuses modified lookalikes; package workflows use
their scoped native credential refresh helper instead. Native security owners
resolve source only through `QVOS_PATH`.
The inherited `sudo-reset` route is also retired: it interpolated account state
into a root shell command and depended on a separately usable root password.
Authentication lockout recovery belongs to an explicit recovery environment,
not a normal-session product command.

`login-policy` is the sole qvOS owner of ordinary password-attempt defaults.
It runs only from its root-owned installed copy, appends one exact marked block
to the package-provided `faillock.conf`, and installs one `visudo`-validated
root-owned fragment allowing ten sudo password attempts. Keep package-owned
PAM stacks unchanged. Refuse active administrator-owned faillock thresholds,
modified qvOS markers, unsafe paths, or foreign sudoers content; publish both
files transactionally and preserve their inodes on an idempotent rerun.

Keep `.gitleaksignore` narrow and reviewable. A retired public identifier may
retain only a commit-pinned historical exception; never keep an unqualified
current-path exception after its owner is removed, because that can hide a
future secret at the reused path.

Fingerprint and FIDO2 remain explicit optional capabilities. Their public `qv`
adapters delegate to `auth`; matching Omarchy adapters are metadata-free ABI
only. `auth-policy` is installed root-owned under `/usr/lib/qvos/security/` and
is the sole owner of marked PAM blocks, private FIDO2 credentials, and root
intent under `/var/lib/qvos/security/auth`. Never edit package-managed PAM files
from a user-writable script, stage credentials in shared `/tmp`, create a new
polkit PAM stack, remove unowned packages, or delete an administrator-owned
FIDO2 directory. PAM updates must preserve unowned content, refuse modified
qvOS blocks, serialize, publish atomically, and roll back as one transaction.
The security installer reconciles enabled intent after package updates.

`qv-dev-share` is the only metadata-bearing LAN-preview adapter. The former
`omarchy-qvos-dev-share` qvOS-in-Omarchy namespace is retired and must remain
absent; `omarchy-dev-share` is its metadata-free matching compatibility
adapter, and the compatibility CLI frontend still discovers the native route
through the shared command engine.

1. Inspect the current source, worktree, installed state, and prior report,
   then run `qvcore/security/lynis-audit` before changing anything.
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
`test/qvcore/qvos-login-policy-test.sh` and
`test/qvcore/qvos-security-audit-test.sh`. Re-run the full qvOS shell suite when
package policy, install/update wiring, shared security defaults, or root
instructions change. After baseline changes, verify the installed file and
effective values directly before rerunning Lynis.
