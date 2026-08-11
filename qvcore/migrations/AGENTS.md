# qvOS Migration Workflow

Read this file completely when adding migrations, changing update migration
execution, seeding a fresh install, or cleaning inherited migration state.

`qvcore/migrations/` is the only migration source. Historical top-level
Omarchy migrations are retired: fresh qvOS installs already contain their
selected outcomes, and updates must never replay them. `qvcore/migrations/run`
executes numeric migration files in order, serializes runs, records private
atomic markers under `~/.local/state/qvos/migrations`, and fails closed without
offering a skip path. Its exact private `.lock` lives beside those markers so
fresh chroot and other headless runs never depend on a login-time runtime
directory. Every migration must be idempotent because a failure may occur after
partial work and the unmarked migration will run again.

Fresh installation calls `run --mark-current` only through the exact
`QVOS_INSTALL` owner so existing-system migrations are recorded without being
executed. The runner may adopt an exact applied marker from the retired
Omarchy state, then removes the validated empty historical marker tree only
after every native migration is current. Reject links, foreign ownership,
unexpected entries, nonempty markers, and conflicting state before mutation.
Legacy cleanup accepts only empty timestamp or timestamp-plus-lowercase-slug
markers from the former Omarchy runner; native migration names stay numeric.
Tests for an exact retired runtime must use its pinned historical source, not
copy the evolving active owner and broaden a cleanup allowlist to fit it.

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
The Hyprland format transition calls `qvcore/config/migrate-hyprland-lua` and
never translates arbitrary `.conf` text. Its reviewed hash catalog, private
config and theme backups, typed replacement profiles, and theme handoff must
succeed before the Lua entrypoint is published. Retire the old main config
before its theme fragment, then re-verify before removing remaining legacy
leaves.

Run `qvcore/migrations/check`, `qvos-migrations-test.sh`, install, update, boot,
product, and upstream-boundary tests, Bash syntax and ShellCheck, then the full
qvOS suite. On the live installation, run the native owner once, verify private
markers and removal of only the validated legacy marker tree, then require
development/live source parity.
