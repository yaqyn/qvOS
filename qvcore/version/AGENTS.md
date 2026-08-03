# qvOS Version Reporting Workflow

Read this file completely when changing installed-version, source-branch,
package-channel, package-age, or Fastfetch system-state reporting.

`qvcore/version/` is the singular read-only owner. Native consumers use the
metadata-bearing `qv-version*` commands; matching `omarchy-version*` names are
metadata-free compatibility adapters only.

- Read the version and branch from the selected qvOS source checkout. Reject a
  missing, symbolic-link, or malformed version file rather than presenting
  untrusted content as product identity.
- Report the configured Omarchy mirror and repository channel truthfully. qvOS
  supports Stable only, but reporting must expose mismatched, unsupported, or
  unknown configuration rather than silently relabeling it.
- Parse only Pacman's exact `[ALPM] upgraded` records. Missing, empty, or
  malformed history reports `unknown` and remains safe for system-information
  displays.
- Path overrides exist for deterministic fixtures and read-only diagnostics;
  they must never mutate source, Pacman configuration, or logs.

Run `qvcore/version/check`, Bash syntax and ShellCheck, the focused version,
branding, CLI, config, package, upstream-overlay, and full qvOS suites. Apply
the Fastfetch source through its existing config reconciliation owner before
claiming installed-display parity.
