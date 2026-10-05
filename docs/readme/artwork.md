# README Artwork

- `cover.gif`: a 1280 × 448, 32-frame, 5.12-second looping system brand cover.
  The canonical white qvOS wordmark stays still above a pixel-lettered SYSTEM
  label while a dark red-to-grayscale pixel gradient moves gently behind it.
- `cover.svg`: its static rendition, including the canonical source hash.
- `cards/*.png`: the approved ten pictures — Git, Snapshots, Security, Devel,
  Power, Thunar, Windows VM, Capture, Media, and Web Apps.
- `icons/*.svg`: red section-heading icons and the illustrations used inside
  feature cards.
- `logos/`: original vendor assets. Their retrieval URLs and SHA-256 hashes live
  in [sources.json](logos/sources.json). Vendor marks retain their owners'
  respective rights; they are not qvOS-authored logos.
- Thunar, Windows VM, and generic capabilities use illustrative symbols
  rather than invented vendor logos.
- Wallpaper references `qvcore/theme/yaqyn/preview.png` directly.
- `gaming-scene.png`: user-supplied gaming artwork added on 2026-10-05,
  retained byte-for-byte as the original source. The source contains 448
  transparent bottom rows. This artwork is not a claim of measured qvOS game
  performance.
  SHA-256: `cc49acc01a77b337f182c61f3f61d1d6d7664c72249888ee2c853f97288c9f07`.

- `gaming-scene-cropped.png`: the displayed 2172 × 724 framing rendition,
  edited with the built-in image tool to remove the empty bottom padding.
  The rendition is resampled; the original source remains available above.
  SHA-256: `75990da95fdcc44950eb314a08902992e9b7dce64f09d047db2e60924383db7e`.
  Editing brief: retain the entire visible red industrial scene, remove its
  transparent bottom padding, and add no text, borders, or new game content.

`pixel_art.py` owns shared gradient and typography. To reproduce the cover and cards:

```sh
python docs/readme/render-cover.py
python docs/readme/render-cards.py
```

These commands use the Python standard library, rsvg-convert, and FFmpeg.
They require no image-generation service or downloaded font. Vendor sources
are already local; rendering does not fetch network assets.
