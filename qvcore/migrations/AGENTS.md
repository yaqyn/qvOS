# qvOS Migration Workflow

Read this file completely when adding migrations, changing update migration
execution, seeding a fresh install, or cleaning inherited migration state.

`qvcore/migrations/` is the only migration source. Historical top-level
Retired compatibility migrations never run: fresh qvOS installs already contain their
selected outcomes, and updates must never replay them. `qvcore/migrations/run`
executes numeric migration files in order, serializes runs, records private
atomic markers under `~/.local/state/qvos/migrations`, and fails closed without
offering a skip path. Its exact private `.lock` lives beside those markers so
fresh chroot and other headless runs never depend on a login-time runtime
directory. The runner must close its lock descriptor before entering each
migration process so restarted services cannot inherit the lock beyond the
runner lifetime. Every migration must be idempotent because a failure may occur
after partial work and the unmarked migration will run again.

Numeric owners exist only for the currently supported upgrade window. Before
the first public baseline, and whenever the supported upgrade floor advances,
remove transition files already completed by every supported installation and
prove their outcomes through fresh-install owners. The runner then deletes only
matching safe, empty, account-owned qvOS markers whose source no longer exists;
it never reads, adopts, or cleans an external migration-state tree. An empty
numeric source set is a valid compacted baseline and still retains the runner
for future public upgrades.

Fresh installation calls `run --mark-current` only through the exact
`QVOS_INSTALL` owner so current existing-system migrations are recorded without
being executed. Reject links, foreign ownership, unexpected entries, nonempty
markers, and conflicting state before mutation. Native migration names stay
numeric; historical external markers are outside this owner's state and cannot
suppress a native migration.

Use `qv dev add migration` to create a numeric `0644` source. Migration files
run in a fresh Bash process with `errexit`, unset-variable checks, and pipeline
failure enabled: they have no shebang, start with a concise `echo`, use
`$QVOS_PATH`, and keep all mutation idempotent and preservation-safe. The
inherited public commands are metadata-only adapters and never own state.
System-identity migrations call `qvcore/branding/system-identity`; they never
edit `/etc/os-release` directly or overwrite a foreign administrator identity.
Runtime-channel migrations call their native install owner, mutate only an
exact inherited setting after its replacement is available, and preserve weak,
linked, foreign, or concurrently modified user configuration.

Run `qvcore/migrations/check`, `qvos-migrations-test.sh`, install, update, boot,
product, and upstream-boundary tests, Bash syntax and ShellCheck, then the full
qvOS suite. On the live installation, run the native owner once, verify its
private current markers and removal of only obsolete safe qvOS markers, then
require development/live source parity.
