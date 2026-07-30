package main

import (
	"strings"

	"charm.land/lipgloss/v2"
)

const authorizationSummaryWidth = 40

type authorizationScreen struct {
	Summary  string
	Error    string
	Password []rune
	Hints    []tuiHint
}

func renderAuthorizationScreen(screen authorizationScreen, mode layoutMode) string {
	title := centerCanvas(renderAuthorizationTitle(canvasW))
	field := centerCanvas(renderPasswordField(screen.Password, mode))
	summary := renderAuthorizationSummary(screen.Summary, canvasW)
	errorText := centerCanvas(sRed.Render(trimDisplay(screen.Error, max(1, canvasW))))

	lines := []string{title, "", field}
	if screen.Error != "" {
		lines = append(lines, errorText)
	}
	if summary != "" {
		lines = append(lines, "", summary)
	}
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
}

func renderAuthorizationTitle(width int) string {
	return sWhite.Render(trimDisplay("Auth Required", max(1, width)))
}

func renderAuthorizationSummary(summary string, width int) string {
	values := authorizationSummaryLines(summary, width)
	lines := make([]string, len(values))
	for index, value := range values {
		lines[index] = centerCanvas(sDim.Render(value))
	}
	return strings.Join(lines, "\n")
}

func authorizationSummaryLines(summary string, width int) []string {
	summary = strings.TrimSpace(summary)
	if summary == "" || width < 1 {
		return nil
	}

	wrapWidth := min(width, authorizationSummaryWidth)
	values := wrapDisplayLines([]string{summary}, wrapWidth)
	if len(values) < 2 || len(strings.Fields(values[len(values)-1])) != 1 {
		return values
	}

	previousWords := strings.Fields(values[len(values)-2])
	if len(previousWords) < 2 {
		return values
	}
	tail := previousWords[len(previousWords)-1] + " " + values[len(values)-1]
	if lipgloss.Width(tail) > wrapWidth {
		return values
	}
	values[len(values)-2] = strings.Join(previousWords[:len(previousWords)-1], " ")
	values[len(values)-1] = tail
	return values
}

func renderPasswordField(password []rune, mode layoutMode) string {
	fieldWidth := 28
	if mode == layoutTablet {
		fieldWidth = 18
	}
	if mode == layoutMobile {
		fieldWidth = 10
	}

	count := min(len(password), fieldWidth)
	if count == 0 {
		return sDim.Render(strings.Repeat("─", fieldWidth))
	}

	return sBright.Render(strings.Repeat("•", count))
}
