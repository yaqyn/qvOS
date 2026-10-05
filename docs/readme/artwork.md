# README Artwork

- `cover.gif`: a 1280 × 448, 32-frame, 5.12-second looping system brand cover.
  The canonical white qvOS wordmark stays still above a pixel-lettered SYSTEM
  label while a dark red-to-grayscale pixel gradient moves gently behind it.
- `cover.svg`: its static rendition, including the canonical source hash.
- `sections/*.png`: ten 1280 × 128 section bars with a representative logo or
  feature illustration and pixel lettering. All match the cover's gradient.
- `cards/*.png`: the approved ten pictures — Git, Snapshots, Security, Devel,
  Power, Thunar, Windows VM, Capture, Media, and Web Apps.
- `icons/*.svg`: red section-heading icons and the illustrations used inside
  section bars and feature cards.
- `logos/`: original vendor assets. Their retrieval URLs and SHA-256 hashes live
  in [sources.json](logos/sources.json). Vendor marks retain their owners'
  respective rights; they are not qvOS-authored logos.
- Proton assets come from the [Proton media kit](https://proton.me/media/kit).
  The README links to Proton as required by the kit's published usage guidance.
- Thunar, Windows VM, and generic capabilities use illustrative symbols
  rather than invented vendor logos.
- Wallpaper references `qvcore/theme/yaqyn/preview.png` directly.
- Actual in-game pictures remain user-supplied; no generated gameplay or
  controller product photo is published.

`pixel_art.py` owns shared gradient and typography. To reproduce the artwork:

```sh
python docs/readme/render-cover.py
python docs/readme/render-sections.py
```

These commands use the Python standard library, rsvg-convert, and FFmpeg.
They require no image-generation service or downloaded font. Vendor sources
are already local; rendering does not fetch network assets.
