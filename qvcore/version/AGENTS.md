# qvOS Version Reporting Workflow

Read this file completely when changing installed-version, source-branch,
package-channel, package-age, or Fastfetch system-state reporting.

`qvcore/version/` is the singular read-only owner. Native consumers use the
metadata-bearing `qv-version*` commands; matching `omarchy-version*` names are
metadata-free compatibility adapters only.

- Validate that the selected source is a non-symbolic Git top level through
  the shared `lib` owner. Report `rolling-<12-character-commit>` from its exact
  commit and append `-dirty` when tracked or untracked source differs. The
  inherited root `version` file is retired; qvOS rolling identity requires no
  manually maintained release number. Reject an unsafe checkout, missing
  commit, malformed object identity, or unreadable worktree state.
- Report the configured Omarchy mirror and repository channel truthfully. qvOS
  supports Stable only, but reporting must expose mismatched, unsupported, or
  unknown configuration rather than silently relabeling it.
- Parse only Pacman's exact `[ALPM] upgraded` records. Missing, empty, or
  malformed history reports `unknown` and remains safe for system-information
  displays.
- Snapshot descriptions call the native version owner and never read a second
  version source.
- Path overrides exist for deterministic fixtures and read-only diagnostics;
  they must never mutate source, Pacman configuration, or logs.

Run `qvcore/version/check`, Bash syntax and ShellCheck, the focused version,
branding, CLI, config, package, upstream-overlay, and full qvOS suites. Apply
the Fastfetch source through its existing config reconciliation owner before
claiming installed-display parity.
