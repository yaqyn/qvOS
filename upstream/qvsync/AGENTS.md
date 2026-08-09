# qvOS Git And qvsync Workflow

Read this file completely when committing qvOS work, auditing upstream Omarchy
or Omarchy ISO, or running `git qvsync`.

The root `AGENTS.md` owns the main qvsync evolution and capability-audit
workflow. These instructions supplement it with repository mechanics and never
replace its judgment.

## Audit Mechanics

1. Require branch `OS`, inspect `git status --short --branch`, and inspect
   `.git/qvsync` when its dispatch is relevant.
   Install the helper through its tracked absolute path; the installer resolves
   the owning checkout from its own source, converges both official upstream
   fetch URLs, and disables both push URLs regardless of the caller's directory.
2. Start with `git qvsync --audit`. It fetches Omarchy `master` and Omarchy ISO
   `quattro` without merging, cherry-picking, moving product branches, making
   upstream executable build input, or publishing. It reports each independent
   range after `reviewed-upstream` and `reviewed-iso-upstream`, changed paths,
   mechanical overlap hints, and changes to catalog-wide TUI owner sources.
   Treat an owner-contract hint as required semantic review, not permission to
   refresh its fingerprint.
3. Create `upstream/qvsync/upstream-reviews/<target-sha>.psv` for the exact fetched
   target. Use the format in `upstream/qvsync/README.md`; include every commit exactly
   once and give it a decision, native owner, summary, and verification.
4. Create a backup branch before adaptation. Port selected capability into its
   native qvOS owner without merging or cherry-picking the upstream commit.
   Remove the superseded implementation, overlay, adapter, payload, state, and
   test in the same change whenever its replacement is complete.
5. Before recording a reviewed target, refresh the effective reviewed gaming
   set in `test/qvcore/qvos-gaming-base-test.sh` against Linutil's current Arch
   list in `core/tabs/system-setup/gaming-setup.sh`. Update the Gaming-ready
   runtime section of `qvcore/install/packaging/base.packages` deliberately. Use
   current package names, keep the matching 32-bit PipeWire JACK package, and
   leave hardware-specific GPU drivers to the optional Steam installer.
6. When upstream changes optional software, its menu leaves, or lifecycle
   owners, read `qvcore/menu/AGENTS.md` and complete its software reconciliation
   ledger before approving the reviewed upstream SHA.
7. Treat every match from `package-provider-paths` as a required provider audit.
   Verify Stable URLs, repository identity, signatures, keyring, package
   availability, and qvOS manifest compatibility without taking ownership of
   Omarchy's builds or infrastructure.
8. For Omarchy ISO, create
   `upstream/qvsync/iso-upstream-reviews/<target-sha>.psv`, review every commit
   and complete diff, and search the native `release/iso/` owner and tests.
   Port selected fixes deliberately, then record only the exact fetched target
   with `git qvsync --record-reviewed-iso-upstream <target-sha>`. Never restore
   a build-time clone, patch, mount, package dependency, or fallback installer.

## Verification And Publication

- Set repository identity to `Abdulrahman M. Yaqyn <Yaqyn@pm.me>`. Use the
  GitHub noreply fallback only for an unpublished commit rejected by email
  privacy, as defined by the root contract.
- Pushes fail closed through normal Git transport. Never mutate a GitHub ref
  through the API as a push fallback: it can bypass remote policy such as
  GH007. Diagnose the rejection, then use only the authorized unpublished
  email-privacy fallback or retry the unchanged commit normally.
- Match checks to the diff: Bash syntax and ShellCheck for shell (`-s bash` for
  sourced install or migration files); `gofmt`, `go test -count=1 ./...`, and
  a `/tmp` Go build for Go; `test/qvcore/run.sh` for the full shell suite; binding
  checks for qvOS bindings; Hyprland reload and error checks for its config; and
  `git diff --check`.
- Before runtime checks, back up and apply changed user config, then install
  desktop payloads with
  `QVOS_PATH=$PWD bash -c 'source qvcore/install/desktop'`. Preserve optional
  Services and Development integrations without reinstalling them,
  verify the direct-tool
  runtime and hook, confirm the live checkout is clean, and run the relevant
  reload or smoke test.
- Stage with `git add -A`; inspect `git diff --cached --check` and
  `git diff --cached --stat`; remove generated artifacts; then commit the
  verified logical unit without agent attribution.
- After verification, run
  `git qvsync --record-reviewed-upstream <target-sha>` and commit the validated
  ledger, reviewed baseline, and qvOS adaptation together. Review upstream
  instruction changes as capability input, but keep root `AGENTS.md` precise to
  qvOS's current paths, owners, and verification model.
- Record an ISO target separately with
  `git qvsync --record-reviewed-iso-upstream <target-sha>` and commit its ISO
  ledger, baseline, and verified native ports together. Never advance one
  baseline as evidence for the other.
- qvsync never publishes. Use the normal reviewed Git workflow only when the
  user asks to push, then report the commit, upstream baseline, checks, and
  final branch status.
