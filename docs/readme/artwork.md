# README Artwork

- `cover.gif`: a 1280 × 448, 32-frame, 5.12-second looping system brand cover.
  The canonical white qvOS wordmark stays still above a pixel-lettered SYSTEM
  label; a simple dark red-to-grayscale pixel gradient moves gently behind it.
- `cover.svg`: the static rendition. The canonical wordmark source path and
  SHA-256 are recorded inside the SVG.
- `render-cover.py`: the singular cover generator. Run
  `python docs/readme/render-cover.py` with `rsvg-convert` and FFmpeg installed.
  It uses no downloaded fonts, random textures, or image-generation service.
- `icons/*.svg`: ten sharp, local outline icons on a transparent background,
  with a shared 24-unit canvas, 1.7-unit stroke, and `#d00000` accent.
- Wallpaper: the README references `qvcore/theme/yaqyn/preview.png` directly.
  This is the actual bundled wallpaper, not a generated desktop preview.
- Gaming: reserved for user-supplied in-game pictures. No controller product
  image, generated scene, or placeholder is published.

Documentation compositions do not replace Branding's vector masters or change
the installed theme. Keep section imagery relevant to its subject and retain
source provenance for subsequently supplied pictures.
