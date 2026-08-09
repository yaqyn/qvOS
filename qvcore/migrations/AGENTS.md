# qvOS Migration Workflow

Read this file completely when adding migrations, changing update migration
execution, seeding a fresh install, or cleaning inherited migration state.

`qvcore/migrations/` is the only migration source. Historical top-level
Omarchy migrations are retired: fresh qvOS installs already contain their
selected outcomes, and updates must never replay them. `qvcore/migrations/run`
executes numeric migration files in order, serializes runs, records private
atomic markers under `~/.local/state/qvos/migrations`, and fails closed without
offering a skip path. Every migration must be idempotent because a failure may
occur after partial work and the unmarked migration will run again.

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

Run `qvcore/migrations/check`, `qvos-migrations-test.sh`, install, update, boot,
product, and upstream-boundary tests, Bash syntax and ShellCheck, then the full
qvOS suite. On the live installation, run the native owner once, verify private
markers and removal of only the validated legacy marker tree, then require
development/live source parity.
