package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

const (
	actionSelectionMaxLabelWidth = 48
	actionSelectionMaxRows       = 6
)

type actionOptionsLoadedMsg struct {
	action  actionMode
	script  string
	choices []string
	err     error
}

func (m *model) resetActionSelection() {
	m.selectionLoading = false
	m.selectionActive = false
	m.selectionChoices = nil
	clearRunes(m.selectionFilter)
	m.selectionFilter = nil
	m.selectionCursor = 0
	m.actionSelections = nil
	m.selectionErr = ""
}

func loadActionOptionsCmd(action actionMode, script string) tea.Cmd {
	return func() tea.Msg {
		if action != actionGeneric {
			return actionOptionsLoadedMsg{
				action: action,
				script: script,
				err:    fmt.Errorf("action %d does not support selection", action),
			}
		}

		cmd := exec.Command("/bin/bash", script, "--options")
		cmd.Env = os.Environ()
		output, err := cmd.CombinedOutput()
		if err != nil {
			message := strings.Join(strings.Fields(string(output)), " ")
			if message == "" {
				message = err.Error()
			}
			return actionOptionsLoadedMsg{
				action: action,
				script: script,
				err:    fmt.Errorf("%s", message),
			}
		}

		choices, err := parseActionOptions(string(output))
		return actionOptionsLoadedMsg{
			action:  action,
			script:  script,
			choices: choices,
			err:     err,
		}
	}
}

func parseActionOptions(output string) ([]string, error) {
	seen := make(map[string]bool)
	choices := make([]string, 0)
	scanner := bufio.NewScanner(strings.NewReader(output))
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		choice := strings.TrimSpace(sanitizeLogLine(scanner.Text()))
		if choice == "" || seen[choice] {
			continue
		}
		seen[choice] = true
		choices = append(choices, choice)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("could not read action choices: %w", err)
	}
	return choices, nil
}

func (m model) actionSelectionHasNoChoices() bool {
	return len(m.selectionChoices) == 0
}

func (m model) filteredActionChoices() []string {
	filter := strings.ToLower(strings.TrimSpace(string(m.selectionFilter)))
	if filter == "" {
		return m.selectionChoices
	}

	filtered := make([]string, 0, len(m.selectionChoices))
	for _, choice := range m.selectionChoices {
		if strings.Contains(strings.ToLower(choice), filter) {
			filtered = append(filtered, choice)
		}
	}
	return filtered
}

func (m model) handleActionSelectionKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if m.actionSelectionHasNoChoices() {
		switch msg.String() {
		case "enter", "esc", "ctrl+c", "ctrl+z":
			return m.cancelRootAction()
		default:
			return m, nil
		}
	}

	choices := m.filteredActionChoices()
	switch msg.String() {
	case "esc", "ctrl+c", "ctrl+z":
		return m.cancelRootAction()
	case "up":
		if m.selectionCursor > 0 {
			m.selectionCursor--
		}
	case "down":
		if m.selectionCursor < len(choices)-1 {
			m.selectionCursor++
		}
	case "enter":
		if len(choices) == 0 {
			m.selectionErr = "no matches"
			return m, nil
		}
		if currentActionSpec.AllowsMultipleSelections() {
			if len(m.actionSelections) == 0 {
				m.actionSelections = []string{choices[m.selectionCursor]}
			}
			return m.completeActionSelection()
		}
		m.actionSelections = []string{choices[m.selectionCursor]}
		return m.completeActionSelection()
	case "tab":
		if !currentActionSpec.AllowsMultipleSelections() || len(choices) == 0 {
			return m, nil
		}
		m.toggleActionSelection(choices[m.selectionCursor])
	case " ", "space":
		if currentActionSpec.IsActionSelection() {
			return m, nil
		}
		m.selectionFilter = append(m.selectionFilter, ' ')
		m.selectionCursor = 0
		m.selectionErr = ""
	case "backspace", "ctrl+h":
		if len(m.selectionFilter) > 0 {
			m.selectionFilter[len(m.selectionFilter)-1] = 0
			m.selectionFilter = m.selectionFilter[:len(m.selectionFilter)-1]
			m.selectionCursor = 0
			m.selectionErr = ""
		}
	case "ctrl+u":
		clearRunes(m.selectionFilter)
		m.selectionFilter = nil
		m.selectionCursor = 0
		m.selectionErr = ""
	default:
		if currentActionSpec.IsActionSelection() {
			return m, nil
		}
		if text := msg.Key().Text; text != "" {
			m.selectionFilter = append(m.selectionFilter, []rune(text)...)
			m.selectionCursor = 0
			m.selectionErr = ""
		}
	}

	if m.selectionCursor >= len(choices) {
		m.selectionCursor = max(0, len(choices)-1)
	}
	return m, nil
}

func (m *model) toggleActionSelection(choice string) {
	for index, selected := range m.actionSelections {
		if selected != choice {
			continue
		}
		m.actionSelections = append(m.actionSelections[:index], m.actionSelections[index+1:]...)
		return
	}
	m.actionSelections = append(m.actionSelections, choice)
}

func (m model) actionSelectionContains(choice string) bool {
	for _, selected := range m.actionSelections {
		if selected == choice {
			return true
		}
	}
	return false
}

func (m model) completeActionSelection() (model, tea.Cmd) {
	m.selectionActive = false
	m.selectionErr = ""
	if currentActionSpec.IsActionSelection() {
		currentActionSpec = currentActionSpec.ForSelection(m.actionSelections[0])
	}
	return m.continueRootActionFlow()
}

func (m model) renderActionSelectionFor(mode layoutMode) string {
	title := centerCanvas(sWhite.Render(strings.ToUpper(currentActionSpec.SelectionTitle)))
	if m.actionSelectionHasNoChoices() {
		empty := currentActionSpec.SelectionEmpty
		if empty == "" {
			empty = "No options are currently available."
		}
		return appendTUIHints(
			strings.Join([]string{title, "", centerCanvas(sGray.Render(empty))}, "\n"),
			canvasW,
			m.rootPersistentHints()...,
		)
	}

	prefixWidth := actionSelectionPrefixWidth()
	labelWidth := m.actionSelectionLabelWidth(prefixWidth)
	columnWidth := prefixWidth + labelWidth
	rows := centerLinesWithWidth(m.visibleActionSelectionRows(mode, labelWidth), columnWidth)

	lines := []string{title, ""}
	if !currentActionSpec.IsActionSelection() {
		filter := centerCanvas(sMid.Render("search"))
		if strings.TrimSpace(string(m.selectionFilter)) != "" {
			filter = strings.Repeat(" ", prefixWidth) +
				renderSearchFieldWidth(string(m.selectionFilter), labelWidth)
			filter = centerCanvas(lipgloss.PlaceHorizontal(columnWidth, lipgloss.Left, filter))
		}
		lines = append(lines, filter, "")
	}
	lines = append(lines, rows...)
	if m.selectionErr != "" {
		lines = append(lines, "", centerCanvas(sRed.Render(m.selectionErr)))
	}
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, m.rootPersistentHints()...)
}

func actionSelectionPrefixWidth() int {
	width := 2
	if currentActionSpec.AllowsMultipleSelections() {
		width += 2
	}
	return width
}

func (m model) actionSelectionLabelWidth(prefixWidth int) int {
	labelWidth := lipgloss.Width("search")
	for _, choice := range m.selectionChoices {
		labelWidth = max(labelWidth, lipgloss.Width(choice))
	}
	return min(labelWidth, actionSelectionMaxLabelWidth, max(1, canvasW-prefixWidth))
}

func (m model) actionSelectionRowLimit(mode layoutMode) int {
	if isSideComposition(m.width, m.height, m.fullscreen) {
		return min(actionSelectionMaxRows, max(3, m.height-8))
	}

	if mode == layoutTablet {
		return 5
	}
	if mode == layoutMobile {
		return 3
	}
	return actionSelectionMaxRows
}

func (m model) visibleActionSelectionRows(mode layoutMode, labelWidth int) []string {
	choices := m.filteredActionChoices()
	limit := min(
		m.actionSelectionRowLimit(mode),
		max(3, len(m.selectionChoices)),
	)
	if len(choices) == 0 {
		return padActionSelectionRows([]string{sMid.Render("No matches")}, limit)
	}

	start := m.selectionCursor - limit/2
	if start < 0 {
		start = 0
	}
	if start+limit > len(choices) {
		start = max(0, len(choices)-limit)
	}
	end := min(len(choices), start+limit)

	rows := make([]string, 0, end-start)
	for index := start; index < end; index++ {
		rows = append(rows, m.renderActionSelectionRow(
			choices[index],
			index == m.selectionCursor,
			m.actionSelectionContains(choices[index]),
			labelWidth,
		))
	}
	return padActionSelectionRows(rows, limit)
}

func padActionSelectionRows(rows []string, height int) []string {
	for len(rows) < height {
		rows = append(rows, "")
	}
	return rows
}

func (m model) renderActionSelectionRow(choice string, active bool, selected bool, labelWidth int) string {
	label := trimDisplay(choice, labelWidth)
	labelStyle := sMid
	cursor := sDim.Render("  ")
	if active {
		labelStyle = sWhite
		cursor = sRed.Render("• ")
	}

	selection := ""
	if currentActionSpec.AllowsMultipleSelections() {
		if selected {
			selection = sRed.Render("✓ ")
		} else {
			selection = sDim.Render("· ")
		}
	}
	label = lipgloss.PlaceHorizontal(labelWidth, lipgloss.Left, labelStyle.Render(label))
	return lipgloss.JoinHorizontal(lipgloss.Center, cursor, selection, label)
}
