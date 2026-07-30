package main

import (
	"fmt"
	"math"
	"strings"

	"charm.land/lipgloss/v2"
)

const progressBarWidth = 34

type progressScreen struct {
	Title    string
	Status   string
	Phase    loadPhase
	Progress float64
	Bar      bool
	Hints    []tuiHint
}

func renderProgressScreen(screen progressScreen, mode layoutMode) string {
	progress := min(1, max(0, screen.Progress))
	if mode == layoutMobile || canvasW < progressBarWidth {
		var content string
		if screen.Phase == loadRun {
			content = renderCompactProgress(screen.Title, progress)
		} else {
			content = renderCompactResult(screen.Title, screen.Phase)
		}
		return appendTUIHints(content, canvasW, screen.Hints...)
	}

	percentRaw := fmt.Sprintf("%3d%%", int(progress*100))
	statusRaw := strings.TrimSpace(screen.Status)
	if statusRaw == "" {
		statusRaw = "working"
	}
	statusRaw = trimDisplay(statusRaw, progressBarWidth-len(percentRaw)-1)
	gap := progressBarWidth - lipgloss.Width(statusRaw) - len(percentRaw)
	if gap < 1 {
		gap = 1
	}

	titleStyle := sWhite
	statusStyle := sGray
	if screen.Phase == loadErr {
		titleStyle = sRed
		statusStyle = sRed
	}
	titleRaw := trimDisplay(
		strings.ToUpper(strings.TrimSpace(screen.Title)),
		max(1, canvasW),
	)
	statusLine := statusStyle.Render(statusRaw) +
		strings.Repeat(" ", gap) +
		sMid.Render(percentRaw)
	center := func(value string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, value)
	}

	lines := []string{
		center(titleStyle.Render(titleRaw)),
		"",
		center(statusLine),
	}
	if screen.Bar {
		lines = append(lines, "", center(renderProgressBar(screen.Phase, progress)))
	}
	lines = append(lines, "")
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
}

func renderCompactProgress(label string, progress float64) string {
	percent := fmt.Sprintf("%d%%", int(progress*100))
	suffixWidth := lipgloss.Width("  ·  " + percent)
	label = trimDisplay(
		strings.ToUpper(strings.TrimSpace(label)),
		max(1, canvasW-suffixWidth),
	)
	return centerCanvas(
		sWhite.Render(label) +
			"  " + sDim.Render("·") + "  " +
			sDeepRed.Render(percent),
	)
}

func renderCompactResult(label string, phase loadPhase) string {
	label = trimDisplay(
		strings.ToUpper(strings.TrimSpace(label)),
		max(1, canvasW),
	)
	style := sWhite
	if phase == loadErr {
		style = sRed
	}
	return centerCanvas(style.Render(label))
}

func renderProgressBar(phase loadPhase, progress float64) string {
	progress = min(1, max(0, progress))
	full := int(math.Round(progress * float64(progressBarWidth)))
	if full > progressBarWidth {
		full = progressBarWidth
	}

	var bar strings.Builder
	for i := 0; i < full; i++ {
		bar.WriteString(sDeepRed.Render("━"))
	}
	if phase == loadRun && full > 0 && full < progressBarWidth {
		bar.WriteString(sRed.Render("━"))
		full++
	}
	for i := full; i < progressBarWidth; i++ {
		bar.WriteString(sDim.Render("─"))
	}
	return bar.String()
}
