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
  Remove it only when it is the exact native qvOS file; preserve modified,
  linked, foreign, or otherwise unsafe paths.
  Restore Chromium through `qv-default-browser` before removing the active
  optional browser; do not duplicate XDG association mutation here.
- Store qvOS-owned Wayland environment under the `qvos-` filename. Retired
  Retired compatibility environment files are not an active qvOS lifecycle dependency.
- Never embed or redistribute a third party's OAuth application credentials.
  The inherited Chromium Account installer and its one-time retirement engine
  are absent. Chromium refresh installs only the sanitized native qvOS flags
  source and preserves the replaced user file through the config owner.
- Browser defaults live only in `qvcore/browser/`. The unpacked Copy URL
  extension is a small qvOS base capability, not a Web App. Its 128px icon is
  derived from `qvcore/branding/assets/qv-mark-light.svg` on `#d00000`; keep the
  extension free of remote code, unsafe execution primitives, and service URLs.
  Firefox and Zen share the one native `firefox-policies.json` source.
- `install-chromium-defaults` publishes the minimal validated first-launch
  appearance preference into Chromium's root-owned directory without following
  links or replacing foreign state. The installer theme stage delegates to this
  browser owner and never writes `/usr/lib/chromium` directly.
- Offline theme rendering updates browser policy files without discovering or
  refreshing host-session processes through the target chroot. Fresh install
  never deletes Chromium profile locks; removing a live `SingletonLock` is not
  a browser lifecycle operation.
- Fresh browser installs and Chromium refresh write only the native Copy URL
  extension path. Do not restore an inherited runtime-root migration to normal
  install, refresh, removal, or update paths.
- Installation remains noninteractive and stream-safe. Validate the browser
  slug before package or filesystem mutation, and do not launch the installed
  browser from the captured TUI flow.
- Use native qvOS package and command helpers. The inherited theme command is
  the only temporary browser dependency until the theme domain is promoted;
  declare it in the owner's TUI source contract so drift cannot go unnoticed.

Run `qvcore/browser/check`, `qvcore/migrations/check`, Bash syntax, ShellCheck,
the focused browser, migration, software, and TUI tests,
`qvcore/tui/owner-contracts --check`, and the full qvOS suite. Do not install or
remove a live browser merely to verify source ownership.
