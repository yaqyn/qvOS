# Public README Presentation

Keep the README visual, brief, and product-focused. Use short feature lists and
plain descriptions; avoid slogans, long architecture paragraphs, and tables
that do not support an actual comparison. Link detailed lifecycle requirements
to their native owners. Distinguish base capabilities, optional integrations,
and confirmed release availability.

Use the Yaqyn red/grayscale palette. Branding's vector masters remain the
product authority; documentation artwork is not another logo master. Use sharp,
consistent local SVG section icons. Inspect all generated artwork before use.
Keep its prompt and reference provenance in `artwork.md`.

The cover uses canonical vector paths, a pixel-lettered SYSTEM label, and a
simple dark red-to-grayscale pixel gradient. Keep animation slow and the logo
stationary; avoid texture, decorative geometry, flashing, and slogans.
`render-cover.py` owns reproducible SVG/GIF generation from the Branding master
using Python standard-library code, rsvg-convert, and FFmpeg. Keep `cover.svg`
as the static rendition and use the lightweight `cover.gif` in the README. Gaming imagery belongs beside Gaming; the
actual bundled wallpaper belongs beside Wallpaper & appearance. Generated imagery is
editorial artwork, not installed-system evidence. Do not use TUI screenshots in
the root README. Do not modify the installed theme or wallpaper merely to change
documentation artwork.

Check local links, native command examples, SVG validity, image quality, GitHub
Markdown rendering, and `git diff --check`. Documentation-only changes require
neither Worker redeployment nor live desktop installation.
