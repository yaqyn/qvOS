# qvPLAY design system

## Direction

qvPLAY is a cinema-console library, not a dashboard or store. The selected game
owns the screen. The signature is a quiet cover transformation: a portrait game
case opens horizontally when selected, without a colored frame or drop shadow.
The red horizon seam is reserved for the introduction and primary action instead
of decorating every state.

The generated direction board is in `design/qvplay-direction.png`. The six
fictional key-art files under `public/art/` are the only imagery in this phase.

## Tokens

| Role | Token | Value |
| --- | --- | --- |
| Absolute background | Void | `#050506` |
| Raised surface | Graphite | `#121316` |
| Primary text | Bone | `#f1eee8` |
| Primary action | Orion | `#d9362b` |
| Focus / hot edge | Ember | `#ff6b54` |
| Secondary text | Alloy | `#a7a8aa` |

The qvOS family signature uses locally bundled Montserrat ExtraBold 800 for `qv`, while
qvPLAY uses locally bundled Michroma for its distinctive module name. Archivo
Variable carries game titles, navigation, and controls. JetBrains Mono is
reserved for metadata, state labels, and key hints. Corner radii stay between
6px and 10px; the interface never uses floating pill containers.

## Component contract

- `PlayButton`: solid Orion action, explicit focus ring, pressed depth.
- `IconButton`: square smoked-glass utility action.
- `LibrarySearch`: hidden bottom-right global title, tag, publisher, and
  developer search, revealed only by typing or `Shift + S`.
- `GameRail`: one continuous run of 4:5 box covers, favourites sorted first
  from the left, with the selected game widening into a landscape card. Search
  ranks matches first in color and leaves non-matches visible in grayscale.
  Covers are removed from Tab order so control focus never impersonates game
  selection.
- `Menu`: quiet CSS-transition popover; `Switch` remains visibly unavailable.
- `Settings`: global trailer behavior and other future preferences, separated
  from the artwork-first hero.
- `Info & controls`: the complete keyboard reference, opened from the menu so
  the main library stays clean.
- `MediaEditor`: independent logo/name PNG, box art, full-screen artwork, and
  trailer fields plus full description, wiki, and resource-link fields, all
  with session-only controls. Logo imports normalize transparent bounds into a
  4:1 presentation canvas and expose an exact-ratio crop workspace without
  changing the source PNG. Recommended logo source size is 3200×800; 1600×400
  is the minimum presentation target, and wide wordmarks are preferred over
  stacked logo lockups. Box art uses a 1600×2000 recommended 4:5 source and its
  crop workspace previews both the normal cover and selected 8:5 rail card.
- `GameDetails`: the unclamped description and user-curated official or
  community reference links.
- `AppWindow`: the shared qvHOME modal foundation with fixed title geometry,
  hidden scrollbars, and an independently scrolling body.
- `StatusScene`: useful loading, empty, and failure directions.
- `Toast`: terse confirmation tied to the action name.

## Motion

Motion owns the three-second introduction, hero crossfade, deliberate rail
selection, dialog, launch preview, and library reveal. Search ranking never
animates cards; matches reorder immediately. CSS owns menu and popover states.
Reduced-motion preferences collapse travel and duration without removing state
feedback.

## Experience reference

Netflix's official product material treats artwork as the gateway into a title,
keeps the strongest-ranked choices at the start of a row, and brings the
information needed for a play decision forward. qvPLAY applies those principles
to a personal game collection while deliberately avoiding Netflix's service
chrome, recommendation machinery, and branded visual language.

- https://help.netflix.com/en/node/100639
- https://netflixtechblog.com/artwork-personalization-c589f074ad76
- https://about.netflix.com/en/news/unveiling-our-innovative-new-tv-experience

The packaged XAML from Playnite's Ubiquity theme was also inspected as a direct
gaming-library reference. Its useful lessons are selected-game artwork as the
screen, a fixed lower cover rail, selected-only emphasis, and normalized logo
metadata (600×320 in its current guidance). qvPLAY keeps those principles but
does not inherit Ubiquity's hard-coded offsets, animated selection outlines,
plugin coupling, filter sidebar, or controller-specific chrome.

- https://github.com/RedSchism/ubiquity

## Fictional art prompt set

All six images were generated as original 16:9 industrial science-fiction key
art with darker left-side negative space, graphite materials, restrained red
signals, subtle film grain, and no text, logos, trademarks, or existing
franchise language. Subjects are: a courier above a vertical megacity, a
salvage mech at a burning refinery, an offshore signal station in a storm, an
aerial habitat above cloud cover, an armored rail convoy, and an underground
red scanning ring.
