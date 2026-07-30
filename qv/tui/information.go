package main

import (
	"strings"
	"unicode"

	"charm.land/lipgloss/v2"
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
	sourceLines := formatInformationLines(
		screen.Title,
		screen.Lines,
		contentWidth,
		screen.Error,
	)
	if len(sourceLines) == 0 {
		sourceLines = formatInformationLines(
			screen.Title,
			[]string{screen.Empty},
			contentWidth,
			screen.Error,
		)
	}
	lines, _ := visibleTUILogLines(
		sourceLines,
		max(1, screen.VisibleRows),
		screen.Scroll,
		"",
	)

	titleStyle := sWhite
	if screen.Error {
		titleStyle = sRed
	}
	title := centerCanvas(titleStyle.Render(trimDisplay(
		strings.ToUpper(strings.TrimSpace(screen.Title)),
		width,
	)))
	contentStyle := lipgloss.NewStyle().
		Width(width).
		Padding(0, 1)
	content := contentStyle.Render(strings.Join(lines, "\n"))

	return appendTUIHints(
		strings.Join([]string{title, "", content}, "\n"),
		canvasW,
		screen.Hints...,
	)
}

func formatInformationLines(
	title string,
	lines []string,
	width int,
	isError bool,
) []string {
	width = max(1, width)
	if isError {
		return styleWrappedInformation(lines, width, sRed)
	}

	formatted := make([]string, 0, len(lines)*3)
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			if len(formatted) > 0 && formatted[len(formatted)-1] != "" {
				formatted = append(formatted, "")
			}
			continue
		}

		label, value, ok := splitInformationField(line)
		if !ok {
			formatted = append(
				formatted,
				styleWrappedInformation([]string{line}, width, sBright)...,
			)
			continue
		}
		if len(formatted) > 0 && formatted[len(formatted)-1] != "" {
			formatted = append(formatted, "")
		}
		if strings.EqualFold(label, title) {
			label = "Status"
		}
		formatted = append(
			formatted,
			sDeepRed.Render("▐")+" "+sRed.Render(strings.ToUpper(label)),
		)
		formatted = append(formatted, formatInformationValue(value, width)...)
	}
	for len(formatted) > 0 && formatted[len(formatted)-1] == "" {
		formatted = formatted[:len(formatted)-1]
	}
	return formatted
}

func splitInformationField(line string) (string, string, bool) {
	label, value, found := strings.Cut(line, ":")
	label = strings.TrimSpace(label)
	value = strings.TrimSpace(value)
	if !found || label == "" || value == "" || strings.HasPrefix(value, "//") ||
		len([]rune(label)) > 40 {
		return "", "", false
	}
	for _, character := range label {
		if unicode.IsLetter(character) || unicode.IsDigit(character) ||
			unicode.IsSpace(character) || strings.ContainsRune("-_/()", character) {
			continue
		}
		return "", "", false
	}
	return label, value, true
}

func formatInformationValue(value string, width int) []string {
	primary := value
	qualifier := ""
	if before, after, found := strings.Cut(value, " - "); found {
		primary = strings.TrimSpace(before)
		qualifier = strings.TrimSpace(after)
	}
	primary, detail := splitInformationDetail(primary)

	primaryStyle := sWhite
	if qualifier != "" && len(strings.Fields(primary)) <= 2 {
		primaryStyle = sHot
	}
	formatted := styleWrappedInformation([]string{primary}, width, primaryStyle)
	if qualifier != "" {
		formatted = append(
			formatted,
			styleWrappedInformation([]string{qualifier}, width, sMid)...,
		)
	}
	if detail != "" {
		formatted = append(
			formatted,
			styleWrappedInformation([]string{detail}, width, sRed)...,
		)
	}
	return formatted
}

func splitInformationDetail(value string) (string, string) {
	open := strings.LastIndex(value, " (")
	if open < 0 || !strings.HasSuffix(value, ")") {
		return value, ""
	}
	return strings.TrimSpace(value[:open]), strings.TrimSpace(value[open+2 : len(value)-1])
}

func styleWrappedInformation(
	lines []string,
	width int,
	style lipgloss.Style,
) []string {
	wrapped := wrapDisplayLines(lines, width)
	for index, line := range wrapped {
		wrapped[index] = style.Render(line)
	}
	return wrapped
}
