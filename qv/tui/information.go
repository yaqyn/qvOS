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
	Prose bool
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
	fieldCount := 0
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
		if isInformationProse(label, value) {
			entries = append(entries, informationEntry{
				Raw:   formatInformationProse(label, value),
				Prose: true,
			})
			continue
		}
		if strings.EqualFold(label, title) {
			label = "Status"
		}
		label = strings.ToUpper(label)
		labelWidth = max(labelWidth, lipgloss.Width(label))
		entries = append(entries, informationEntry{Label: label, Value: value})
		fieldCount++
	}

	reportLayout := fieldCount > 2
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
					reportLayout,
				)...,
			)
		case entry.Prose:
			if len(formatted) > 0 && formatted[len(formatted)-1] != "" {
				formatted = append(formatted, "")
			}
			formatted = append(
				formatted,
				styleWrappedInformation([]string{entry.Raw}, width, sMid)...,
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

func isInformationProse(label string, value string) bool {
	switch strings.ToLower(strings.TrimSpace(label)) {
	case "details", "message", "note", "notice", "privacy", "report privacy", "summary", "warning":
		return true
	}
	return strings.HasSuffix(strings.ToLower(strings.TrimSpace(value)), " omitted")
}

func formatInformationProse(label string, value string) string {
	if strings.EqualFold(strings.TrimSpace(label), "Report privacy") {
		return "Report Privacy: Serials, DMI Data, & Native paths omitted"
	}

	label = strings.TrimSpace(label)
	value = strings.TrimSpace(value)
	if label != "" {
		label = string(unicode.ToUpper([]rune(label)[0])) + string([]rune(label)[1:])
	}
	if value != "" {
		value = string(unicode.ToUpper([]rune(value)[0])) + string([]rune(value)[1:])
	}
	return label + ": " + value
}

func formatInformationField(
	label string,
	value string,
	width int,
	labelWidth int,
	reportLayout bool,
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
	separator := " · "
	if reportLayout {
		separator = " - "
	}
	valueIndent := strings.Repeat(" ", labelWidth+lipgloss.Width(separator))
	valueWidth := max(1, width-lipgloss.Width(valueIndent))
	primaryLines := wrapDisplayLines([]string{primary}, valueWidth)
	if len(primaryLines) == 0 {
		primaryLines = []string{primary}
	}

	formatted := make([]string, 0, len(primaryLines)+len(secondary))
	formatted = append(
		formatted,
		sGray.Render(paddedLabel)+sDim.Render(separator)+primaryStyle.Render(primaryLines[0]),
	)
	for _, line := range primaryLines[1:] {
		formatted = append(formatted, valueIndent+primaryStyle.Render(line))
	}
	for _, qualifier := range secondary {
		style := sMid
		if strings.Contains(qualifier, "%") {
			style = sRed
		}
		qualifierLines := wrapDisplayLines([]string{qualifier}, valueWidth)
		if !reportLayout && len(qualifierLines) == 1 &&
			lipgloss.Width(formatted[len(formatted)-1])+
				lipgloss.Width(" - ")+
				lipgloss.Width(qualifierLines[0]) <= width {
			formatted[len(formatted)-1] +=
				sDim.Render(" - ") + style.Render(qualifierLines[0])
			continue
		}
		for _, line := range qualifierLines {
			formatted = append(formatted, valueIndent+style.Render(line))
		}
	}
	return formatted
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
	primary = simplifyInformationText(primary)
	for index, qualifier := range secondary {
		secondary[index] = simplifyInformationText(qualifier)
	}
	return primary, secondary
}

func simplifyInformationText(value string) string {
	value = strings.TrimPrefix(strings.TrimSpace(value), "approximately ")
	value = strings.ReplaceAll(value, "_", " ")
	switch strings.ToLower(value) {
	case "yes", "no", "true", "false", "enabled", "disabled", "absent", "present",
		"supported", "unsupported", "unmanaged":
		return string(unicode.ToUpper([]rune(value)[0])) + string([]rune(value)[1:])
	case "none active":
		return "None active"
	}
	return value
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
