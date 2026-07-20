import { describe, expect, it } from "vitest";
import { games } from "./games";
import {
  formatLastPlayed,
  moveSelection,
  nextGameId,
  previewStateFromSearch,
  rankGamesForSearch,
  searchGames,
  sortGamesByFavorite,
} from "./library";

describe("qvPLAY library model", () => {
  it("gives every game four independent media surfaces", () => {
    for (const game of games) {
      expect(Object.keys(game.media)).toEqual(["logo", "boxArt", "artwork", "trailer"]);
      expect(game.media.logo === null || typeof game.media.logo === "string").toBe(true);
      expect(game.media.boxArt === null || typeof game.media.boxArt === "string").toBe(true);
      expect(game.media.artwork === null || typeof game.media.artwork === "string").toBe(true);
      expect(game.media.trailer === null || typeof game.media.trailer === "string").toBe(true);
    }
  });

  it("sorts Favorites first without splitting or duplicating the library", () => {
    const sorted = sortGamesByFavorite(games);

    expect(sorted).toHaveLength(games.length);
    expect(sorted.slice(0, 4).every((game) => game.favorite)).toBe(true);
    expect(sorted.slice(4).every((game) => !game.favorite)).toBe(true);
    expect(new Set(sorted.map((game) => game.id)).size).toBe(games.length);
  });

  it("searches the whole library by title, tags, publisher, and developer", () => {
    expect(searchGames(games, "Ashen Circuit").map((game) => game.id)).toEqual(["ashen-circuit"]);
    expect(searchGames(games, "mechs").map((game) => game.id)).toEqual(["ashen-circuit"]);
    expect(searchGames(games, "Cinder Assembly").map((game) => game.id)).toEqual(["ashen-circuit"]);
    expect(searchGames(games, "Foundry Nine").map((game) => game.id)).toEqual(["ashen-circuit"]);
  });

  it("ranks matches first without removing any rail cards", () => {
    const sorted = sortGamesByFavorite(games);
    const ranking = rankGamesForSearch(sorted, "Foundry Nine");

    expect(ranking.matches.map((game) => game.id)).toEqual(["ashen-circuit"]);
    expect(ranking.ordered).toHaveLength(games.length);
    expect(ranking.ordered[0]?.id).toBe("ashen-circuit");
    expect(new Set(ranking.ordered.map((game) => game.id)).size).toBe(games.length);
  });

  it("wraps rail navigation in both directions", () => {
    expect(moveSelection(0, -1, 6)).toBe(5);
    expect(moveSelection(5, 1, 6)).toBe(0);
    expect(moveSelection(0, 1, 0)).toBe(0);
  });

  it("selects the next visible game by stable id", () => {
    const visible = sortGamesByFavorite(games);

    expect(nextGameId(visible, "the-last-signal", 1)).toBe("black-tide");
    expect(nextGameId(visible, "the-last-signal", -1)).toBe("null-meridian");
  });

  it("formats last-played metadata without inventing activity", () => {
    const now = new Date("2026-07-19T12:00:00.000Z");

    expect(formatLastPlayed("2026-07-19T03:00:00.000Z", now)).toBe("Played today");
    expect(formatLastPlayed("2026-07-18T03:00:00.000Z", now)).toBe("Played yesterday");
    expect(formatLastPlayed(null, now)).toBe("Never played");
  });

  it("exposes explicit preview states without routing machinery", () => {
    expect(previewStateFromSearch("?state=loading")).toBe("loading");
    expect(previewStateFromSearch("?state=empty")).toBe("empty");
    expect(previewStateFromSearch("?state=error")).toBe("error");
    expect(previewStateFromSearch("?state=unknown")).toBe("live");
  });
});
