# qvOS Git And qvsync Workflow

Read this file completely when committing qvOS work, auditing upstream Omarchy,
or running `git qvsync`.

The root `AGENTS.md` owns the main qvsync evolution and capability-audit
workflow. These instructions supplement it with repository mechanics and never
replace its judgment.

## Audit Mechanics

1. Require branch `OS`, inspect `git status --short --branch`, and inspect
   `.git/qvsync` when its dispatch is relevant.
2. Start with `git qvsync --audit`. It fetches without merging or publishing
   and reports every upstream commit, changed path, and mechanical overlap hint.
3. Use `--reviewed-upstream <full-sha>` only after completing the root workflow
   for that exact target. It is a freshness gate, not proof of judgment.
4. When adaptation is required, create a backup branch and integrate upstream
   locally without pushing. Finish, verify, and commit the adaptation before
   qvsync may publish.
5. Before every qvsync, refresh the effective reviewed gaming set in
   `test/qvos/qvos-gaming-base-test.sh` against Linutil's current Arch list in
   `core/tabs/system-setup/gaming-setup.sh`. Keep only packages not already
   inherited from Omarchy between `qvos:gaming-base:start` and
   `qvos:gaming-base:end` in `qv/install/packaging/base.additions`. Use current
   package names, keep the matching 32-bit PipeWire JACK package, and leave
   hardware-specific GPU drivers to Omarchy's Steam installer.

## Verification And Publication

- Set repository identity to `Abdulrahman M. Yaqyn <Yaqyn@pm.me>`. Use the
  GitHub noreply fallback only for an unpublished commit rejected by email
  privacy, as defined by the root contract.
- Match checks to the diff: Bash syntax and ShellCheck for shell (`-s bash` for
  sourced install or migration files); `gofmt`, `go test -count=1 ./...`, and
  a `/tmp` Go build for Go; `test/qvos/run.sh` for the full shell suite; binding
  checks for qvOS bindings; Hyprland reload and error checks for its config; and
  `git diff --check`.
- Before runtime checks, back up and apply changed user config, then install
  desktop payloads with
  `OMARCHY_PATH=$PWD bash -c 'source qv/install/desktop'`. Preserve optional
  qvCORE runtime integrations without reinstalling them, verify the direct-tool
  runtime and hook, confirm the live checkout is clean, and run the relevant
  reload or smoke test.
- Stage with `git add -A`; inspect `git diff --cached --check` and
  `git diff --cached --stat`; remove generated artifacts; then commit the
  verified logical unit without agent attribution.
- Run `git qvsync` only from a clean post-commit worktree. Afterward, require the
  upstream block above the qvOS separator in root `AGENTS.md` to match
  `upstream/master:AGENTS.md` byte-for-byte.
- Report the commit SHA, qvsync result, checks run or skipped, and final branch
  status.
