package main

import (
	"strings"

	"charm.land/lipgloss/v2"
)

type logPanelScreen struct {
	Lines         []string
	Width         int
	Height        int
	VisibleRows   int
	Scroll        int
	Empty         string
	Border        bool
	HideSwitchCue bool
}

type responsiveLogWidth struct {
	Width      int
	Height     int
	CenterMax  int
	Maximum    int
	Terminal   bool
	Fullscreen bool
	ModelSlot  bool
	SideRight  bool
	Border     bool
}

func responsiveTUILogContentWidth(screen responsiveLogWidth) int {
	if screen.Terminal {
		return terminalOutputContentWidth(screen.Width)
	}

	panelWidth := min(screen.CenterMax, max(1, screen.Width-4))
	if isSideComposition(screen.Width, screen.Height, screen.Fullscreen) {
		leftWidth, rightWidth := sideColumnWidths(screen.Width)
		panelWidth = leftWidth
		if screen.SideRight {
			panelWidth = rightWidth
		}
	} else if screen.ModelSlot {
		panelWidth, _, _ = fitCenterStageCanvas(
			screen.Width,
			screen.Height,
			fullCanvasReserveRows,
		)
	}
	panelWidth = min(screen.Maximum, max(1, panelWidth))
	return tuiLogPanelContentWidth(panelWidth, screen.Border)
}

func applyTerminalFrame(lines []string, cursor int, frame terminalFrame) ([]string, int, int) {
	before := len(lines)
	if frame.clear {
		return nil, 0, -before
	}
	cursor = max(0, cursor+frame.move)
	if !frame.update {
		return lines, cursor, 0
	}
	for len(lines) <= cursor {
		lines = append(lines, "")
	}
	lines[cursor] = frame.line
	if frame.commit {
		cursor++
	}
	return lines, cursor, len(lines) - before
}

func renderLogPanel(screen logPanelScreen) string {
	width := max(1, screen.Width)
	visibleRows := max(1, screen.VisibleRows)
	contentWidth := tuiLogPanelContentWidth(width, screen.Border)
	rows := wrapTUILogLines(screen.Lines, contentWidth)

	lines, scrollOffset := visibleTUILogLines(
		rows,
		visibleRows,
		screen.Scroll,
		screen.Empty,
	)

	style := lipgloss.NewStyle().
		Width(width).
		Foreground(lipgloss.Color(mid)).
		Padding(0, 1)
	if screen.Height > 0 {
		style = style.Height(screen.Height)
	}
	if screen.Border {
		style = style.
			Border(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color(deepRed))
	}

	panel := style.Render(strings.Join(lines, "\n"))
	if screen.HideSwitchCue {
		return panel
	}
	return appendTUILogSwitchCue(panel, width, scrollOffset)
}

func actionLogPanelHeight(mode layoutMode, terminalHeight int) int {
	height := 18
	if mode == layoutTablet {
		height = 16
	}
	if mode == layoutMobile {
		height = 7
	}
	if terminalHeight > 0 {
		heightLimit := terminalHeight - 4
		if mode == layoutDesktop {
			heightLimit = terminalHeight - 12
		}
		if heightLimit < 3 {
			heightLimit = 3
		}
		if height > heightLimit {
			height = heightLimit
		}
	}
	return height
}

func actionLogVisibleRows(mode layoutMode, terminalHeight int) int {
	return max(1, actionLogPanelHeight(mode, terminalHeight)-2)
}

func renderActionLogPanel(
	lines []string,
	width int,
	mode layoutMode,
	terminalHeight int,
	scroll int,
	empty string,
) string {
	height := actionLogPanelHeight(mode, terminalHeight)
	return renderLogPanel(logPanelScreen{
		Lines:       lines,
		Width:       min(logSideRightMax, max(1, width)),
		Height:      height,
		VisibleRows: actionLogVisibleRows(mode, terminalHeight),
		Scroll:      scroll,
		Empty:       empty,
		Border:      true,
	})
}

func tuiLogPanelContentWidth(width int, border bool) int {
	contentWidth := width - 2
	if border {
		contentWidth -= 2
	}
	return max(1, contentWidth)
}

func wrapTUILogLines(lines []string, width int) []string {
	if len(lines) == 0 {
		return nil
	}
	return wrapDisplayLines(lines, max(1, width))
}

func fitsTUILogModelSlot(width, height int) bool {
	return width >= 20 && height >= 6
}

func fullscreenTUILogUsesModelSlot(active bool, width, height int) bool {
	if !active {
		return false
	}
	stageWidth, stageHeight, _ := fitCenterStageCanvas(
		width,
		height,
		fullCanvasReserveRows,
	)
	return fitsTUILogModelSlot(stageWidth, stageHeight)
}

func placeTUILogInCanvas(log string, width, height int) string {
	return lipgloss.Place(
		max(1, width),
		max(1, height),
		lipgloss.Center,
		lipgloss.Center,
		log,
	)
}
