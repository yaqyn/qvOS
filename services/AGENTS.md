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
- Write enrollment only after complete verification to
  `~/.local/state/qvos/services/proton`. Migrate the exact former
  `qvos/qvcore/proton` marker atomically; reject links, foreign ownership,
  malformed parents, and conflicting new state. Keep the category private at
  `0700` and its empty enrollment marker at `0600`.
- Install only missing pieces and reuse compatible software. Uninstall only an
  enrolled Service and preserve cloud data, profiles, credentials, sessions,
  personal files, and unrelated software.
- Keep Proton direct tools in the singular direct-tool registry. Updates may
  update an installed tool but must never enroll Proton or initialize an
  authenticated CLI.
- Preserve the narrow Proton Pass and Codex credential rules in the owner.
  Tokens stay in process memory and never enter output, arguments, files, or
  catalogs.

Run Bash syntax, ShellCheck, the Proton lifecycle and upload tests, direct-tool,
menu, TUI owner-contract, product-contract, and full qvOS suites. Do not change
live authentication or install/remove Proton solely for source verification.
