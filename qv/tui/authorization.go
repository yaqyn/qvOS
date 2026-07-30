package main

import (
	"strings"
)

type authorizationScreen struct {
	Details  string
	Error    string
	Password []rune
	Hints    []tuiHint
}

func renderAuthorizationScreen(screen authorizationScreen, mode layoutMode) string {
	title := centerCanvas(renderAuthorizationTitle(canvasW))
	field := centerCanvas(renderPasswordField(screen.Password, mode))
	details := renderAuthorizationDetails(screen.Details, canvasW, mode)
	errorText := centerCanvas(sRed.Render(trimDisplay(screen.Error, max(1, canvasW))))

	lines := []string{title, "", field}
	if screen.Error != "" {
		lines = append(lines, errorText)
	}
	if details != "" {
		lines = append(lines, "", details)
	}
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
}

func renderAuthorizationTitle(width int) string {
	return sWhite.Render(trimDisplay("Auth Required", max(1, width)))
}

func renderAuthorizationDetails(details string, width int, mode layoutMode) string {
	details = strings.TrimSpace(details)
	if details == "" || width < 1 {
		return ""
	}

	values := wrapDisplayLines([]string{details}, width)
	if mode != layoutDesktop && len(values) > 1 {
		values = []string{trimDisplay(details, width)}
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
