package main

import (
	"fmt"
	"os/exec"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type tuiHint struct {
	Key    string
	Action string
}

type tuiLogCopiedMsg struct {
	err error
}

func tuiHelpHint() tuiHint {
	return tuiHint{Key: "f1", Action: "help"}
}

func tuiTerminalPersistentHints() []tuiHint {
	return []tuiHint{
		{Key: "ctrl+v", Action: "switch"},
		tuiHelpHint(),
	}
}

func handleTUITerminalViewKey(
	msg tea.KeyPressMsg,
	lines []string,
	terminalView *bool,
	logOverlay *bool,
	copyStatus *string,
) (bool, tea.Cmd) {
	if !*terminalView {
		return false, nil
	}

	switch msg.String() {
	case "y", "Y":
		var cmd tea.Cmd
		*copyStatus, cmd = beginTUILogCopy(lines)
		return true, cmd
	case "ctrl+v":
		*terminalView = false
		*copyStatus = ""
		return true, nil
	case "v", "V":
		*terminalView = false
		*logOverlay = true
		*copyStatus = ""
		return true, nil
	default:
		return false, nil
	}
}

func handleTUILogViewKey(
	msg tea.KeyPressMsg,
	available bool,
	terminalView *bool,
	logOverlay *bool,
	copyStatus *string,
) bool {
	if !available {
		return false
	}

	switch msg.String() {
	case "v", "V":
		*logOverlay = !*logOverlay
		return true
	case "ctrl+v":
		*terminalView = true
		*copyStatus = ""
		return true
	default:
		return false
	}
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
	hints = visibleTUIHints(width, hints)

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
		keyStyle := sHot
		actionStyle := sBright
		if isHelpTUIHint(hint) {
			keyStyle = sDim
			actionStyle = sDim
		}
		token := keyStyle.Render(key) + " " + actionStyle.Render(action)
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

func visibleTUIHints(width int, hints []tuiHint) []tuiHint {
	if width >= sideLeftMax || len(hints) != 2 {
		return hints
	}
	for _, hint := range hints {
		if !isHelpTUIHint(hint) {
			return []tuiHint{hint}
		}
	}
	return hints
}

func isHelpTUIHint(hint tuiHint) bool {
	return strings.EqualFold(strings.TrimSpace(hint.Action), "help")
}

func centerTUIHints(width int, hints ...tuiHint) string {
	rendered := renderTUIHints(width, hints...)
	if rendered == "" {
		return ""
	}
	lines := strings.Split(rendered, "\n")
	for index, line := range lines {
		lines[index] = lipgloss.PlaceHorizontal(width, lipgloss.Center, line)
	}
	return strings.Join(lines, "\n")
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

func tuiLogScrollHints() []tuiHint {
	return []tuiHint{
		{Key: "↑ / ↓  or  j / k", Action: "scroll lines"},
		{Key: "pgup / pgdown", Action: "scroll pages"},
		{Key: "home / end", Action: "oldest / newest"},
	}
}

func tuiTerminalLogHints() []tuiHint {
	return append(tuiLogScrollHints(),
		tuiHint{Key: "drag / ctrl+shift+c", Action: "copy visible text"},
		tuiHint{Key: "y", Action: "copy full log"},
	)
}

func tuiLogClipboardText(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	return strings.Join(lines, "\n") + "\n"
}

func beginTUILogCopy(lines []string) (string, tea.Cmd) {
	text := tuiLogClipboardText(lines)
	if text == "" {
		return "nothing to copy", nil
	}

	return "copying full log", func() tea.Msg {
		cmd := exec.Command("wl-copy", "--type", "text/plain;charset=utf-8")
		cmd.Stdin = strings.NewReader(text)
		return tuiLogCopiedMsg{err: cmd.Run()}
	}
}

func tuiLogCopyResultStatus(err error) string {
	if err != nil {
		return "copy failed · clipboard unavailable"
	}
	return "full log copied"
}

func terminalOutputContentHeight(height int) int {
	return max(3, height-8)
}

func terminalOutputContentWidth(width int) int {
	panelWidth := min(112, max(20, width-6))
	return max(1, panelWidth-4)
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
		renderTUIRail(contentWidth, sDim),
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
		tuiHint{Key: "f1 / shift+? / esc", Action: "close help"},
	))

	return lipgloss.NewStyle().
		Width(panelWidth).
		Padding(1, 2).
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(deepRed)).
		Render(strings.Join(rows, "\n"))
}

func renderTUITerminalOutput(
	width, height int,
	page string,
	lines []string,
	scrollOffset int,
	copyStatus string,
	empty string,
	hints []tuiHint,
) string {
	panelWidth := min(112, max(20, width-6))
	contentWidth := terminalOutputContentWidth(width)
	contentHeight := terminalOutputContentHeight(height)
	lines = wrapTUILogLines(lines, contentWidth)
	lines, scrollOffset = visibleTUILogLines(
		lines,
		contentHeight,
		scrollOffset,
		empty,
	)

	body := make([]string, 0, len(lines)+5)
	title := sWhite.Render("qvOS  " + strings.ToUpper(page) + " / TERMINAL OUTPUT")
	var metadata []string
	if scrollOffset > 0 {
		metadata = append(metadata, fmt.Sprintf("%d newer", scrollOffset))
	}
	if copyStatus != "" {
		metadata = append(metadata, copyStatus)
	}
	if len(metadata) > 0 {
		available := contentWidth - lipgloss.Width(title) - 1
		if available > 0 {
			status := sGray.Render(trimDisplay(strings.Join(metadata, " · "), available))
			gap := max(1, contentWidth-lipgloss.Width(title)-lipgloss.Width(status))
			title += strings.Repeat(" ", gap) + status
		}
	}
	body = append(body, title, renderTUIRail(contentWidth, sDim))
	for _, line := range lines {
		body = append(body, sBright.Render(line))
	}
	for len(body) < contentHeight+2 {
		body = append(body, "")
	}
	body = append(body,
		renderTUIRail(contentWidth, sDim),
		centerTUIHints(contentWidth, hints...),
	)

	return lipgloss.NewStyle().
		Width(panelWidth).
		Padding(0, 1).
		Render(strings.Join(body, "\n"))
}
