# qvOS Branding Workflow

Read this file completely when changing visible qvOS identity, vector assets,
terminal art, About or screensaver customization, installer logos, session
labels, terminal titles, or branding-state migration.

`qvcore/branding/` owns product identity. Public copy says qvOS; Omarchy appears
only for truthful upstream attribution, an exact external compatibility ABI, or
historical migration evidence.

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
`0600` files. Preserve valid legacy customization, reject unsafe links and
foreign or unbounded files, archive conflicts under the private
`~/.local/state/qvos/branding-backups`, and remove only the validated inactive
`~/.config/omarchy/branding` tree. `--reset-defaults` is an explicit operation
and backs up different qvOS content before replacement.

`config/fastfetch/config.jsonc` is the one installed Fastfetch source and reads
the native About file. Never restore `qvcore/config/files/fastfetch`, the former
ANSI overlay, top-level `icon.txt`/`logo.txt`, or qvcore copies of those assets.

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
the branding, Fastfetch/runtime-root, screensaver, installer, CLI, menu, and
product tests, then the full qvOS suite. After live alignment, run the branding
owner, reconcile Fastfetch, verify permissions and residue, render Fastfetch,
and inspect a fullscreen screenshot when the visible result changes.
