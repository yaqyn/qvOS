# Omarchy Compatibility

Read this file completely when changing a retained Omarchy command, path, state,
or behavior that exists only to migrate an older qvOS installation.

- `compat/omarchy/` owns temporary compatibility implementations. Keep public
  `bin/omarchy-*` entries as metadata-bearing adapters only.
- Compatibility may translate old names into current qvOS owners; it must not
  duplicate their implementation, expose a new product category, or become a
  dependency of a fresh qvOS installation.
- Preserve only routes needed by an installed or released state. Reject unknown
  inputs, keep removal explicit, and test both delegation and retired inputs.
- Remove a compatibility route together with its old state support once no
  supported installation needs it.
