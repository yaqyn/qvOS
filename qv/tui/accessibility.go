package main

import (
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type tuiHint struct {
	Key    string
	Action string
}

func handleTUIHelpKey(open bool, msg tea.KeyPressMsg) (bool, bool) {
	return handleTUIHelpKeyWithQuestion(open, msg, true)
}

func handleTUIHelpKeyWithQuestion(open bool, msg tea.KeyPressMsg, allowQuestion bool) (bool, bool) {
	switch msg.String() {
	case "f1":
		return !open, true
	case "?":
		if allowQuestion || open {
			return !open, true
		}
	case "esc":
		if open {
			return false, true
		}
	}
	return open, open
}

func renderTUIHints(width int, hints ...tuiHint) string {
	if width < 1 || len(hints) == 0 {
		return ""
	}

	separator := sDim.Render("  ·  ")
	separatorWidth := lipgloss.Width(separator)
	lines := make([]string, 0, len(hints))
	current := ""
	currentWidth := 0

	for _, hint := range hints {
		key := strings.TrimSpace(hint.Key)
		action := strings.TrimSpace(hint.Action)
		if key == "" || action == "" {
			continue
		}

		availableActionWidth := max(1, width-lipgloss.Width(key)-1)
		action = trimDisplay(action, availableActionWidth)
		token := sHot.Render(key) + " " + sBright.Render(action)
		tokenWidth := lipgloss.Width(token)

		if current == "" {
			current = token
			currentWidth = tokenWidth
			continue
		}
		if currentWidth+separatorWidth+tokenWidth <= width {
			current += separator + token
			currentWidth += separatorWidth + tokenWidth
			continue
		}

		lines = append(lines, current)
		current = token
		currentWidth = tokenWidth
	}

	if current != "" {
		lines = append(lines, current)
	}
	return strings.Join(lines, "\n")
}

func centerTUIHints(width int, hints ...tuiHint) string {
	return lipgloss.PlaceHorizontal(width, lipgloss.Center, renderTUIHints(width, hints...))
}

func appendTUIHints(content string, width int, hints ...tuiHint) string {
	rendered := centerTUIHints(width, hints...)
	if rendered == "" {
		return content
	}
	if content == "" {
		return rendered
	}
	return content + "\n\n" + rendered
}

func updateTUILogScroll(offset int, key string, lineCount int, visibleRows int) (int, bool) {
	maxOffset := max(0, lineCount-max(1, visibleRows))
	pageRows := max(1, visibleRows-1)

	switch key {
	case "up", "k":
		offset++
	case "down", "j":
		offset--
	case "pgup":
		offset += pageRows
	case "pgdown":
		offset -= pageRows
	case "home":
		offset = maxOffset
	case "end":
		offset = 0
	default:
		return offset, false
	}

	return min(max(offset, 0), maxOffset), true
}

func visibleTUILogLines(lines []string, visibleRows int, offset int, empty string) ([]string, int) {
	visibleRows = max(1, visibleRows)
	if len(lines) == 0 {
		return []string{empty}, 0
	}

	maxOffset := max(0, len(lines)-visibleRows)
	offset = min(max(offset, 0), maxOffset)
	end := len(lines) - offset
	start := max(0, end-visibleRows)
	return append([]string(nil), lines[start:end]...), offset
}

func appendTUILogSwitchCue(panel string, width int, offset int) string {
	cue := "ctrl+v  switch"
	if offset > 0 {
		cue = fmt.Sprintf("%d newer  ·  %s", offset, cue)
	}
	return panel + "\n" + lipgloss.PlaceHorizontal(width, lipgloss.Center, sGray.Render(cue))
}

func tuiLogInteractionHints() []tuiHint {
	return []tuiHint{
		{Key: "↑ / ↓  or  j / k", Action: "scroll lines"},
		{Key: "pgup / pgdown", Action: "scroll pages"},
		{Key: "home / end", Action: "oldest / newest"},
		{Key: "drag / ctrl+shift+c", Action: "copy + paste"},
	}
}

func terminalOutputContentHeight(height int) int {
	return max(3, height-8)
}

func renderTUIHelp(width int, title string, hints []tuiHint) string {
	panelWidth := min(72, max(18, width-8))
	contentWidth := max(1, panelWidth-6)
	keyWidth := 0
	for _, hint := range hints {
		keyWidth = max(keyWidth, lipgloss.Width(hint.Key))
	}
	keyWidth = min(keyWidth, max(4, contentWidth/3))

	rows := []string{
		sWhite.Render("qvOS  " + strings.ToUpper(title)),
		sDeepRed.Render(strings.Repeat("━", contentWidth)),
	}
	for _, hint := range hints {
		key := trimDisplay(strings.TrimSpace(hint.Key), keyWidth)
		actionWidth := max(1, contentWidth-keyWidth-5)
		action := trimDisplay(strings.TrimSpace(hint.Action), actionWidth)
		rows = append(rows,
			lipgloss.PlaceHorizontal(keyWidth, lipgloss.Right, sHot.Render(key))+
				sDim.Render("  ·  ")+
				sBright.Render(action),
		)
	}
	rows = append(rows, "", centerTUIHints(contentWidth,
		tuiHint{Key: "f1 / ? / esc", Action: "close help"},
	))

	return lipgloss.NewStyle().
		Width(panelWidth).
		Padding(1, 2).
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(deepRed)).
		Render(strings.Join(rows, "\n"))
}

func renderTUITerminalOutput(width, height int, page string, lines []string, scrollOffset int, hints []tuiHint) string {
	panelWidth := min(112, max(20, width-6))
	contentWidth := max(1, panelWidth-4)
	contentHeight := terminalOutputContentHeight(height)
	lines, scrollOffset = visibleTUILogLines(
		lines,
		contentHeight,
		scrollOffset,
		"waiting for command output",
	)

	body := make([]string, 0, len(lines)+5)
	title := sWhite.Render("qvOS  " + strings.ToUpper(page) + " / TERMINAL OUTPUT")
	if scrollOffset > 0 {
		position := sGray.Render(fmt.Sprintf("%d newer", scrollOffset))
		gap := max(1, contentWidth-lipgloss.Width(title)-lipgloss.Width(position))
		title += strings.Repeat(" ", gap) + position
	}
	body = append(body, title, sDeepRed.Render(strings.Repeat("━", contentWidth)))
	for _, line := range lines {
		body = append(body, sBright.Render(trimDisplay(line, contentWidth)))
	}
	for len(body) < contentHeight+2 {
		body = append(body, "")
	}
	body = append(body,
		sDeepRed.Render(strings.Repeat("━", contentWidth)),
		centerTUIHints(contentWidth, hints...),
	)

	return lipgloss.NewStyle().
		Width(panelWidth).
		Padding(0, 1).
		Render(strings.Join(body, "\n"))
}
