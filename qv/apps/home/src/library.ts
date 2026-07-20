import type { Game } from "./games";

export type PreviewState = "live" | "loading" | "empty" | "error";

export function sortGamesByFavorite(allGames: readonly Game[]): Game[] {
  return [...allGames].sort((left, right) => Number(right.favorite) - Number(left.favorite));
}

export function searchGames(allGames: readonly Game[], query: string): Game[] {
  const terms = query.normalize("NFKD").toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);

  if (terms.length === 0) {
    return [...allGames];
  }

  return allGames.filter((game) => {
    const searchable = [game.title, game.publisher, game.developer, ...game.tags]
      .join(" ")
      .normalize("NFKD")
      .toLocaleLowerCase();
    return terms.every((term) => searchable.includes(term));
  });
}

export function rankGamesForSearch(
  allGames: readonly Game[],
  query: string,
): { matches: Game[]; ordered: Game[] } {
  const matches = searchGames(allGames, query);
  const matchingIds = new Set(matches.map((game) => game.id));

  return {
    matches,
    ordered: [...matches, ...allGames.filter((game) => !matchingIds.has(game.id))],
  };
}

export function moveSelection(current: number, direction: -1 | 1, length: number): number {
  if (length === 0) {
    return 0;
  }

  return (current + direction + length) % length;
}

export function formatLastPlayed(value: string | null, now = new Date()): string {
  if (!value) {
    return "Never played";
  }

  const elapsed = Math.max(0, now.getTime() - new Date(value).getTime());
  const days = Math.floor(elapsed / 86_400_000);

  if (days === 0) {
    return "Played today";
  }

  if (days === 1) {
    return "Played yesterday";
  }

  return `Played ${days} days ago`;
}

export function previewStateFromSearch(search: string): PreviewState {
  const state = new URLSearchParams(search).get("state");
  return state === "loading" || state === "empty" || state === "error" ? state : "live";
}

export function nextGameId(
  visibleGames: readonly Game[],
  selectedId: string,
  direction: -1 | 1,
): string | null {
  if (visibleGames.length === 0) {
    return null;
  }

  const current = visibleGames.findIndex((game) => game.id === selectedId);
  const start = current === -1 ? 0 : current;
  return visibleGames[moveSelection(start, direction, visibleGames.length)]?.id ?? null;
}
