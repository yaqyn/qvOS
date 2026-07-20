import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import type { ChangeEvent, ReactElement, RefObject } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Button,
  Input,
  Menu,
  MenuItem,
  MenuTrigger,
  Popover,
  SearchField,
  Separator,
  Tab,
  TabList,
  TabPanel,
  Tabs,
} from "react-aria-components";
import { type Game, games } from "./games";
import {
  CloseIcon,
  EditIcon,
  InfoIcon,
  MenuIcon,
  PlayIcon,
  RefreshIcon,
  SearchIcon,
  SettingsIcon,
} from "./icons";
import {
  nextGameId,
  type PreviewState,
  previewStateFromSearch,
  rankGamesForSearch,
  sortGamesByFavorite,
} from "./library";
import { AppWindow } from "./ui/AppWindow";

type IntroPhase = "running" | "exiting" | "done";
type MediaSlot = keyof Game["media"];
type SettingsTab = "settings" | "info";
type EditorTab = "media" | "details";

interface ResourceLinkDraft {
  id: string;
  label: string;
  url: string;
}

interface GameDetailsDraft {
  description: string;
  resources: ResourceLinkDraft[];
  wikiUrl: string;
}

interface PreviewAsset {
  fileName: string;
  height?: number;
  presentationUrl?: string;
  type: string;
  url: string;
  width?: number;
}

interface CropTransform {
  scale: number;
  x: number;
  y: number;
}

type GamePreviews = Partial<Record<MediaSlot, PreviewAsset>>;
type PreviewMedia = Record<string, GamePreviews>;
type GameDetailsById = Partial<Record<string, GameDetailsDraft>>;
type MediaCropsById = Partial<Record<string, CropTransform>>;

interface QvPlayAppProps {
  introDurationMs?: number;
}

const defaultLogoCrop: CropTransform = { scale: 1, x: 0, y: 0 };
const defaultBoxArtCrop: CropTransform = { scale: 1, x: 0, y: 0 };
const logoPresentation = { height: 800, width: 3200 };

const slots: ReadonlyArray<{
  accept: string;
  description: string;
  key: MediaSlot;
  label: string;
}> = [
  {
    key: "logo",
    label: "Logo / name",
    description: "Transparent PNG wordmark",
    accept: "image/png",
  },
  {
    key: "boxArt",
    label: "Box art",
    description: "Portrait 4:5 library cover",
    accept: "image/png,image/jpeg,image/webp",
  },
  {
    key: "artwork",
    label: "Artwork",
    description: "Full-screen 16:9 background",
    accept: "image/png,image/jpeg,image/webp",
  },
  {
    key: "trailer",
    label: "Trailer",
    description: "Muted looping MP4 or WebM",
    accept: "video/mp4,video/webm",
  },
];

async function normalizeLogoPresentation(
  file: File,
): Promise<{ height: number; presentationUrl: string; width: number } | null> {
  if (typeof createImageBitmap === "undefined") {
    return null;
  }

  const bitmap = await createImageBitmap(file);
  try {
    const scanScale = Math.min(1, 1024 / bitmap.width, 1024 / bitmap.height);
    const scanWidth = Math.max(1, Math.round(bitmap.width * scanScale));
    const scanHeight = Math.max(1, Math.round(bitmap.height * scanScale));
    const scanCanvas = document.createElement("canvas");
    scanCanvas.width = scanWidth;
    scanCanvas.height = scanHeight;
    const scanContext = scanCanvas.getContext("2d", { willReadFrequently: true });
    if (!scanContext) {
      return null;
    }

    scanContext.drawImage(bitmap, 0, 0, scanWidth, scanHeight);
    const pixels = scanContext.getImageData(0, 0, scanWidth, scanHeight).data;
    let minX = scanWidth;
    let minY = scanHeight;
    let maxX = -1;
    let maxY = -1;

    for (let pixel = 0; pixel < scanWidth * scanHeight; pixel += 1) {
      if ((pixels[pixel * 4 + 3] ?? 0) <= 8) {
        continue;
      }
      const x = pixel % scanWidth;
      const y = Math.floor(pixel / scanWidth);
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    }

    const hasVisiblePixels = maxX >= minX && maxY >= minY;
    const sourceX = hasVisiblePixels ? minX / scanScale : 0;
    const sourceY = hasVisiblePixels ? minY / scanScale : 0;
    const sourceWidth = hasVisiblePixels ? (maxX - minX + 1) / scanScale : bitmap.width;
    const sourceHeight = hasVisiblePixels ? (maxY - minY + 1) / scanScale : bitmap.height;
    const availableWidth = logoPresentation.width * 0.9;
    const availableHeight = logoPresentation.height * 0.8;
    const presentationScale = Math.min(
      availableWidth / sourceWidth,
      availableHeight / sourceHeight,
    );
    const drawWidth = sourceWidth * presentationScale;
    const drawHeight = sourceHeight * presentationScale;

    const presentationCanvas = document.createElement("canvas");
    presentationCanvas.width = logoPresentation.width;
    presentationCanvas.height = logoPresentation.height;
    const presentationContext = presentationCanvas.getContext("2d");
    if (!presentationContext) {
      return null;
    }
    presentationContext.imageSmoothingEnabled = true;
    presentationContext.imageSmoothingQuality = "high";
    presentationContext.drawImage(
      bitmap,
      sourceX,
      sourceY,
      sourceWidth,
      sourceHeight,
      (logoPresentation.width - drawWidth) / 2,
      (logoPresentation.height - drawHeight) / 2,
      drawWidth,
      drawHeight,
    );

    const blob = await new Promise<Blob | null>((resolve) =>
      presentationCanvas.toBlob(resolve, "image/png"),
    );
    if (!blob) {
      return null;
    }

    return {
      height: bitmap.height,
      presentationUrl: URL.createObjectURL(blob),
      width: bitmap.width,
    };
  } finally {
    bitmap.close();
  }
}

function defaultGameDetails(game: Game): GameDetailsDraft {
  return {
    description: game.description,
    wikiUrl: "",
    resources: [
      { id: "official", label: "Official site", url: "" },
      { id: "community", label: "Community guide", url: "" },
      { id: "companion", label: "Marketplace or companion", url: "" },
    ],
  };
}

function safeExternalUrl(value: string): string | null {
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
  } catch {
    return null;
  }
}

function isEditableTarget(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement ||
    target instanceof HTMLSelectElement ||
    (target instanceof HTMLElement && target.isContentEditable)
  );
}

function QvPlayWordmark({ compact = false }: { compact?: boolean }): ReactElement {
  return (
    <span className="qvplay-brand" data-compact={compact || undefined}>
      <span className="qvplay-brand__qv">qv</span>
      <span className="qvplay-brand__module">PLAY</span>
    </span>
  );
}

function Intro({ phase }: { phase: IntroPhase }): ReactElement | null {
  if (phase === "done") {
    return null;
  }

  return (
    <motion.div
      animate={{ opacity: phase === "exiting" ? 0 : 1 }}
      className="intro"
      initial={{ opacity: 1 }}
      transition={{ duration: phase === "exiting" ? 0.38 : 0 }}
    >
      <motion.div
        animate={{ opacity: 1, scale: 1.045 }}
        className="intro-wordmark"
        initial={{ opacity: 0, scale: 0.96 }}
        transition={{ duration: 2.25, ease: [0.2, 0.8, 0.2, 1] }}
      >
        <QvPlayWordmark />
      </motion.div>
      <motion.div
        animate={{ opacity: [0, 0.85, 0], scaleX: [0.02, 1, 1] }}
        className="intro-seam"
        initial={{ opacity: 0, scaleX: 0 }}
        transition={{ delay: 0.65, duration: 1.95, times: [0, 0.55, 1] }}
      />
      <motion.p animate={{ opacity: 0.58 }} initial={{ opacity: 0 }} transition={{ delay: 1.2 }}>
        qvHOME / PLAY
      </motion.p>
    </motion.div>
  );
}

function FallbackArtwork({
  game,
  compact = false,
}: {
  game: Game;
  compact?: boolean;
}): ReactElement {
  return (
    <div className={`fallback-art fallback-art--${game.tone}`} data-compact={compact || undefined}>
      <span className="fallback-art__index">QV / {game.id.slice(0, 2).toUpperCase()}</span>
      <span className="fallback-art__line" />
      <strong>{game.title}</strong>
    </div>
  );
}

function HeroArtwork({
  game,
  previews,
  trailersEnabled,
}: {
  game: Game;
  previews: GamePreviews;
  trailersEnabled: boolean;
}): ReactElement {
  const artwork = previews.artwork?.url ?? game.media.artwork;
  const trailer = previews.trailer?.url ?? game.media.trailer;

  if (trailersEnabled && trailer) {
    return (
      <motion.video
        autoPlay
        className="hero-art hero-art--video"
        initial={{ opacity: 0 }}
        key={`${game.id}-trailer`}
        loop
        muted
        playsInline
        src={trailer}
        animate={{ opacity: 1 }}
      />
    );
  }

  if (!artwork) {
    return <FallbackArtwork game={game} />;
  }

  return (
    <motion.img
      alt=""
      animate={{ opacity: 1, scale: 1 }}
      className="hero-art"
      initial={{ opacity: 0, scale: 1.018 }}
      key={`${game.id}-hero`}
      src={artwork}
      transition={{ duration: 0.72, ease: [0.2, 0.8, 0.2, 1] }}
    />
  );
}

function GameLogoArtwork({
  crop = defaultLogoCrop,
  game,
  preview,
  compact = false,
}: {
  crop?: CropTransform;
  game: Game;
  preview?: PreviewAsset;
  compact?: boolean;
}): ReactElement {
  const logo = preview?.presentationUrl ?? preview?.url ?? game.media.logo;

  return (
    <span className="game-logo-artwork" data-compact={compact || undefined}>
      {logo ? (
        <img
          alt=""
          src={logo}
          style={{ transform: `translate(${crop.x}%, ${crop.y}%) scale(${crop.scale})` }}
        />
      ) : (
        <span className="game-wordmark__text">{game.title}</span>
      )}
    </span>
  );
}

function BoxArtArtwork({
  crop = defaultBoxArtCrop,
  game,
  preview,
}: {
  crop?: CropTransform;
  game: Game;
  preview?: PreviewAsset;
}): ReactElement {
  const boxArt = preview?.url ?? game.media.boxArt;

  if (!boxArt) {
    return <FallbackArtwork compact game={game} />;
  }

  return (
    <img
      alt=""
      className="box-artwork"
      src={boxArt}
      style={{
        objectPosition: `${50 + crop.x}% ${50 + crop.y}%`,
        scale: crop.scale,
      }}
    />
  );
}

function GameWordmark({
  crop,
  game,
  preview,
}: {
  crop: CropTransform;
  game: Game;
  preview?: PreviewAsset;
}): ReactElement {
  return (
    <h1 aria-label={game.title} className="game-wordmark" id="selected-game-title">
      <GameLogoArtwork crop={crop} game={game} preview={preview} />
    </h1>
  );
}

function GameDescription({
  description,
  onReadMore,
}: {
  description: string;
  onReadMore: () => void;
}): ReactElement {
  const descriptionRef = useRef<HTMLParagraphElement>(null);
  const [truncated, setTruncated] = useState(description.length > 150);

  useEffect(() => {
    const descriptionElement = descriptionRef.current;
    if (!descriptionElement) {
      return;
    }

    const measure = () => {
      setTruncated(
        description.length > 150 ||
          descriptionElement.scrollHeight > descriptionElement.clientHeight + 1,
      );
    };
    const frame = window.requestAnimationFrame(measure);
    const resizeObserver =
      typeof ResizeObserver === "undefined" ? null : new ResizeObserver(measure);
    resizeObserver?.observe(descriptionElement);

    return () => {
      window.cancelAnimationFrame(frame);
      resizeObserver?.disconnect();
    };
  }, [description]);

  return (
    <div className="game-description-block">
      <p className="game-description" ref={descriptionRef}>
        {description}
      </p>
      <div className="game-description-more">
        {truncated ? (
          <Button className="read-more-button" onPress={onReadMore}>
            Read more
          </Button>
        ) : null}
      </div>
    </div>
  );
}

function LibrarySearch({
  inputRef,
  query,
  onClose,
  onChange,
}: {
  inputRef: RefObject<HTMLInputElement | null>;
  query: string;
  onClose: () => void;
  onChange: (query: string) => void;
}): ReactElement {
  return (
    <motion.div
      animate={{ opacity: 1, scaleX: 1, y: 0 }}
      className="library-search-shell"
      initial={{ opacity: 0, scaleX: 0.92, y: -5 }}
      transition={{ duration: 0.18, ease: [0.2, 0.8, 0.2, 1] }}
    >
      <SearchField
        aria-label="Search games"
        autoFocus
        className="library-search"
        onChange={onChange}
        value={query}
      >
        <SearchIcon />
        <Input className="library-search__input" placeholder="Search games" ref={inputRef} />
        <Button aria-label="Close game search" className="library-search__clear" onPress={onClose}>
          <CloseIcon />
        </Button>
      </SearchField>
    </motion.div>
  );
}

function MainMenu({
  isOpen,
  onOpenChange,
  onEdit,
  onInfo,
  onQuit,
  onRefresh,
  onSettings,
}: {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  onEdit: () => void;
  onInfo: () => void;
  onQuit: () => void;
  onRefresh: () => void;
  onSettings: () => void;
}): ReactElement {
  return (
    <MenuTrigger isOpen={isOpen} onOpenChange={onOpenChange}>
      <Button aria-label="Open qvPLAY menu" className="icon-button menu-button">
        <MenuIcon />
      </Button>
      <Popover className="menu-popover" placement="bottom start">
        <div className="menu-heading">
          <span>qvHOME</span>
          <QvPlayWordmark compact />
        </div>
        <Menu
          aria-label="qvPLAY menu"
          className="app-menu"
          onAction={(key) => {
            if (key === "refresh") {
              onRefresh();
            } else if (key === "edit") {
              onEdit();
            } else if (key === "settings") {
              onSettings();
            } else if (key === "info") {
              onInfo();
            } else if (key === "quit") {
              onQuit();
            }
          }}
        >
          <MenuItem
            aria-label="Switch — qvPLAY only"
            className="menu-item"
            id="switch"
            isDisabled
            textValue="Switch — qvPLAY only"
          >
            <span aria-hidden="true" className="menu-item__spacer" />
            <span>
              <small>Switch</small>
              qvPLAY only
            </span>
            <kbd>—</kbd>
          </MenuItem>
          <Separator className="menu-separator" />
          <MenuItem className="menu-item" id="refresh" textValue="Refresh library">
            <RefreshIcon />
            <span>Refresh library</span>
          </MenuItem>
          <MenuItem className="menu-item" id="edit" textValue="Edit selected game">
            <EditIcon />
            <span>Edit selected game</span>
            <kbd>Ctrl E</kbd>
          </MenuItem>
          <MenuItem className="menu-item" id="settings" textValue="Settings">
            <SettingsIcon />
            <span>Settings</span>
          </MenuItem>
          <MenuItem
            aria-label="Info and controls"
            className="menu-item"
            id="info"
            textValue="Info and controls"
          >
            <InfoIcon />
            <span>Info &amp; controls</span>
          </MenuItem>
          <Separator className="menu-separator" />
          <MenuItem className="menu-item menu-item--danger" id="quit" textValue="Quit">
            <CloseIcon />
            <span>Quit</span>
          </MenuItem>
        </Menu>
        <p className="menu-footnote">Frontend prototype · no process handoff</p>
      </Popover>
    </MenuTrigger>
  );
}

function Rail({
  boxArtCrops,
  games: visibleGames,
  previews,
  matchingIds,
  selectionMotion,
  searching,
  selectedId,
  onSelect,
}: {
  boxArtCrops: MediaCropsById;
  games: readonly Game[];
  previews: PreviewMedia;
  matchingIds: ReadonlySet<string>;
  selectionMotion: boolean;
  searching: boolean;
  selectedId: string | null;
  onSelect: (id: string) => void;
}): ReactElement {
  const selectedButton = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (selectedButton.current?.dataset.gameId === selectedId) {
      selectedButton.current.scrollIntoView?.({
        behavior: searching ? "auto" : "smooth",
        block: "nearest",
        inline: "center",
      });
    }
  }, [searching, selectedId]);

  return (
    <nav
      aria-label="Game library"
      className="rail-track"
      data-selection-motion={selectionMotion || undefined}
      data-searching={searching || undefined}
    >
      {visibleGames.map((game) => {
        const selected = game.id === selectedId;
        const crop = boxArtCrops[game.id] ?? defaultBoxArtCrop;

        return (
          <button
            aria-current={selected ? "true" : undefined}
            aria-label={`Select ${game.title}`}
            className="game-card"
            data-game-id={game.id}
            data-match={searching ? matchingIds.has(game.id) : undefined}
            data-selected={selected || undefined}
            key={game.id}
            onClick={() => onSelect(game.id)}
            ref={selected ? selectedButton : undefined}
            tabIndex={-1}
            type="button"
          >
            <BoxArtArtwork crop={crop} game={game} preview={previews[game.id]?.boxArt} />
          </button>
        );
      })}
    </nav>
  );
}

function StatusScene({
  state,
  onRetry,
}: {
  state: Exclude<PreviewState, "live"> | "refreshing";
  onRetry: () => void;
}): ReactElement {
  if (state === "loading" || state === "refreshing") {
    return (
      <section aria-live="polite" className="status-scene">
        <span className="status-scan" />
        <p>{state === "refreshing" ? "Refreshing library" : "Preparing local library"}</p>
        <h1>One moment.</h1>
        <small>No network is used.</small>
      </section>
    );
  }

  if (state === "empty") {
    return (
      <section className="status-scene">
        <span className="status-code">QV / 00</span>
        <p>Local library</p>
        <h1>No games found.</h1>
        <small>Installed games will appear here, with favourites sorted first.</small>
      </section>
    );
  }

  return (
    <section className="status-scene" role="alert">
      <span className="status-code">QV / ERR</span>
      <p>Library unavailable</p>
      <h1>The local game list could not be read.</h1>
      <small>Nothing was changed. Retry when the source is available.</small>
      <Button className="secondary-button" onPress={onRetry}>
        Retry
      </Button>
    </section>
  );
}

function SearchEmpty({ query, onClear }: { query: string; onClear: () => void }): ReactElement {
  return (
    <section className="status-scene">
      <span className="status-code">QV / SEARCH</span>
      <p>No matches</p>
      <h1>Nothing found for “{query}”.</h1>
      <small>Search checks titles, tags, publishers, and developers.</small>
      <Button className="secondary-button" onPress={onClear}>
        Clear search
      </Button>
    </section>
  );
}

function GameDetailsPage({
  details,
  game,
  isOpen,
  onClose,
  onEdit,
}: {
  details: GameDetailsDraft;
  game: Game;
  isOpen: boolean;
  onClose: () => void;
  onEdit: () => void;
}): ReactElement {
  const wikiUrl = safeExternalUrl(details.wikiUrl);
  const resources = details.resources.flatMap((resource) => {
    const url = safeExternalUrl(resource.url);
    return url && resource.label.trim() ? [{ ...resource, url }] : [];
  });

  return (
    <AppWindow
      actions={
        <Button className="secondary-button window-edit-button" onPress={onEdit}>
          <EditIcon /> Edit details &amp; links
        </Button>
      }
      closeLabel="Close game details"
      eyebrow={game.eyebrow}
      isOpen={isOpen}
      onClose={onClose}
      size="details"
      title={game.title}
    >
      <div className="details-layout">
        <article className="details-description">
          <p>About</p>
          <h3>Game description</h3>
          <div>{details.description}</div>
        </article>
        <aside className="details-links">
          <p>References</p>
          <h3>Links</h3>
          {wikiUrl ? (
            <a href={wikiUrl} rel="noreferrer" target="_blank">
              <span>Wiki</span>
              <small>{wikiUrl}</small>
            </a>
          ) : (
            <div className="details-link-empty">Wiki link not added</div>
          )}
          {resources.map((resource) => (
            <a href={resource.url} key={resource.id} rel="noreferrer" target="_blank">
              <span>{resource.label}</span>
              <small>{resource.url}</small>
            </a>
          ))}
          {resources.length === 0 ? (
            <div className="details-link-empty">Additional links not added</div>
          ) : null}
        </aside>
      </div>
    </AppWindow>
  );
}

function SettingsPage({
  isOpen,
  onClose,
  onTabChange,
  onToggleTrailer,
  tab,
  trailersEnabled,
}: {
  isOpen: boolean;
  onClose: () => void;
  onTabChange: (tab: SettingsTab) => void;
  onToggleTrailer: () => void;
  tab: SettingsTab;
  trailersEnabled: boolean;
}): ReactElement {
  return (
    <AppWindow
      closeLabel="Close settings"
      eyebrow="qvPLAY"
      isOpen={isOpen}
      onClose={onClose}
      size="compact"
      title="Settings & information"
    >
      <Tabs
        className="settings-tabs"
        onSelectionChange={(key) => {
          if (key === "settings" || key === "info") {
            onTabChange(key);
          }
        }}
        selectedKey={tab}
      >
        <TabList aria-label="Settings sections" className="settings-tab-list">
          <Tab className="settings-tab" id="settings">
            Settings
          </Tab>
          <Tab className="settings-tab" id="info">
            Info &amp; controls
          </Tab>
        </TabList>

        <TabPanel className="settings-panel" id="settings">
          <div className="settings-panel__heading">
            <p>Playback</p>
            <h3>All games</h3>
            <span>Playback preferences apply across the whole library.</span>
          </div>
          <Button
            aria-label="Toggle trailer previews"
            aria-pressed={trailersEnabled}
            className="setting-row"
            onPress={onToggleTrailer}
          >
            <span>
              <strong>Trailer preview</strong>
              <small>Replace the hero artwork with a muted looping local trailer.</small>
            </span>
            <b>{trailersEnabled ? "On" : "Off"}</b>
          </Button>
        </TabPanel>

        <TabPanel className="settings-panel" id="info">
          <div className="settings-panel__heading">
            <p>Controls</p>
            <h3>Everything stays close.</h3>
            <span>Letters and numbers always begin a library search.</span>
          </div>
          <dl className="controls-list">
            <div>
              <dt>Arrow Left / Right</dt>
              <dd>Browse games</dd>
            </div>
            <div>
              <dt>Enter</dt>
              <dd>Play selected game</dd>
            </div>
            <div>
              <dt>Shift + S</dt>
              <dd>Open search</dd>
            </div>
            <div>
              <dt>Ctrl + E</dt>
              <dd>Edit selected game</dd>
            </div>
            <div>
              <dt>Ctrl + T</dt>
              <dd>Toggle trailers for all games</dd>
            </div>
            <div>
              <dt>Shift + H</dt>
              <dd>Hide or show the interface</dd>
            </div>
            <div>
              <dt>Escape</dt>
              <dd>Close the current overlay</dd>
            </div>
          </dl>
        </TabPanel>
      </Tabs>
    </AppWindow>
  );
}

function LogoCropControls({
  crop,
  game,
  onBack,
  onChange,
  onReset,
  preview,
}: {
  crop: CropTransform;
  game: Game;
  onBack: () => void;
  onChange: (crop: CropTransform) => void;
  onReset: () => void;
  preview?: PreviewAsset;
}): ReactElement {
  return (
    <div className="media-crop-controls" data-crop-workspace>
      <div className="media-crop-controls__heading">
        <div>
          <span>Crop logo preview</span>
          <small>
            4:1 presentation · 3200×800 recommended · wide wordmarks fit best · original PNG
            unchanged
          </small>
        </div>
        <Button className="crop-back-button" onPress={onBack}>
          Back to media
        </Button>
      </div>
      <div aria-label="Logo crop preview" className="logo-crop-stage" role="img">
        <GameLogoArtwork crop={crop} game={game} preview={preview} />
        <span aria-hidden="true" className="logo-crop-stage__safe-area" />
      </div>
      <label>
        <span>Scale</span>
        <input
          aria-label="Logo crop scale"
          max="4"
          min="0.75"
          onChange={(event) => onChange({ ...crop, scale: Number(event.target.value) })}
          step="0.05"
          type="range"
          value={crop.scale}
        />
        <output>{Math.round(crop.scale * 100)}%</output>
      </label>
      <label>
        <span>Horizontal</span>
        <input
          aria-label="Logo crop horizontal position"
          max="50"
          min="-50"
          onChange={(event) => onChange({ ...crop, x: Number(event.target.value) })}
          step="1"
          type="range"
          value={crop.x}
        />
        <output>{crop.x}</output>
      </label>
      <label>
        <span>Vertical</span>
        <input
          aria-label="Logo crop vertical position"
          max="50"
          min="-50"
          onChange={(event) => onChange({ ...crop, y: Number(event.target.value) })}
          step="1"
          type="range"
          value={crop.y}
        />
        <output>{crop.y}</output>
      </label>
      <Button className="crop-reset-button" onPress={onReset}>
        Fit
      </Button>
    </div>
  );
}

function BoxArtCropControls({
  crop,
  game,
  onBack,
  onChange,
  onReset,
  preview,
}: {
  crop: CropTransform;
  game: Game;
  onBack: () => void;
  onChange: (crop: CropTransform) => void;
  onReset: () => void;
  preview?: PreviewAsset;
}): ReactElement {
  return (
    <div className="media-crop-controls" data-crop-workspace>
      <div className="media-crop-controls__heading">
        <div>
          <span>Crop box art</span>
          <small>4:5 source · 1600×2000 recommended · 800×1000 minimum · original unchanged</small>
        </div>
        <Button className="crop-back-button" onPress={onBack}>
          Back to media
        </Button>
      </div>
      <fieldset aria-label="Box art crop preview" className="box-art-crop-previews">
        <figure>
          <figcaption>Library · 4:5</figcaption>
          <div className="box-art-crop-stage">
            <BoxArtArtwork crop={crop} game={game} preview={preview} />
          </div>
        </figure>
        <figure>
          <figcaption>Selected · 8:5</figcaption>
          <div className="box-art-crop-stage" data-selected>
            <BoxArtArtwork crop={crop} game={game} preview={preview} />
          </div>
        </figure>
      </fieldset>
      <label>
        <span>Scale</span>
        <input
          aria-label="Box art crop scale"
          max="1.6"
          min="1"
          onChange={(event) => onChange({ ...crop, scale: Number(event.target.value) })}
          step="0.05"
          type="range"
          value={crop.scale}
        />
        <output>{Math.round(crop.scale * 100)}%</output>
      </label>
      <label>
        <span>Horizontal focus</span>
        <input
          aria-label="Box art crop horizontal position"
          max="50"
          min="-50"
          onChange={(event) => onChange({ ...crop, x: Number(event.target.value) })}
          step="1"
          type="range"
          value={crop.x}
        />
        <output>{crop.x}</output>
      </label>
      <label>
        <span>Vertical focus</span>
        <input
          aria-label="Box art crop vertical position"
          max="50"
          min="-50"
          onChange={(event) => onChange({ ...crop, y: Number(event.target.value) })}
          step="1"
          type="range"
          value={crop.y}
        />
        <output>{crop.y}</output>
      </label>
      <Button className="crop-reset-button" onPress={onReset}>
        Fit
      </Button>
    </div>
  );
}

function MediaEditor({
  boxArtCrop,
  details,
  game,
  isOpen,
  logoCrop,
  onClose,
  onBoxArtCropChange,
  onLogoCropChange,
  onDetailsChange,
  onPreview,
  onTabChange,
  previews,
  tab,
}: {
  boxArtCrop: CropTransform;
  details: GameDetailsDraft;
  game: Game;
  isOpen: boolean;
  logoCrop: CropTransform;
  onClose: () => void;
  onBoxArtCropChange: (crop: CropTransform) => void;
  onLogoCropChange: (crop: CropTransform) => void;
  onDetailsChange: (details: GameDetailsDraft) => void;
  onPreview: (slot: MediaSlot, file: File) => void;
  onTabChange: (tab: EditorTab) => void;
  previews: GamePreviews;
  tab: EditorTab;
}): ReactElement {
  const [cropSlot, setCropSlot] = useState<"boxArt" | "logo" | null>(null);
  const logoAvailable = Boolean(previews.logo ?? game.media.logo);
  const boxArtAvailable = Boolean(previews.boxArt ?? game.media.boxArt);

  function handleFile(slot: MediaSlot, event: ChangeEvent<HTMLInputElement>): void {
    const file = event.target.files?.[0];
    if (file) {
      onPreview(slot, file);
    }
    event.target.value = "";
  }

  return (
    <AppWindow
      closeLabel="Close media editor"
      eyebrow="Selected game"
      footer={
        <>
          <span>Session only</span>
          <p>Media and game details remain session-only in this frontend phase.</p>
          <Button className="secondary-button" onPress={onClose}>
            Done
          </Button>
        </>
      }
      isOpen={isOpen}
      onClose={onClose}
      title={game.title}
    >
      <Tabs
        className="editor-tabs"
        onSelectionChange={(key) => {
          if (key === "media" || key === "details") {
            onTabChange(key);
          }
        }}
        selectedKey={tab}
      >
        <TabList aria-label="Game editor sections" className="settings-tab-list">
          <Tab className="settings-tab" id="media">
            Media
          </Tab>
          <Tab className="settings-tab" id="details">
            Details &amp; links
          </Tab>
        </TabList>
        <TabPanel className="editor-panel" id="media">
          {logoAvailable && cropSlot === "logo" ? (
            <LogoCropControls
              crop={logoCrop}
              game={game}
              onBack={() => setCropSlot(null)}
              onChange={onLogoCropChange}
              onReset={() => onLogoCropChange(defaultLogoCrop)}
              preview={previews.logo}
            />
          ) : boxArtAvailable && cropSlot === "boxArt" ? (
            <BoxArtCropControls
              crop={boxArtCrop}
              game={game}
              onBack={() => setCropSlot(null)}
              onChange={onBoxArtCropChange}
              onReset={() => onBoxArtCropChange(defaultBoxArtCrop)}
              preview={previews.boxArt}
            />
          ) : (
            <>
              <p className="dialog-intro">
                Preview each surface before the native copy-and-persist workflow is connected.
              </p>
              <div className="media-grid">
                {slots.map((slot) => {
                  const preview = previews[slot.key];
                  const currentMedia = game.media[slot.key];
                  const cropKey = slot.key === "logo" || slot.key === "boxArt" ? slot.key : null;
                  return (
                    <section className="media-slot" key={slot.key}>
                      <div className={`media-slot__preview media-slot__preview--${slot.key}`}>
                        {slot.key === "logo" ? (
                          <GameLogoArtwork crop={logoCrop} compact game={game} preview={preview} />
                        ) : slot.key === "boxArt" ? (
                          <BoxArtArtwork crop={boxArtCrop} game={game} preview={preview} />
                        ) : preview?.type.startsWith("image/") ? (
                          <img alt={`${slot.label} preview`} src={preview.url} />
                        ) : slot.key === "artwork" ? (
                          currentMedia ? (
                            <img alt="" src={currentMedia} />
                          ) : (
                            <FallbackArtwork compact game={game} />
                          )
                        ) : (
                          <PlayIcon />
                        )}
                      </div>
                      <div className="media-slot__body">
                        <p>{slot.label}</p>
                        <small>
                          {preview
                            ? `${preview.fileName}${preview.width && preview.height ? ` · ${preview.width}×${preview.height}` : ""}`
                            : slot.description}
                        </small>
                      </div>
                      <div className="media-slot__actions">
                        <label className="file-button">
                          {preview ? "Replace preview" : "Choose preview"}
                          <input
                            accept={slot.accept}
                            aria-label={`Choose ${slot.label.toLowerCase()}`}
                            onChange={(event) => handleFile(slot.key, event)}
                            type="file"
                          />
                        </label>
                        {cropKey ? (
                          <Button
                            aria-label={cropKey === "logo" ? "Crop logo" : "Crop box art"}
                            className="crop-button"
                            isDisabled={cropKey === "logo" ? !logoAvailable : !boxArtAvailable}
                            onPress={() => setCropSlot(cropKey)}
                          >
                            Crop
                          </Button>
                        ) : null}
                      </div>
                    </section>
                  );
                })}
              </div>
            </>
          )}
        </TabPanel>
        <TabPanel className="editor-panel" id="details">
          <div className="details-editor">
            <label>
              <span>Full description</span>
              <textarea
                onChange={(event) =>
                  onDetailsChange({ ...details, description: event.target.value })
                }
                rows={7}
                value={details.description}
              />
            </label>
            <label>
              <span>Wiki URL</span>
              <input
                inputMode="url"
                onChange={(event) => onDetailsChange({ ...details, wikiUrl: event.target.value })}
                placeholder="https://..."
                type="url"
                value={details.wikiUrl}
              />
            </label>
            <div className="resource-editor">
              <p>Additional links</p>
              {details.resources.map((resource, index) => (
                <div className="resource-editor__row" key={resource.id}>
                  <label>
                    <span>Label</span>
                    <input
                      onChange={(event) =>
                        onDetailsChange({
                          ...details,
                          resources: details.resources.map((item, itemIndex) =>
                            itemIndex === index ? { ...item, label: event.target.value } : item,
                          ),
                        })
                      }
                      value={resource.label}
                    />
                  </label>
                  <label>
                    <span>URL</span>
                    <input
                      inputMode="url"
                      onChange={(event) =>
                        onDetailsChange({
                          ...details,
                          resources: details.resources.map((item, itemIndex) =>
                            itemIndex === index ? { ...item, url: event.target.value } : item,
                          ),
                        })
                      }
                      placeholder="https://..."
                      type="url"
                      value={resource.url}
                    />
                  </label>
                </div>
              ))}
            </div>
          </div>
        </TabPanel>
      </Tabs>
    </AppWindow>
  );
}

export function QvPlayApp({ introDurationMs = 3000 }: QvPlayAppProps): ReactElement {
  const prefersReducedMotion = useReducedMotion();
  const [introPhase, setIntroPhase] = useState<IntroPhase>(
    introDurationMs === 0 ? "done" : "running",
  );
  const [searchActive, setSearchActive] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedId, setSelectedId] = useState("the-last-signal");
  const [selectionMotion, setSelectionMotion] = useState(false);
  const [libraryState, setLibraryState] = useState<PreviewState>(() =>
    previewStateFromSearch(window.location.search),
  );
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [editorOpen, setEditorOpen] = useState(false);
  const [editorTab, setEditorTab] = useState<EditorTab>("media");
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsTab, setSettingsTab] = useState<SettingsTab>("settings");
  const [trailersEnabled, setTrailersEnabled] = useState(false);
  const [uiVisible, setUiVisible] = useState(true);
  const [launching, setLaunching] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [previews, setPreviews] = useState<PreviewMedia>({});
  const [logoCropsByGame, setLogoCropsByGame] = useState<MediaCropsById>({});
  const [boxArtCropsByGame, setBoxArtCropsByGame] = useState<MediaCropsById>({});
  const [detailsByGame, setDetailsByGame] = useState<GameDetailsById>({});
  const objectUrls = useRef<string[]>([]);
  const searchInput = useRef<HTMLInputElement>(null);

  const sortedGames = useMemo(() => sortGamesByFavorite(games), []);
  const searchRanking = useMemo(
    () => rankGamesForSearch(sortedGames, searchQuery),
    [searchQuery, sortedGames],
  );
  const searching = searchQuery.trim().length > 0;
  const matchingIds = useMemo(
    () => new Set(searchRanking.matches.map((game) => game.id)),
    [searchRanking.matches],
  );
  const railGames = libraryState === "empty" ? [] : searching ? searchRanking.ordered : sortedGames;
  const navigationGames = railGames;
  const selectedGame =
    navigationGames.find((game) => game.id === selectedId) ?? navigationGames[0] ?? null;
  const selectedDetails = selectedGame
    ? (detailsByGame[selectedGame.id] ?? defaultGameDetails(selectedGame))
    : null;
  const selectedLogoCrop = selectedGame
    ? (logoCropsByGame[selectedGame.id] ?? defaultLogoCrop)
    : defaultLogoCrop;
  const selectedBoxArtCrop = selectedGame
    ? (boxArtCropsByGame[selectedGame.id] ?? defaultBoxArtCrop)
    : defaultBoxArtCrop;

  const selectGame = useCallback((id: string) => {
    setSelectionMotion(true);
    setSelectedId(id);
  }, []);

  const showToast = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(null), 2600);
  }, []);

  const browse = useCallback(
    (direction: -1 | 1) => {
      if (!selectedGame) {
        return;
      }
      const id = nextGameId(navigationGames, selectedGame.id, direction);
      if (id) {
        selectGame(id);
      }
    },
    [navigationGames, selectGame, selectedGame],
  );

  const toggleTrailers = useCallback(() => {
    setTrailersEnabled((enabled) => !enabled);
  }, []);

  const refresh = useCallback(() => {
    setMenuOpen(false);
    setIsRefreshing(true);
    window.setTimeout(() => {
      setIsRefreshing(false);
      setLibraryState("live");
      showToast("Library refreshed.");
    }, 900);
  }, [showToast]);

  const openEditor = useCallback(() => {
    setMenuOpen(false);
    if (selectedGame) {
      setEditorTab("media");
      setEditorOpen(true);
    }
  }, [selectedGame]);

  const openSettings = useCallback((tab: SettingsTab) => {
    setMenuOpen(false);
    setSettingsTab(tab);
    setSettingsOpen(true);
  }, []);

  const play = useCallback(() => {
    if (selectedGame) {
      setLaunching(true);
    }
  }, [selectedGame]);

  const closeSearch = useCallback(() => {
    setSearchActive(false);
    setSearchQuery("");
    setSelectionMotion(false);
    searchInput.current?.blur();
  }, []);

  const activateSearch = useCallback(
    (initialCharacter?: string) => {
      setSearchActive(true);
      if (initialCharacter !== undefined) {
        const nextQuery = searchActive ? `${searchQuery}${initialCharacter}` : initialCharacter;
        setSearchQuery(nextQuery);
        setSelectionMotion(false);
        const firstMatch = rankGamesForSearch(sortedGames, nextQuery).matches[0];
        if (firstMatch) {
          setSelectedId(firstMatch.id);
        }
      }
      window.requestAnimationFrame(() => searchInput.current?.focus());
    },
    [searchActive, searchQuery, sortedGames],
  );

  const toggleInterface = useCallback(() => {
    setUiVisible((visible) => {
      if (visible) {
        setSearchActive(false);
        setSearchQuery("");
        setMenuOpen(false);
        setEditorOpen(false);
        setDetailsOpen(false);
        setSettingsOpen(false);
        setLaunching(false);
      }
      return !visible;
    });
  }, []);

  useEffect(() => {
    if (introDurationMs === 0) {
      return;
    }

    const total = prefersReducedMotion ? Math.min(introDurationMs, 500) : introDurationMs;
    let skipTimer: number | undefined;
    const finish = () => {
      setIntroPhase("done");
      window.removeEventListener("keydown", skip);
    };
    const exitTimer = window.setTimeout(() => setIntroPhase("exiting"), Math.max(0, total - 420));
    const doneTimer = window.setTimeout(finish, total);
    function skip(): void {
      window.clearTimeout(exitTimer);
      window.clearTimeout(doneTimer);
      setIntroPhase("exiting");
      skipTimer = window.setTimeout(finish, prefersReducedMotion ? 80 : 380);
    }

    window.addEventListener("keydown", skip, { once: true });
    return () => {
      window.clearTimeout(exitTimer);
      window.clearTimeout(doneTimer);
      if (skipTimer !== undefined) {
        window.clearTimeout(skipTimer);
      }
      window.removeEventListener("keydown", skip);
    };
  }, [introDurationMs, prefersReducedMotion]);

  useEffect(() => {
    if (!launching) {
      return;
    }
    const timer = window.setTimeout(
      () => {
        setLaunching(false);
        showToast("Launch transition previewed. No game was started.");
      },
      prefersReducedMotion ? 450 : 1450,
    );
    return () => window.clearTimeout(timer);
  }, [launching, prefersReducedMotion, showToast]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (introPhase !== "done") {
        return;
      }

      const lowerKey = event.key.toLocaleLowerCase();
      if (event.ctrlKey && !event.altKey && !event.metaKey && lowerKey === "a") {
        if (!isEditableTarget(event.target)) {
          event.preventDefault();
        }
        return;
      }

      if (event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey && lowerKey === "h") {
        event.preventDefault();
        toggleInterface();
        return;
      }

      if (!uiVisible) {
        return;
      }

      if (event.key === "Escape") {
        if (searchActive) {
          event.preventDefault();
          closeSearch();
          return;
        }
        if (editorOpen) {
          setEditorOpen(false);
        }
        if (detailsOpen) {
          setDetailsOpen(false);
        }
        if (settingsOpen) {
          setSettingsOpen(false);
        }
        if (menuOpen) {
          setMenuOpen(false);
        }
        if (launching) {
          setLaunching(false);
        }
        return;
      }

      if (editorOpen || detailsOpen || settingsOpen || menuOpen || launching) {
        return;
      }

      if (event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey && lowerKey === "s") {
        event.preventDefault();
        activateSearch();
      } else if (event.ctrlKey && !event.altKey && !event.metaKey && lowerKey === "e") {
        event.preventDefault();
        openEditor();
      } else if (event.ctrlKey && !event.altKey && !event.metaKey && lowerKey === "t") {
        event.preventDefault();
        toggleTrailers();
      } else if (event.key === "ArrowLeft") {
        event.preventDefault();
        browse(-1);
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        browse(1);
      } else if (event.key === "Enter") {
        event.preventDefault();
        play();
      } else if (
        !isEditableTarget(event.target) &&
        !event.ctrlKey &&
        !event.altKey &&
        !event.metaKey &&
        /^[\p{L}\p{N}]$/u.test(event.key)
      ) {
        event.preventDefault();
        activateSearch(event.key);
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [
    activateSearch,
    browse,
    closeSearch,
    detailsOpen,
    editorOpen,
    introPhase,
    launching,
    menuOpen,
    openEditor,
    play,
    searchActive,
    settingsOpen,
    toggleInterface,
    toggleTrailers,
    uiVisible,
  ]);

  useEffect(() => {
    const preventContextMenu = (event: MouseEvent) => event.preventDefault();
    window.addEventListener("contextmenu", preventContextMenu);
    return () => window.removeEventListener("contextmenu", preventContextMenu);
  }, []);

  useEffect(() => {
    return () => {
      for (const url of objectUrls.current) {
        URL.revokeObjectURL(url);
      }
    };
  }, []);

  function changeSearch(nextQuery: string): void {
    setSearchQuery(nextQuery);
    setSelectionMotion(false);
    const firstMatch = rankGamesForSearch(sortedGames, nextQuery).matches[0];
    if (nextQuery.trim() && firstMatch) {
      setSelectedId(firstMatch.id);
    }
  }

  function previewMedia(slot: MediaSlot, file: File): void {
    const slotDefinition = slots.find((item) => item.key === slot);
    const valid = slotDefinition?.accept.split(",").includes(file.type) ?? false;
    if (!valid || !selectedGame) {
      showToast(
        slot === "logo"
          ? "Choose a transparent PNG logo."
          : slot === "trailer"
            ? "Choose an MP4 or WebM trailer."
            : "Choose a PNG, JPEG, or WebP image.",
      );
      return;
    }

    const url = URL.createObjectURL(file);
    objectUrls.current.push(url);
    setPreviews((current) => ({
      ...current,
      [selectedGame.id]: {
        ...current[selectedGame.id],
        [slot]: { fileName: file.name, type: file.type, url },
      },
    }));
    if (slot === "logo") {
      setLogoCropsByGame((current) => ({
        ...current,
        [selectedGame.id]: defaultLogoCrop,
      }));
      void normalizeLogoPresentation(file)
        .then((normalized) => {
          if (!normalized) {
            return;
          }
          objectUrls.current.push(normalized.presentationUrl);
          setPreviews((current) => {
            const currentLogo = current[selectedGame.id]?.logo;
            if (currentLogo?.url !== url) {
              return current;
            }
            return {
              ...current,
              [selectedGame.id]: {
                ...current[selectedGame.id],
                logo: { ...currentLogo, ...normalized },
              },
            };
          });
        })
        .catch(() => showToast("Logo loaded, but automatic transparent trimming was unavailable."));
    }
    if (slot === "boxArt") {
      setBoxArtCropsByGame((current) => ({
        ...current,
        [selectedGame.id]: defaultBoxArtCrop,
      }));
    }
    showToast(`${slotDefinition?.label ?? "Media"} preview updated.`);
  }

  function updateSelectedDetails(details: GameDetailsDraft): void {
    if (!selectedGame) {
      return;
    }
    setDetailsByGame((current) => ({ ...current, [selectedGame.id]: details }));
  }

  function updateSelectedLogoCrop(crop: CropTransform): void {
    if (!selectedGame) {
      return;
    }
    setLogoCropsByGame((current) => ({ ...current, [selectedGame.id]: crop }));
  }

  function updateSelectedBoxArtCrop(crop: CropTransform): void {
    if (!selectedGame) {
      return;
    }
    setBoxArtCropsByGame((current) => ({ ...current, [selectedGame.id]: crop }));
  }

  const gamePreviews = selectedGame ? (previews[selectedGame.id] ?? {}) : {};
  const trailerPlaying =
    trailersEnabled && Boolean(gamePreviews.trailer?.url ?? selectedGame?.media.trailer);
  const statusState = isRefreshing ? "refreshing" : libraryState;

  return (
    <main className="qvplay-shell" data-ui-hidden={!uiVisible || undefined}>
      <div className="hero-stage">
        <AnimatePresence initial={false} mode="sync">
          {selectedGame ? (
            <HeroArtwork
              game={selectedGame}
              key={`${selectedGame.id}-${trailerPlaying ? "trailer" : "hero"}`}
              previews={gamePreviews}
              trailersEnabled={trailersEnabled}
            />
          ) : null}
        </AnimatePresence>
        <div className="hero-veil" />
        <div className="hero-grain" />
        {trailerPlaying ? (
          <div className="trailer-indicator">
            <span /> Reel preview · muted
          </div>
        ) : null}
      </div>

      <motion.div
        animate={{
          opacity: introPhase === "done" && uiVisible ? 1 : 0,
          y: introPhase === "done" ? 0 : 14,
        }}
        aria-hidden={!uiVisible}
        className="interface-layer"
        initial={false}
        transition={{ duration: 0.72, ease: [0.2, 0.8, 0.2, 1] }}
      >
        <header className="topbar">
          <MainMenu
            isOpen={menuOpen}
            onEdit={openEditor}
            onInfo={() => openSettings("info")}
            onOpenChange={setMenuOpen}
            onQuit={() => {
              setMenuOpen(false);
              showToast("Quit belongs to the desktop shell and is not connected yet.");
            }}
            onRefresh={refresh}
            onSettings={() => openSettings("settings")}
          />
        </header>
        {searchActive ? (
          <LibrarySearch
            inputRef={searchInput}
            onChange={changeSearch}
            onClose={closeSearch}
            query={searchQuery}
          />
        ) : null}

        {statusState !== "live" ? (
          <StatusScene onRetry={() => setLibraryState("live")} state={statusState} />
        ) : selectedGame ? (
          <section aria-labelledby="selected-game-title" className="hero-copy">
            <AnimatePresence initial={false} mode="wait">
              <motion.div
                animate={{ opacity: 1, y: 0 }}
                className="game-identity"
                initial={{ opacity: 0, y: 12 }}
                key={selectedGame.id}
                transition={{ duration: 0.42, ease: [0.2, 0.8, 0.2, 1] }}
              >
                <p className="hero-mode">{selectedGame.eyebrow}</p>
                <GameWordmark
                  crop={selectedLogoCrop}
                  game={selectedGame}
                  preview={gamePreviews.logo}
                />
                {selectedDetails ? (
                  <GameDescription
                    description={selectedDetails.description}
                    onReadMore={() => setDetailsOpen(true)}
                  />
                ) : null}
              </motion.div>
            </AnimatePresence>
            <div className="hero-actions">
              <Button className="play-button" isDisabled={launching} onPress={play}>
                <PlayIcon />
                Play
              </Button>
              <Button
                aria-label="Edit selected game"
                className="icon-button edit-button"
                onPress={openEditor}
              >
                <EditIcon />
              </Button>
            </div>
          </section>
        ) : searchQuery.trim() ? (
          <SearchEmpty onClear={closeSearch} query={searchQuery.trim()} />
        ) : (
          <StatusScene onRetry={() => setLibraryState("live")} state="empty" />
        )}

        {statusState === "live" && railGames.length > 0 ? (
          <section
            aria-label={searching ? "Game search ranking" : "Game library, favourites first"}
            className="library-rail"
          >
            <Rail
              boxArtCrops={boxArtCropsByGame}
              games={railGames}
              matchingIds={matchingIds}
              onSelect={selectGame}
              previews={previews}
              selectionMotion={selectionMotion}
              searching={searching}
              selectedId={selectedGame?.id ?? null}
            />
          </section>
        ) : null}
      </motion.div>

      {selectedGame ? (
        <MediaEditor
          boxArtCrop={selectedBoxArtCrop}
          details={selectedDetails ?? defaultGameDetails(selectedGame)}
          game={selectedGame}
          isOpen={editorOpen}
          logoCrop={selectedLogoCrop}
          onClose={() => setEditorOpen(false)}
          onBoxArtCropChange={updateSelectedBoxArtCrop}
          onDetailsChange={updateSelectedDetails}
          onLogoCropChange={updateSelectedLogoCrop}
          onPreview={previewMedia}
          onTabChange={setEditorTab}
          previews={gamePreviews}
          tab={editorTab}
        />
      ) : null}
      {selectedGame && selectedDetails ? (
        <GameDetailsPage
          details={selectedDetails}
          game={selectedGame}
          isOpen={detailsOpen}
          onClose={() => setDetailsOpen(false)}
          onEdit={() => {
            setDetailsOpen(false);
            setEditorTab("details");
            setEditorOpen(true);
          }}
        />
      ) : null}
      <SettingsPage
        isOpen={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        onTabChange={setSettingsTab}
        onToggleTrailer={toggleTrailers}
        tab={settingsTab}
        trailersEnabled={trailersEnabled}
      />

      <AnimatePresence>
        {launching && selectedGame ? (
          <motion.section
            animate={{ opacity: 1 }}
            className="launch-preview"
            exit={{ opacity: 0 }}
            initial={{ opacity: 0 }}
            key="launch"
            transition={{ duration: prefersReducedMotion ? 0.08 : 0.52 }}
          >
            <p>Launch preview</p>
            <h2>{selectedGame.title}</h2>
            <span>Native handoff begins after frontend approval.</span>
          </motion.section>
        ) : null}
      </AnimatePresence>

      <AnimatePresence>
        {toast ? (
          <motion.div
            animate={{ opacity: 1, y: 0 }}
            className="toast"
            exit={{ opacity: 0, y: 8 }}
            initial={{ opacity: 0, y: 8 }}
            role="status"
          >
            <span />
            {toast}
          </motion.div>
        ) : null}
      </AnimatePresence>

      <Intro phase={introPhase} />
    </main>
  );
}
