package main

import (
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

func renderTUIHelp(width int, title string, hints []tuiHint) string {
	panelWidth := min(72, max(18, width-8))
	keyWidth := 0
	for _, hint := range hints {
		keyWidth = max(keyWidth, lipgloss.Width(hint.Key))
	}
	keyWidth = min(keyWidth, max(4, panelWidth/3))

	rows := []string{
		sWhite.Render("qvOS  " + strings.ToUpper(title)),
		sDeepRed.Render(strings.Repeat("━", panelWidth)),
	}
	for _, hint := range hints {
		key := trimDisplay(strings.TrimSpace(hint.Key), keyWidth)
		actionWidth := max(1, panelWidth-keyWidth-3)
		action := trimDisplay(strings.TrimSpace(hint.Action), actionWidth)
		rows = append(rows,
			lipgloss.PlaceHorizontal(keyWidth, lipgloss.Right, sHot.Render(key))+
				sDim.Render("  ·  ")+
				sBright.Render(action),
		)
	}
	rows = append(rows, "", centerTUIHints(panelWidth,
		tuiHint{Key: "f1 / ? / esc", Action: "close help"},
	))

	return lipgloss.NewStyle().
		Width(panelWidth).
		Padding(1, 2).
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(deepRed)).
		Render(strings.Join(rows, "\n"))
}

func renderTUITerminalOutput(width, height int, page string, lines []string, hints []tuiHint) string {
	panelWidth := min(112, max(20, width-6))
	contentWidth := max(1, panelWidth-4)
	contentHeight := max(3, height-8)

	if len(lines) == 0 {
		lines = []string{"waiting for command output"}
	}
	if len(lines) > contentHeight {
		lines = lines[len(lines)-contentHeight:]
	}

	body := make([]string, 0, len(lines)+5)
	body = append(body,
		sWhite.Render("qvOS  "+strings.ToUpper(page)+" / TERMINAL OUTPUT"),
		sDeepRed.Render(strings.Repeat("━", contentWidth)),
	)
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
