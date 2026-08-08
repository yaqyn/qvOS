# qvOS Browser Lifecycle

Read this file completely when changing supported browsers, their install or
removal owners, browser policy, defaults, flags, or menu lifecycle.

`qvcore/browser/install` and `qvcore/browser/remove` are the singular mutation
owners. Native routes are `qv install browser` and `qv remove browser`; the
inherited command names are metadata-free compatibility adapters only.
Keep browser availability and lifecycle in `qvcore/menu/software-actions.psv` and
delegate each selected operation once through the shared TUI.

- Keep Chromium as the qvOS base/default browser; optional browsers never
  replace it automatically.
- Browser policy directories remain root-owned. Theme policy files may be
  desktop-user writable only where `qvcore/browser/setup-policy` explicitly grants
  it; never make the directory or file world-writable. The theme owner validates
  the exact directory and `color.json` ownership before its bounded in-place
  update because the user cannot atomically rename inside a root-owned directory.
- Remove only exact qvOS-created flags, policy, and environment files. Never
  recursively delete a shared policy tree or user browser profile.
- Preserve the Firefox/Zen Wayland environment while either browser remains.
  Restore Chromium through `qv-default-browser` before removing the active
  optional browser; do not duplicate XDG association mutation here.
- Store qvOS-owned Wayland environment under the `qvos-` filename. Migrate the
  exact retired Omarchy filename without touching other environment files.
- Installation remains noninteractive and stream-safe. Validate the browser
  slug before package or filesystem mutation, and do not launch the installed
  browser from the captured TUI flow.
- Use native qvOS package and command helpers. The inherited theme command is
  the only temporary browser dependency until the theme domain is promoted;
  declare it in the owner's TUI source contract so drift cannot go unnoticed.

Run `qvcore/browser/check`, Bash syntax, ShellCheck, the focused browser and
software/TUI tests, `qvcore/tui/owner-contracts --check`, and the full qvOS suite.
Do not install or remove a live browser merely to verify source ownership.
