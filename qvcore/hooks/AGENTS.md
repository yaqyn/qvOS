# qvOS Hooks Workflow

Read this file completely when changing custom automation hooks, hook
installation, hook-state migration, or a native hook consumer.

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
- `reconcile` atomically adopts one safe legacy Omarchy hook tree only when the
  canonical tree is absent, installs missing qvOS samples without overwriting
  custom files, removes only allowlisted exact historical qvOS-managed hook
  copies, and rewrites only the exact inherited post-boot invocation. An exact
  retired qvOS-created main post-update hook may be removed, but a different
  main hook is personal automation and must be preserved.
- qvOS-owned post-update jobs execute directly from their feature owners.
  Never copy system behavior into the user-writable custom hook tree.
- Native consumers decide whether a custom-hook failure is fatal. Font,
  theme, battery, boot, and update integrations keep their primary verified
  operation and report the hook failure without inventing rollback.

Run `qvcore/hooks/check`, Bash syntax and ShellCheck, the hook, first-run,
update, font, theme, desktop-install, migration, CLI, product, upstream-overlay,
and full qvOS suites. On an existing installation, run the native migration,
verify the canonical tree and exact legacy-root removal, then use read-only
fixture hooks for runtime validation; never trigger personal hooks as a test.
