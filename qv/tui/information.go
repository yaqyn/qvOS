package main

import (
	"strings"
)

type informationScreen struct {
	Title       string
	Lines       []string
	Empty       string
	Error       bool
	Width       int
	VisibleRows int
	Scroll      int
	Hints       []tuiHint
}

func renderInformationScreen(screen informationScreen) string {
	width := max(1, screen.Width)
	contentWidth := max(1, width-2)
	lines, _ := visibleTUILogLines(
		screen.Lines,
		max(1, screen.VisibleRows),
		screen.Scroll,
		screen.Empty,
	)
	for index, line := range lines {
		lines[index] = trimDisplay(line, contentWidth)
	}

	titleStyle := sWhite
	contentStyle := sGray
	if screen.Error {
		titleStyle = sRed
		contentStyle = sRed
	}
	title := centerCanvas(titleStyle.Render(trimDisplay(
		strings.ToUpper(strings.TrimSpace(screen.Title)),
		width,
	)))
	contentStyle = contentStyle.
		Width(width).
		Padding(0, 1)
	content := contentStyle.Render(strings.Join(lines, "\n"))

	return appendTUIHints(
		strings.Join([]string{title, "", content}, "\n"),
		canvasW,
		screen.Hints...,
	)
}
