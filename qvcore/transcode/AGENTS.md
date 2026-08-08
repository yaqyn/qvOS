# qvOS Transcode Workflow

Read this file completely when changing picture, video, or terminal-art
conversion, its output naming, clipboard behavior, or any Transcode launch
surface.

`qvcore/transcode/media` and `qvcore/transcode/ascii` are the only conversion
owners. Public commands are `qv-transcode` and `qv-transcode-ascii`; matching
Omarchy names are metadata-free compatibility adapters only.

- Validate every option, input, format, resolution, dimension, and output
  before invoking ImageMagick or FFmpeg. Preserve paths as exact arguments.
- Build media output in a private same-directory temporary and publish with a
  no-clobber hard link. Never overwrite an existing media result or retain a
  partial result after failure.
- Terminal art may replace only a regular user-owned destination, never a link
  or its own input. Preserve an existing destination's mode and replace it
  atomically from the same directory.
- Keep image dimensions and ImageMagick resources bounded. Strip media
  metadata, use share-compatible codecs, and percent-encode clipboard file
  URIs. A clipboard or notification failure must not destroy or misreport a
  successfully saved conversion.
- Thunar, Hyprland, menu, shell, and branding consumers use native qv routes.
  Nautilus is retired and has no source or installed extension path.

Run `qvcore/transcode/check`, Bash syntax, ShellCheck, the focused Transcode,
branding, Thunar, menu, config-migration, product, install, CLI, and upstream
tests, then the full qvOS suite. Use fixtures for conversion commands; do not
modify real media merely to verify source.
