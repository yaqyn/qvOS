# Public README Presentation

Keep the README visual, brief, and product-focused. Use short feature lists and
plain descriptions; avoid slogans, long architecture paragraphs, and tables
that do not support an actual comparison. Link detailed lifecycle requirements
to their native owners. Distinguish base capabilities, optional integrations,
and confirmed release availability.

Keep the existing red-icon section headings. Every section starts with a short
pixel-gradient picture bar. Place software logos or relevant feature pictures
beneath the corresponding mentions. Prefer compact wrapping image rows over
wide tables. Keep user-supplied in-game pictures separate from launcher logos;
never replace them with generated gameplay or controller product shots.

Use the Yaqyn red/grayscale palette for the artwork; preserve vendor logo colors
and shapes. Branding's vector masters remain the product authority. Preserve
original vendor assets in `logos/` with retrieval URLs and hashes in
`logos/sources.json`. Verify SVGs contain no scripts or external resources.
Generic feature illustrations are not company logos; make that clear in alt
text and provenance. Proton media-kit assets link back to https://proton.me.

`pixel_art.py` is the singular gradient and pixel-type owner. `render-cover.py`
renders the cover; `render-sections.py` renders the PNG section bars and cards.
Both use Python standard-library code and rsvg-convert; GIF export also uses
FFmpeg. Keep the cover logo stationary and its animation slow. Avoid texture,
decorative geometry, flashing, and slogans. Keep `cover.svg` as the static
rendition and use the lightweight `cover.gif` in the README.

The Wallpaper section uses the actual bundled wallpaper. Documentation artwork
is not installed-system evidence. Do not use TUI screenshots in the root README
or change installed themes to produce documentation. Record provenance in
`artwork.md`.

Check local links, native examples, logo provenance, image rendering at desktop
and narrow widths, GitHub Markdown rendering, and `git diff --check`.
Documentation-only changes require neither Worker redeployment nor live desktop
installation.
