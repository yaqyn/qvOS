# qvHOME / qvPLAY

This directory currently contains the frontend-first qvPLAY prototype. It is a
complete fictional local library used to settle the experience before native
or Steam integration begins.

## Run it

```bash
bun install
bun run dev
```

The production frontend is static and self-contained:

```bash
bun run build
bun run preview
```

On qvOS, `Super + Shift + Ctrl + Grave` starts the Vite server when needed,
switches to Workspace G, and opens or focuses the qvPLAY app window. The server
log is stored at `~/.cache/qvos/home/frontend-dev.log`.

## Prototype controls

- Left / Right: browse the favourites-first library
- Enter: preview the launch fade
- Ctrl + E: open the selected game's media editor
- Ctrl + T: toggle trailers for the whole library
- Shift + S: open search
- Shift + H: hide or restore the complete interface and artwork dimming
- Any letter or number: open search and begin typing
- Tab: navigate interactive controls
- Escape: close search, the editor, or the launch preview
- Any key: skip the introduction through its short fade

The library is one continuous art rail. Favourites start from the left and the
selected 4:5 box cover widens into a flat landscape card.
The rail is intentionally skipped by Tab; Left/Right and pointer input own game
selection, so moving control focus cannot change or imitate the selected game.
Search stays hidden above the bottom-right of the rail until typing or
`Shift + S` invokes it. Matches move
to the front in full color; non-matches remain visible behind them in grayscale,
with no search-time card animation. Trailer controls live in Settings as a
global preference, and the hamburger menu opens the complete control reference
under Info & controls.

Hero descriptions always occupy three lines. Longer copy exposes `Read more`,
which opens the selected game's details page. The editor's `Details & links`
tab manages the full description, wiki URL, and three official or community
resources. These edits remain session-only during the frontend phase.

Every game exposes four independent media values in `src/games.ts`: transparent
PNG logo/name, portrait box art, full-screen artwork, and MP4/WebM trailer. The
Media tab edits the same four surfaces directly. qvHOME windows share the
`AppWindow` shell, which keeps a fixed title bar while only the body scrolls.
Scrollbars, document selection, and the browser context menu stay out of the
app surface; text fields keep normal editing behavior.

Logo presentation uses a fixed transparent 4:1 frame. Use a 3200×800 PNG when
available; 1600×400 is the practical minimum. Importing a logo automatically
trims transparent margins into a high-quality derived preview, then the Crop
control opens a full-width, exact-ratio workspace for scale and
horizontal/vertical placement. Wide wordmarks fit this presentation best;
stacked marks can remain fully fitted or be deliberately enlarged to isolate
their wordmark. The source PNG is never resized, recompressed, or changed; only
session presentation data and the derived preview are adjusted.

Box art uses a 4:5 source frame. Use 1600×2000 PNG or WebP when available;
800×1000 is the practical minimum. Its crop workspace shows both the normal
4:5 library cover and the selected 8:5 card at once, and applies the same scale
and focal point to the live rail without modifying the imported source.

Use `?state=loading`, `?state=empty`, or `?state=error` while developing to
inspect the non-happy library states. Media selections use browser object URLs
and are deliberately session-only in this phase.

## Deferred boundary

Tauri, Steam discovery, native persistence, media copying, launch commands,
single-instance behavior, the user installer, and production desktop packaging
are not part of this frontend approval phase. The Play action is visibly
labeled as a preview and never starts a process.

The current qvOS development launcher already opens qvPLAY fullscreen on
Workspace G. The future native handoff will leave qvHOME fullscreen underneath
the launched game.
