package main

import (
	"strings"
)

type authorizationScreen struct {
	Summary  string
	Error    string
	Password []rune
	Hints    []tuiHint
}

func renderAuthorizationScreen(screen authorizationScreen, mode layoutMode) string {
	title := centerCanvas(renderAuthorizationTitle(canvasW))
	field := centerCanvas(renderPasswordField(screen.Password, mode))
	summary := renderAuthorizationSummary(screen.Summary, canvasW, mode)
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

func renderAuthorizationSummary(summary string, width int, mode layoutMode) string {
	summary = strings.TrimSpace(summary)
	if summary == "" || width < 1 {
		return ""
	}

	values := wrapDisplayLines([]string{summary}, width)
	if mode != layoutDesktop && len(values) > 1 {
		values = []string{trimDisplay(summary, width)}
	}

	lines := make([]string, len(values))
	for index, value := range values {
		lines[index] = centerCanvas(sDim.Render(value))
	}
	return strings.Join(lines, "\n")
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
