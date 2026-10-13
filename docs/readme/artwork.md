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
- `gaming-scene.webp`: user-supplied gaming artwork added on 2026-10-05,
  converted to lossless WebP with its original pixels preserved. The source contains 448
  transparent bottom rows. This artwork is not a claim of measured qvOS game
  performance.
  Original PNG SHA-256: `cc49acc01a77b337f182c61f3f61d1d6d7664c72249888ee2c853f97288c9f07`.
  WebP SHA-256: `c19eaac02bc46a36108a733d63f05417f9f6757c04212009786510eba4a10b08`.

- `gaming-scene-cropped.webp`: the displayed 2172 × 724 framing rendition,
  edited with the built-in image tool to remove the empty bottom padding.
  The rendition is resampled; the original source remains available above.
  Original PNG SHA-256: `75990da95fdcc44950eb314a08902992e9b7dce64f09d047db2e60924383db7e`.
  WebP SHA-256: `9874518b0a76a148326997ea9a05f6174410de444a16202da0e10d34ea6b4eee`.
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
