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

type informationEntry struct {
	Label string
	Value string
	Raw   string
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
	blockWidth := 1
	for _, line := range lines {
		blockWidth = max(blockWidth, lipgloss.Width(line))
	}
	content := lipgloss.PlaceHorizontal(
		width,
		lipgloss.Center,
		lipgloss.NewStyle().
			Width(min(width, blockWidth)).
			Render(strings.Join(lines, "\n")),
	)

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

	entries := make([]informationEntry, 0, len(lines))
	labelWidth := 0
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			entries = append(entries, informationEntry{})
			continue
		}

		label, value, ok := splitInformationField(line)
		if !ok {
			entries = append(entries, informationEntry{Raw: line})
			continue
		}
		if strings.EqualFold(label, title) {
			label = "Status"
		}
		label = strings.ToUpper(label)
		labelWidth = max(labelWidth, lipgloss.Width(label))
		entries = append(entries, informationEntry{Label: label, Value: value})
	}

	formatted := make([]string, 0, len(lines)*3)
	for _, entry := range entries {
		switch {
		case entry.Label != "":
			formatted = append(
				formatted,
				formatInformationField(
					entry.Label,
					entry.Value,
					width,
					labelWidth,
				)...,
			)
		case entry.Raw != "":
			formatted = append(
				formatted,
				styleWrappedInformation([]string{entry.Raw}, width, sBright)...,
			)
		case len(formatted) > 0 && formatted[len(formatted)-1] != "":
			formatted = append(formatted, "")
		}
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

func formatInformationField(
	label string,
	value string,
	width int,
	labelWidth int,
) []string {
	primary, secondary := splitInformationValue(value)
	primary, secondary = simplifyInformationValue(label, primary, secondary)

	primaryStyle := sWhite
	if strings.Contains(primary, "%") {
		primaryStyle = sRed
	}
	paddedLabel := label + strings.Repeat(
		" ",
		max(0, labelWidth-lipgloss.Width(label)),
	)
	row := sGray.Render(paddedLabel) +
		sDim.Render(" · ") +
		primaryStyle.Render(primary)
	for _, qualifier := range secondary {
		style := sMid
		if strings.Contains(qualifier, "%") {
			style = sRed
		}
		row += sDim.Render(" - ") + style.Render(qualifier)
	}
	return wrapDisplayLines([]string{row}, width)
}

func splitInformationValue(value string) (string, []string) {
	primary := value
	secondary := make([]string, 0, 2)
	if before, after, found := strings.Cut(value, " - "); found {
		primary = strings.TrimSpace(before)
		secondary = append(secondary, strings.TrimSpace(after))
	}
	primary, detail := splitInformationDetail(primary)
	if detail != "" {
		secondary = append(secondary, detail)
	}
	return primary, secondary
}

func simplifyInformationValue(
	label string,
	primary string,
	secondary []string,
) (string, []string) {
	if label == "STATUS" {
		secondary = nil
	}
	if label == "HARDWARE" {
		primary = strings.TrimPrefix(primary, "firmware ")
		primary = strings.TrimSuffix(primary, " mode")
	}
	for index, qualifier := range secondary {
		secondary[index] = strings.TrimPrefix(qualifier, "approximately ")
	}
	return primary, secondary
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
