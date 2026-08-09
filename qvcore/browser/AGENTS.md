# qvOS Browser Lifecycle

Read this file completely when changing supported browsers, their install or
removal owners, browser policy, defaults, flags, or menu lifecycle.

`qvcore/browser/install`, `qvcore/browser/remove`, and
`qvcore/browser/refresh-chromium` are the singular mutation owners. Native
routes are `qv install browser`, `qv remove browser`, and
`qv refresh chromium`; inherited command names are metadata-free compatibility
adapters only.
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
- Never embed or redistribute a third party's OAuth application credentials.
  The inherited Chromium Account installer is retired.
  `retire-google-oauth` removes only the two exact historical generated lines,
  identified by reviewed hashes, through a bounded atomic rewrite; it preserves
  every user-owned OAuth value and unrelated flag. Fresh installs omit the
  feature, updates run its native migration, and Chromium refresh performs the
  same cleanup before creating a sanitized config backup.
- Browser defaults live only in `qvcore/browser/`. The unpacked Copy URL
  extension is a small qvOS base capability, not a Web App. Its 128px icon is
  derived from `qvcore/branding/assets/qv-mark-light.svg` on `#d00000`; keep the
  extension free of remote code, unsafe execution primitives, and service URLs.
  Firefox and Zen share the one native `firefox-policies.json` source.
- `migrate-runtime-root` rewrites only exact inherited Copy URL flag lines,
  keeps a same-mode backup for every changed flags file, and preserves unsafe,
  foreign, oversized, or unrelated browser configuration. Fresh install,
  optional browser install, update migration, and Chromium refresh converge on
  the same native path.
- Installation remains noninteractive and stream-safe. Validate the browser
  slug before package or filesystem mutation, and do not launch the installed
  browser from the captured TUI flow.
- Use native qvOS package and command helpers. The inherited theme command is
  the only temporary browser dependency until the theme domain is promoted;
  declare it in the owner's TUI source contract so drift cannot go unnoticed.

Run `qvcore/browser/check`, `qvcore/migrations/check`, Bash syntax, ShellCheck,
the focused browser, migration, software, and TUI tests,
`qvcore/tui/owner-contracts --check`, and the full qvOS suite. Do not install or
remove a live browser merely to verify source ownership. After source alignment,
run the retirement helper and verify only the exact generated credentials left
the active flags file.
