import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { QvPlayApp } from "./App";

describe("qvPLAY interaction surface", () => {
  it("reveals the library when the three-second intro finishes", () => {
    vi.useFakeTimers();
    render(<QvPlayApp />);

    expect(screen.getByText("qvHOME / PLAY")).toBeInTheDocument();
    act(() => vi.advanceTimersByTime(3000));
    expect(screen.queryByText("qvHOME / PLAY")).not.toBeInTheDocument();
    vi.useRealTimers();
  });

  it("skips the intro through a short fade on any key", () => {
    vi.useFakeTimers();
    render(<QvPlayApp />);

    fireEvent.keyDown(window, { key: "x" });
    expect(screen.getByText("qvHOME / PLAY")).toBeInTheDocument();
    act(() => vi.advanceTimersByTime(380));
    expect(screen.queryByText("qvHOME / PLAY")).not.toBeInTheDocument();
    vi.useRealTimers();
  });

  it("browses the favourites-first library with arrow keys", () => {
    render(<QvPlayApp introDurationMs={0} />);

    expect(screen.getByRole("heading", { name: "The Last Signal" })).toBeInTheDocument();
    expect(screen.queryByText("Played yesterday")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("qvPLAY")).not.toBeInTheDocument();
    expect(screen.getByText("Solo Play — Campaign")).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "ArrowRight" });
    expect(screen.getByRole("heading", { name: "Black Tide" })).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "ArrowLeft" });
    expect(screen.getByRole("heading", { name: "The Last Signal" })).toBeInTheDocument();
  });

  it("shows one continuous box-art rail with favourites first", () => {
    render(<QvPlayApp introDurationMs={0} />);

    const cards = screen.getAllByRole("button", { name: /^Select / });
    expect(cards).toHaveLength(8);
    expect(cards.map((card) => card.getAttribute("aria-label"))).toEqual([
      "Select The Last Signal",
      "Select Black Tide",
      "Select Hollow Sky",
      "Select Night Protocol",
      "Select Ashen Circuit",
      "Select Iron Veil",
      "Select Static Bloom",
      "Select Null Meridian",
    ]);
    expect(screen.queryByRole("tab")).not.toBeInTheDocument();
  });

  it("keeps library covers out of Tab focus without changing the selected game", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    const cards = screen.getAllByRole("button", { name: /^Select / });
    expect(cards.every((card) => card.tabIndex === -1)).toBe(true);
    await user.tab();
    expect(screen.getByRole("button", { name: "Open qvPLAY menu" })).toHaveFocus();
    expect(screen.getByRole("heading", { name: "The Last Signal" })).toBeInTheDocument();
  });

  it("reveals search on typing and searches globally across game metadata", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    expect(screen.queryByRole("searchbox", { name: "Search games" })).not.toBeInTheDocument();
    fireEvent.keyDown(window, { key: "F" });
    const searchbox = screen.getByRole("searchbox", { name: "Search games" });
    expect(searchbox).toHaveValue("F");
    await user.type(searchbox, "oundry Nine");

    expect(screen.getByRole("heading", { name: "Ashen Circuit" })).toBeInTheDocument();
    const cards = screen.getAllByRole("button", { name: /^Select / });
    expect(cards).toHaveLength(8);
    expect(cards[0]).toHaveAccessibleName("Select Ashen Circuit");
    expect(cards[0]).toHaveAttribute("data-match", "true");
    expect(cards[1]).toHaveAttribute("data-match", "false");
    expect(screen.getByRole("navigation", { name: "Game library" })).not.toHaveAttribute(
      "data-selection-motion",
    );
  });

  it("keeps search inside the live rail and permits real-time selection", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    fireEvent.keyDown(window, { key: "F" });
    await user.type(screen.getByRole("searchbox", { name: "Search games" }), "oundry Nine");
    await user.click(screen.getByRole("button", { name: "Select Black Tide" }));

    expect(screen.getByRole("heading", { name: "Black Tide" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Select Black Tide" })).toHaveAttribute(
      "data-selected",
      "true",
    );
    expect(screen.getByRole("navigation", { name: "Game library" })).toHaveAttribute(
      "data-selection-motion",
      "true",
    );
  });

  it("opens hidden search only from typing or Shift+S", () => {
    render(<QvPlayApp introDurationMs={0} />);

    expect(screen.queryByRole("button", { name: /Search games/i })).not.toBeInTheDocument();
    fireEvent.keyDown(window, { key: "S", shiftKey: true });
    expect(screen.getByRole("searchbox", { name: "Search games" })).toHaveValue("");
  });

  it("opens and closes the media editor from the keyboard", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    fireEvent.keyDown(window, { key: "e", ctrlKey: true });
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "The Last Signal" })).toBeInTheDocument();
    expect(screen.getByLabelText("Choose logo / name")).toHaveAttribute("accept", "image/png");
    expect(screen.getByLabelText("Choose box art")).toHaveAttribute(
      "accept",
      "image/png,image/jpeg,image/webp",
    );
    expect(screen.getByLabelText("Choose artwork")).toHaveAttribute(
      "accept",
      "image/png,image/jpeg,image/webp",
    );
    expect(screen.getByLabelText("Choose trailer")).toHaveAttribute(
      "accept",
      "video/mp4,video/webm",
    );
    expect(document.querySelector(".app-window__header")).toBeInTheDocument();
    expect(document.querySelector(".app-window__body")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Close media editor" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
  });

  it("normalizes logo presentation through non-destructive crop controls", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    fireEvent.keyDown(window, { key: "e", ctrlKey: true });
    const cropButton = screen.getByRole("button", { name: "Crop logo" });
    expect(cropButton).toBeDisabled();

    await user.upload(
      screen.getByLabelText("Choose logo / name"),
      new File(["logo"], "game-logo.png", { type: "image/png" }),
    );
    expect(cropButton).toBeEnabled();
    await user.click(cropButton);

    expect(screen.getByLabelText("Logo crop preview")).toBeInTheDocument();
    const scale = screen.getByLabelText("Logo crop scale");
    fireEvent.change(scale, { target: { value: "1.2" } });
    expect(screen.getByText("120%")).toBeInTheDocument();
    expect(screen.getByText(/3200×800 recommended/)).toBeInTheDocument();
    const logoPreviews = document.querySelectorAll<HTMLImageElement>(".game-logo-artwork img");
    expect(logoPreviews.length).toBeGreaterThan(0);
    expect([...logoPreviews].every((image) => image.style.transform.includes("scale(1.2)"))).toBe(
      true,
    );
  });

  it("previews box-art cropping in both rail shapes", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    fireEvent.keyDown(window, { key: "e", ctrlKey: true });
    await user.click(screen.getByRole("button", { name: "Crop box art" }));

    expect(screen.getByLabelText("Box art crop preview")).toBeInTheDocument();
    expect(screen.getByText(/1600×2000 recommended/)).toBeInTheDocument();
    const scale = screen.getByLabelText("Box art crop scale");
    fireEvent.change(scale, { target: { value: "1.25" } });
    expect(screen.getByText("125%")).toBeInTheDocument();
    const selectedCover = document.querySelector<HTMLImageElement>(
      '[data-game-id="the-last-signal"] .box-artwork',
    );
    expect(selectedCover?.style.scale).toBe("1.25");
  });

  it("moves global trailer controls into Settings and keeps Ctrl+T available", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    expect(screen.queryByRole("button", { name: /Trailers/i })).not.toBeInTheDocument();
    fireEvent.keyDown(window, { key: "t", ctrlKey: true });
    await user.click(screen.getByRole("button", { name: "Open qvPLAY menu" }));
    await user.click(screen.getByRole("menuitem", { name: "Settings" }));
    expect(screen.getByRole("button", { name: "Toggle trailer previews" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await user.click(screen.getByRole("button", { name: "Close settings" }));
    await waitFor(() =>
      expect(screen.queryByRole("button", { name: "Close settings" })).not.toBeInTheDocument(),
    );
    fireEvent.keyDown(window, { key: "ArrowRight" });
    await user.click(screen.getByRole("button", { name: "Open qvPLAY menu" }));
    await user.click(screen.getByRole("menuitem", { name: "Settings" }));
    expect(screen.getByRole("button", { name: "Toggle trailer previews" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    expect(
      screen.getByText("Playback preferences apply across the whole library."),
    ).toBeInTheDocument();
  });

  it("hides and restores all interface dimming with Shift+H", () => {
    render(<QvPlayApp introDurationMs={0} />);

    const shell = document.querySelector(".qvplay-shell");
    fireEvent.keyDown(window, { key: "H", shiftKey: true });
    expect(shell).toHaveAttribute("data-ui-hidden", "true");
    expect(document.querySelector(".interface-layer")).toHaveAttribute("aria-hidden", "true");
    fireEvent.keyDown(window, { key: "H", shiftKey: true });
    expect(shell).not.toHaveAttribute("data-ui-hidden");
  });

  it("opens full game details and edits its description and links from the edit page", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    await user.click(screen.getByRole("button", { name: "Read more" }));
    expect(screen.getByRole("heading", { name: "The Last Signal" })).toBeInTheDocument();
    expect(screen.getByText("Wiki link not added")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Edit details & links" }));
    expect(screen.getByRole("tab", { name: "Details & links" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    expect(screen.getByDisplayValue(/Carry one impossible transmission/)).toBeInTheDocument();
    expect(screen.getByDisplayValue("Marketplace or companion")).toBeInTheDocument();
  });

  it("reserves plain letters and numbers for search instead of actions", () => {
    render(<QvPlayApp introDurationMs={0} />);

    fireEvent.keyDown(window, { key: "e" });
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(screen.getByRole("searchbox", { name: "Search games" })).toHaveValue("e");
  });

  it("suppresses browser chrome gestures outside editable fields", () => {
    render(<QvPlayApp introDurationMs={0} />);

    const contextMenu = new MouseEvent("contextmenu", { bubbles: true, cancelable: true });
    window.dispatchEvent(contextMenu);
    expect(contextMenu.defaultPrevented).toBe(true);

    const selectAll = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      ctrlKey: true,
      key: "a",
    });
    window.dispatchEvent(selectAll);
    expect(selectAll.defaultPrevented).toBe(true);
  });

  it("keeps module switching visibly disabled in the menu", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    await user.click(screen.getByRole("button", { name: "Open qvPLAY menu" }));
    const switchItem = screen.getByRole("menuitem", { name: "Switch — qvPLAY only" });
    expect(switchItem).toHaveAttribute("aria-disabled", "true");
    expect(switchItem.querySelector(".menu-item__spacer")).toBeInTheDocument();
  });

  it("keeps the complete control guide in menu-accessible Info", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    expect(screen.queryByLabelText("Keyboard controls")).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Open qvPLAY menu" }));
    await user.click(screen.getByRole("menuitem", { name: "Info and controls" }));
    expect(screen.getByRole("tab", { name: "Info & controls" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    expect(screen.getByText("Arrow Left / Right")).toBeInTheDocument();
    expect(screen.getByText("Shift + H")).toBeInTheDocument();
    expect(
      screen.getByText("Letters and numbers always begin a library search."),
    ).toBeInTheDocument();
  });

  it("labels Play as a non-launching frontend preview", async () => {
    const user = userEvent.setup();
    render(<QvPlayApp introDurationMs={0} />);

    await user.click(screen.getByRole("button", { name: "Play" }));
    expect(screen.getByText("Native handoff begins after frontend approval.")).toBeInTheDocument();
  });
});
