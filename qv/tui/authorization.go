package main

import (
	"strings"

	"charm.land/lipgloss/v2"
)

type authorizationScreen struct {
	Title    string
	Details  string
	Error    string
	Password []rune
	Hints    []tuiHint
}

func renderAuthorizationScreen(screen authorizationScreen, mode layoutMode) string {
	title := centerCanvas(renderAuthorizationTitle(screen.Title, canvasW))
	field := centerCanvas(renderPasswordField(screen.Password, mode))
	details := renderAuthorizationDetails(screen.Details, canvasW, mode)
	errorText := centerCanvas(sRed.Render(trimDisplay(screen.Error, max(1, canvasW))))

	if mode == layoutMobile {
		lines := []string{title, field}
		if screen.Error != "" {
			lines = append(lines, errorText)
		}
		if details != "" {
			lines = append(lines, details)
		}
		return appendTUIHints(
			strings.Join(lines, "\n"),
			canvasW,
			screen.Hints...,
		)
	}

	if mode == layoutTablet {
		lines := []string{title, "", field}
		if screen.Error != "" {
			lines = append(lines, errorText)
		}
		if details != "" {
			lines = append(lines, details)
		}
		return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
	}

	lines := []string{title, "", field}
	if screen.Error != "" {
		lines = append(lines, "", errorText)
	}
	if details != "" {
		lines = append(lines, "", details)
	}
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
}

func renderAuthorizationTitle(label string, width int) string {
	title := strings.TrimSpace(label)
	return sWhite.Render(trimDisplay(title, max(1, width)))
}

func renderAuthorizationDetails(details string, width int, mode layoutMode) string {
	details = strings.TrimSpace(details)
	if details == "" || width < 1 {
		return ""
	}

	label := "Details: "
	valueWidth := max(1, width-lipgloss.Width(label))
	values := wrapDisplayLines([]string{details}, valueWidth)
	if mode != layoutDesktop && len(values) > 1 {
		values = []string{trimDisplay(details, valueWidth)}
	}

	lines := make([]string, 0, len(values))
	for index, value := range values {
		prefix := strings.Repeat(" ", lipgloss.Width(label))
		if index == 0 {
			prefix = label
		}
		lines = append(lines, sDim.Render(prefix)+sGray.Render(value))
	}
	return centerCanvas(strings.Join(lines, "\n"))
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

	return sBright.Render(strings.Repeat("•", count)) +
		sDim.Render(strings.Repeat("─", fieldWidth-count))
}
