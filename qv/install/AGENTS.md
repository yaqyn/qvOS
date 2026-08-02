# qvOS Package Workflow

Read this file completely when changing base packages, conditional hardware
packages, package installation, repair, ISO caching, or live package removal.

`qv/install/packaging/base.packages` is the singular installed base manifest.
`qv/install/packaging/other.packages` is the singular ISO inventory for
conditional hardware paths. `qv/install/packaging/resolve` validates and emits
them; never restore an inherited manifest plus additions/exclusions model.

- Keep qvOS complete without qvCORE. Stack packages stay in their qvCORE owner;
  base packages may provide only shared prerequisites such as `mise`.
- Preserve the reviewed gaming-ready runtime in the marked base section.
  Steam and hardware-specific graphics drivers remain optional owners.
- Treat upstream package changes as capability-review input. Adopt a package
  only with a named qvOS capability and one lifecycle owner.
- Before removing a package, trace command/config/service consumers, reverse
  dependencies, optional-stack ownership, user data, and live installation
  state. Present the exact source and live removal set for approval.
- Never remove a user-installed or qvCORE-owned package merely because it is
  outside the base manifest. Use `omarchy-pkg-drop` only after approval and
  verify the computed Pacman transaction before mutation.

Run the resolver for `base`, `other`, and `all`; package, product, security,
and upstream-boundary tests; Bash syntax and ShellCheck; and the full qvOS
suite. Package-manifest changes also require ISO prepare-only verification.
Do not run package upgrades during source or live parity work.
