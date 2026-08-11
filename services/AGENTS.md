# qvOS Services Workflow

Read this file completely when changing optional integrated services, their
menu classification, enrollment state, direct tools, authentication, or
install and removal lifecycle.

`services/` owns optional service integrations. qvCORE is the mandatory
qvOS implementation and is never a Software category or enrollment scope.
Proton is currently the only qvOS-owned Service.

- Proton exposes exactly Install and Uninstall through
  `services/proton/manage`. Keep convergence, authentication checks,
  state detection, and verification internal.
- Base refresh may call the internal `reconcile` action only for an enrolled
  Proton Service. It may refresh qvOS-owned desktop and Codex assets, but must
  never install packages or tools, change services, or inspect or replace
  authentication.
- Write enrollment only after complete verification to
  `~/.local/state/qvos/services/proton`. Keep the category private at `0700`
  and its empty enrollment marker at `0600`. The pre-release
  `qvos/qvcore/proton` transition is retired; current Service operations never
  inspect or recreate that state root.
- Install only missing pieces and reuse compatible software. Uninstall only an
  enrolled Service and preserve cloud data, profiles, credentials, sessions,
  personal files, and unrelated software.
- Services resolve packages and commands only through native `qv-pkg-*` and
  `qv-cmd-*` helpers. Compatibility command names are external ABI, never an
  internal dependency.
- Keep Proton direct tools in the singular direct-tool registry. Updates may
  update an installed tool but must never enroll Proton or initialize an
  authenticated CLI.
- Preserve the narrow Proton Pass and Codex credential rules in the owner.
  Tokens stay in process memory and never enter output, arguments, files, or
  catalogs.

Run Bash syntax, ShellCheck, the Proton lifecycle and upload tests, direct-tool,
menu, TUI owner-contract, product-contract, and full qvOS suites. Do not change
live authentication or install/remove Proton solely for source verification.
