package main

import (
	"strings"
)

type authorizationScreen struct {
	Title        string
	Status       string
	StatusError  bool
	Password     []rune
	TabletStatus bool
	Hints        []tuiHint
}

func renderAuthorizationScreen(screen authorizationScreen, mode layoutMode) string {
	title := centerCanvas(renderAuthorizationTitle(screen.Title, canvasW))
	field := centerCanvas(renderPasswordField(screen.Password, mode))
	statusStyle := sGray
	if screen.StatusError {
		statusStyle = sRed
	}
	status := centerCanvas(statusStyle.Render(screen.Status))

	if mode == layoutMobile {
		lines := []string{title, ""}
		if screen.StatusError {
			lines = append(lines, status)
		}
		lines = append(lines, field)
		return appendTUIHints(
			strings.Join(lines, "\n"),
			canvasW,
			screen.Hints...,
		)
	}

	if mode == layoutTablet {
		lines := []string{title, ""}
		if screen.TabletStatus || screen.StatusError {
			lines = append(lines, status)
		}
		lines = append(lines, field)
		return appendTUIHints(strings.Join(lines, "\n"), canvasW, screen.Hints...)
	}

	content := strings.Join([]string{
		title,
		"",
		status,
		"",
		field,
		"",
	}, "\n")
	return appendTUIHints(content, canvasW, screen.Hints...)
}

func renderAuthorizationTitle(label string, width int) string {
	title := strings.ToUpper(strings.TrimSpace(label)) + " AUTHORIZATION"
	return sWhite.Render(trimDisplay(title, max(1, width)))
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
