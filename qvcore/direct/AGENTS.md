# qvOS Direct Tool Workflow

Read this file completely when changing direct-tool inventory, verified binary
downloads, optional-integration tool lifecycle, or direct post-update behavior.

`qvcore/direct/manifest.tsv` is the single registry for non-Pacman tools owned
by the optional Devel and Proton scopes. Keep one nine-field tab-separated row
per tool. Do not put base qvOS packages, project-local tools, authentication,
or arbitrary installer commands in this registry.

- `tool` is the only install, update, verify, presence, and removal engine.
  Add a method only when its complete validation and rollback behavior can stay
  centralized here; scope owners must not duplicate download logic.
- Validate release metadata, architecture, exact provider URL, published
  digest, candidate version, and post-install execution before accepting a
  direct binary. Publish replacements atomically and keep temporary downloads
  bounded and private.
- Devel and Proton own enrollment and user confirmation. They may call only
  manifest entries in their exact scope; direct-tool operations never enroll a
  component, configure credentials, start a service, or mutate networking.
- `update` visits every manifest row but updates only tools already present.
  One failure must not hide later results, and any failure makes the stage fail.
- `runtime-paths` is the exact installed payload under
  `~/.local/lib/qvos/direct`. Keep source policy, tests, and owner instructions
  out of that runtime inventory.
- Changes to `tool`, its manifest, or a transitive action owner change TUI
  source digests. Review and regenerate them with
  `qvcore/tui/owner-contracts --write`; never hand-edit the hash ledger.

Run Bash syntax, ShellCheck, `test/qvcore/qvos-direct-tools-test.sh`, the Devel
and Proton lifecycle tests, `qvcore/tui/owner-contracts --check`, the update
tests, and the full qvOS suite. Use fixtures; do not download, install, remove,
update, or authenticate live tools merely to verify source.
