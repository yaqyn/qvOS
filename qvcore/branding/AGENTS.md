# qvOS Branding Workflow

Read this file completely when changing visible qvOS identity, vector assets,
terminal art, About or screensaver customization, installer logos, session
labels, terminal titles, or branding-state migration.

`qvcore/branding/` owns product identity. Public copy says qvOS; Omarchy appears
only for truthful upstream attribution, an exact external compatibility ABI, or
historical migration evidence.
Repository issue forms, native command examples, bundled configuration samples,
and qvOS-owned comments are public identity surfaces. They use qvOS names and
native `qv` routes; do not send users to upstream support or compatibility
commands.

`os-release` is the singular system identity source. `system-identity`
atomically installs it as root-owned `/etc/os-release`, replacing only Arch's
exact vendor link. It leaves the exact installed qvOS file unchanged and
refuses foreign, modified, linked, weakly permissioned, or ambiguously owned
identity state.
Keep `ID=qvos` and `ID_LIKE=arch`: qvOS is the product identity and Arch is the
compatibility base. Fresh installation and migration call this owner; the ISO
builder derives its live identity from the same source and may add only
Archiso's image-build metadata.

The graphical and terminal identities are deliberately distinct:

- `assets/qvos-wordmark-{dark,light}.svg` and
  `assets/qv-mark-{dark,light}.svg` are the self-contained vector masters from
  the qvOS design. Keep them free of scripts, external references, metadata,
  and embedded resources.
- `terminal-art.txt` is Abdulrahman M. Yaqyn's approved poem-and-qvOS terminal
  composition. About, screensaver, installer presentation, and `qv show logo`
  share it as their single default. Do not regenerate it from the vectors or
  rewrite its text without an explicit design decision.
- The Yaqyn wallpaper belongs to `qvcore/theme/`, not Branding. Do not duplicate
  it here.

`install` singularly owns user branding state. Active files are private at
`~/.config/qvos/branding/{about,screensaver}.txt` with `0700` directories and
`0600` files. Reject unsafe links and foreign or unbounded files.
`--reset-defaults` is an explicit operation and backs up different qvOS content
under private `~/.local/state/qvos/branding-backups` before replacement.
Historical Omarchy branding migration is complete; this owner never reads or
mutates that external tree.

`qvcore/config/files/fastfetch/config.jsonc` is the one installed Fastfetch
source and reads the native About file. Never restore a second config layer,
the former ANSI overlay, top-level `icon.txt`/`logo.txt`, or duplicate qvcore
copies of those assets.

Public `qv-branding-*`, `qv-show-logo`, and `qv-refresh-fastfetch` adapters carry
metadata; exact `omarchy-*` names are metadata-free compatibility only. The
Fastfetch owner delegates to the singular config transaction and never embeds
another copier. Native menus and Branding call qv routes; Launch behavior
belongs only to `qvcore/desktop/launch/`. Image imports delegate once to
`qv-transcode-ascii` and never add another image renderer.

List implementation-sized inherited departures in `native-paths`, even when
their final replacement is a thin adapter; list retired inherited assets in
`retired-paths`. Only a text-reviewable upstream change within the small-diff
limit belongs in `compat/omarchy/inherited-seams`. qvOS-only assets belong in no
upstream manifest.

Run `qvcore/branding/check`, `qvcore/config/check`, Bash syntax and ShellCheck,
the system-identity fixture, branding, Fastfetch/runtime-root, screensaver,
installer, CLI, menu, release-ISO, migration, and product tests, then the full
qvOS suite. The branding check enforces upstream
manifests when the development-only `upstream/master` ref is available and
must remain usable in an installed source checkout without that ref. After live
alignment, run the migration with fresh privileged authorization, verify the
root-owned system identity and private user branding, reconcile Fastfetch,
verify permissions and residue, render Fastfetch, and inspect a fullscreen
screenshot when the visible result changes.
