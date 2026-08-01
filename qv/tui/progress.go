package main

import (
	"fmt"
	"math"
	"strings"

	"charm.land/lipgloss/v2"
)

const progressBarWidth = 34

type progressScreen struct {
	Title        string
	Status       string
	Phase        loadPhase
	Progress     float64
	Bar          bool
	HideProgress bool
	NextStep     string
	Hints        []tuiHint
}

type failureScreen struct {
	Subject string
	Message string
	Hints   []tuiHint
}

func renderFailureScreen(screen failureScreen) string {
	title := strings.ToUpper(strings.TrimSpace(screen.Subject))
	title = strings.TrimSuffix(title, " FAILED")
	title = strings.TrimSuffix(title, " ERROR")
	if title == "" {
		title = "ACTION"
	}
	if !strings.Contains(title, "COULD NOT") {
		title += " COULD NOT COMPLETE"
	}

	width := min(48, max(1, canvasW))
	titleLines := wrapDisplayLines([]string{title}, width)
	message := strings.TrimSpace(sanitizeLogLine(screen.Message))
	if message == "" {
		message = "The action did not complete."
	}
	messageLines := wrapDisplayLines([]string{message}, width)

	lines := make([]string, 0, len(titleLines)+len(messageLines)+1)
	for _, line := range titleLines {
		lines = append(lines, centerCanvas(sWhite.Render(line)))
	}
	lines = append(lines, "")
	for _, line := range messageLines {
		lines = append(lines, centerCanvas(sGray.Render(line)))
	}
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
}

func renderProgressScreen(screen progressScreen, mode layoutMode) string {
	if screen.Phase == loadErr {
		return renderFailureScreen(failureScreen{
			Subject: screen.Title,
			Message: screen.Status,
			Hints:   screen.Hints,
		})
	}

	progress := min(1, max(0, screen.Progress))
	if mode == layoutMobile || canvasW < progressBarWidth {
		var content string
		if screen.Phase == loadRun {
			if screen.HideProgress {
				content = centerCanvas(sWhite.Render(strings.ToUpper(screen.Title)))
			} else {
				content = renderCompactProgress(screen.Title, progress)
			}
		} else {
			content = renderCompactResult(screen.Title)
			if screen.Phase == loadOK {
				content = appendSuccessGuidance(content, screen.NextStep)
			}
		}
		return appendTUIHints(content, canvasW, screen.Hints...)
	}

	statusRaw := strings.TrimSpace(screen.Status)
	if statusRaw == "" {
		statusRaw = "working"
	}
	statusLine := sGray.Render(trimDisplay(statusRaw, progressBarWidth))
	if !screen.HideProgress {
		percentRaw := fmt.Sprintf("%3d%%", int(progress*100))
		statusRaw = trimDisplay(statusRaw, progressBarWidth-len(percentRaw)-1)
		gap := progressBarWidth - lipgloss.Width(statusRaw) - len(percentRaw)
		if gap < 1 {
			gap = 1
		}
		statusLine = sGray.Render(statusRaw) +
			strings.Repeat(" ", gap) +
			sMid.Render(percentRaw)
	}

	titleRaw := trimDisplay(
		strings.ToUpper(strings.TrimSpace(screen.Title)),
		max(1, canvasW),
	)
	center := func(value string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, value)
	}

	lines := []string{
		center(sWhite.Render(titleRaw)),
		"",
		center(statusLine),
	}
	if screen.Bar {
		lines = append(lines, "", center(renderProgressBar(screen.Phase, progress)))
	}
	if screen.Phase == loadOK && strings.TrimSpace(screen.NextStep) != "" {
		lines = append(lines, "")
		for _, line := range successGuidanceLines(screen.NextStep) {
			lines = append(lines, center(sGray.Render(line)))
		}
	}
	lines = append(lines, "")
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
}

func appendSuccessGuidance(content, nextStep string) string {
	lines := successGuidanceLines(nextStep)
	if len(lines) == 0 {
		return content
	}
	for index, line := range lines {
		lines[index] = centerCanvas(sGray.Render(line))
	}
	return content + "\n\n" + strings.Join(lines, "\n")
}

func successGuidanceLines(nextStep string) []string {
	nextStep = strings.TrimSpace(nextStep)
	if nextStep == "" {
		return nil
	}
	return wrapDisplayLines(
		[]string{nextStep},
		min(48, max(1, canvasW)),
	)
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

func renderCompactResult(label string) string {
	label = trimDisplay(
		strings.ToUpper(strings.TrimSpace(label)),
		max(1, canvasW),
	)
	return centerCanvas(sWhite.Render(label))
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
