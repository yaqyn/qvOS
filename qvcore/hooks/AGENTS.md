# qvOS Hooks Workflow

Read this file completely when changing custom automation hooks, hook
installation, sample reconciliation, or a native hook consumer.

`qvcore/hooks/` owns custom hooks under `~/.config/qvos/hooks`. Native
consumers use `qv-hook` and `qv-hook-install`; matching `omarchy-hook*` names
are metadata-free compatibility adapters only.

- Hook event names and installed filenames are bounded allowlisted path
  components. Reject links, foreign ownership, unsupported objects, ambiguous
  roots, and conflicting destinations.
- Run the optional main hook first, then regular files in its `.d` directory
  in bytewise filename order. Ignore `.sample` files, continue after a hook
  failure, and return failure truthfully after every eligible hook ran.
- Installation is private, atomic, idempotent for identical content, uses a
  same-directory no-clobber link, and never overwrites an existing hook.
- `reconcile` validates or creates the private native tree and installs only
  missing current samples. Every existing regular user-owned sample and custom
  hook is user content and must be preserved. Completed pre-release legacy-root
  adoption, generated-job cleanup, historical sample upgrades, and autostart
  rewriting are retired; current reconciliation never scans historical roots
  or catalogs.
- qvOS-owned post-update jobs execute directly from their feature owners.
  Never copy system behavior into the user-writable custom hook tree.
- Native consumers decide whether a custom-hook failure is fatal. Font,
  theme, battery, boot, and update integrations keep their primary verified
  operation and report the hook failure without inventing rollback.

Run `qvcore/hooks/check`, Bash syntax and ShellCheck, the hook, first-run,
update, font, theme, desktop-install, migration, CLI, product, upstream-overlay,
and full qvOS suites. On an existing installation, use `reconcile --check` and
read-only fixture hooks for runtime validation; never trigger personal hooks as
a test.
