package main

import (
	"strings"

	"charm.land/lipgloss/v2"
)

type logPanelScreen struct {
	Lines       []string
	Width       int
	Height      int
	VisibleRows int
	Scroll      int
	Empty       string
	Border      bool
}

func renderLogPanel(screen logPanelScreen) string {
	width := max(1, screen.Width)
	visibleRows := max(1, screen.VisibleRows)
	contentWidth := width - 2
	if screen.Border {
		contentWidth -= 2
	}
	contentWidth = max(1, contentWidth)

	lines, scrollOffset := visibleTUILogLines(
		screen.Lines,
		visibleRows,
		screen.Scroll,
		screen.Empty,
	)
	for index, line := range lines {
		lines[index] = trimDisplay(line, contentWidth)
	}

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
	return appendTUILogSwitchCue(panel, width, scrollOffset)
}
