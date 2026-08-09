# Omarchy Compatibility

Read this file completely when changing a retained Omarchy command, path, state,
or behavior that supports an older qvOS installation or external caller.

- `compat/omarchy/` owns temporary compatibility implementations. Promoted
  public `bin/omarchy-*` entries are metadata-free direct adapters; native
  `bin/qv-*` entries alone own qvOS command metadata.
- `inherited-seams` is the sorted, unique inventory of small inherited files
  that intentionally differ only to delegate to an explicit qvOS owner. A seam
  must exist upstream, remain text-reviewable, contain at most ten added and
  ten removed lines, and never appear in a native or retired manifest.
- Implementation-sized inherited changes belong to exactly one owner's
  `native-paths`; absent inherited capability belongs to `retired-paths`.
- Compatibility may translate old names into current qvOS owners; it must not
  duplicate their implementation, expose a new product category, or become a
  dependency of a fresh qvOS installation.
- Compatibility command names resolve owners only through `QVOS_PATH`. Keep the
  installed `omarchy -> qvos` path link for callers that use an old absolute
  path, but never accept `OMARCHY_PATH` as source authority.
- Preserve only routes needed by an installed or released state. Reject unknown
  inputs, keep removal explicit, and test both delegation and retired inputs.
- Remove a compatibility route together with its old state support once no
  supported installation needs it.
- qvCORE is mandatory and no supported qvOS release has an optional qvCORE
  lifecycle. Former `install-qvcore`, `qvcore-remove`, and qvDEV translation
  routes are retired; Services and Development expose their own native
  lifecycles and must never be routed through a qvCORE compatibility bundle.

Run the owning domain check, `test/qvcore/qvos-upstream-overlay-test.sh`, the CLI
catalog tests, and the full suite whenever this manifest changes.
