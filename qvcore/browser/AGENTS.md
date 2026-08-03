# qvOS Browser Lifecycle

Read this file completely when changing supported browsers, their install or
removal owners, browser policy, defaults, flags, or menu lifecycle.

`qvcore/browser/install` and `qvcore/browser/remove` are the singular mutation owners;
the public inherited command names are metadata-only compatibility adapters.
Keep browser availability and lifecycle in `qvcore/menu/software-actions.psv` and
delegate each selected operation once through the shared TUI.

- Keep Chromium as the qvOS base/default browser; optional browsers never
  replace it automatically.
- Browser policy directories remain root-owned. Theme policy files may be
  desktop-user writable only where `qvcore/browser/setup-policy` explicitly grants
  it; never make the directory or file world-writable.
- Remove only exact qvOS-created flags, policy, and environment files. Never
  recursively delete a shared policy tree or user browser profile.
- Preserve the Firefox/Zen Wayland environment while either browser remains.
  Restore Chromium as the default before removing the active optional browser.
- Installation remains noninteractive and stream-safe. Validate the browser
  slug before package or filesystem mutation, and do not launch the installed
  browser from the captured TUI flow.

Run `qvcore/browser/check`, Bash syntax, ShellCheck, the focused browser and
software/TUI tests, `qvcore/tui/owner-contracts --check`, and the full qvOS suite.
Do not install or remove a live browser merely to verify source ownership.
