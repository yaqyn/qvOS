package main

import (
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type isoFinishedModel struct {
	frame         int
	width         int
	height        int
	fullscreen    bool
	logPath       string
	duration      string
	logLines      []string
	logOverlay    bool
	terminalView  bool
	logScroll     int
	logCopyStatus string
	allowQuit     bool
	helpOverlay   bool
}

func runISOFinished(args []string) error {
	logPath := defaultISOProgressLogPath
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--log":
			if i+1 >= len(args) {
				return fmt.Errorf("--log requires a path")
			}
			i++
			logPath = strings.TrimSpace(args[i])
		default:
			return fmt.Errorf("unknown --iso-finished option: %s", args[i])
		}
	}
	if logPath == "" {
		logPath = defaultISOProgressLogPath
	}

	text, lines := readISOProgressLog(logPath)
	p := newTUIProgram(
		newISOFinishedModel(logPath, parseISOFinishedDuration(text), lines),
		tea.WithFilter(filterISOFinishedExitMessages),
	)
	_, err := p.Run()
	return err
}

func newISOFinishedModel(logPath string, duration string, lines []string) isoFinishedModel {
	return isoFinishedModel{
		logPath:  logPath,
		duration: strings.TrimSpace(duration),
		logLines: append([]string(nil), lines...),
	}
}

func filterISOFinishedExitMessages(model tea.Model, msg tea.Msg) tea.Msg {
	switch msg.(type) {
	case tea.QuitMsg:
		if finishedModel, ok := model.(isoFinishedModel); ok && finishedModel.allowQuit {
			return msg
		}
		return nil
	case tea.InterruptMsg, tea.SuspendMsg:
		return nil
	default:
		return msg
	}
}

func (m isoFinishedModel) Init() tea.Cmd { return tea.Batch(tick(), detectFullscreenCmd()) }

func (m isoFinishedModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, detectFullscreenCmd()
	case fullscreenStateMsg:
		m.fullscreen = msg.fullscreen
	case tuiLogCopiedMsg:
		m.logCopyStatus = tuiLogCopyResultStatus(msg.err)
		return m, nil
	case tea.KeyPressMsg:
		if helpOverlay, handled := handleTUIHelpKey(m.helpOverlay, msg); handled {
			m.helpOverlay = helpOverlay
			return m, nil
		}
		if m.logOverlay || m.terminalView {
			if offset, handled := updateTUILogScroll(
				m.logScroll,
				msg.String(),
				len(m.logRows()),
				m.logViewportRows(),
			); handled {
				m.logScroll = offset
				return m, nil
			}
		}
		if m.terminalView {
			if handled, cmd := handleTUITerminalViewKey(
				msg,
				m.logLines,
				&m.terminalView,
				&m.logOverlay,
				&m.logCopyStatus,
			); handled {
				return m, cmd
			}
			return m, nil
		}
		if handleTUILogViewKey(
			msg,
			len(m.logLines) > 0,
			&m.terminalView,
			&m.logOverlay,
			&m.logCopyStatus,
		) {
			return m, nil
		}
		switch msg.String() {
		case "enter":
			m.allowQuit = true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m isoFinishedModel) View() tea.View {
	termWidth, termHeight := safeDimensions(m.width, m.height)
	width, height := termWidth, termHeight
	mode := layoutFor(width, height)

	var body string
	if m.helpOverlay {
		body = renderTUIHelp(width, "install finale controls", m.helpHints())
	} else if m.terminalView {
		body = renderTUITerminalOutput(
			width,
			height,
			"INSTALL",
			m.logLines,
			m.logScroll,
			m.logCopyStatus,
			"No command output",
			tuiTerminalPersistentHints(),
		)
	} else if isSideComposition(width, height, m.fullscreen) {
		body = m.renderISOSideBody(width, height)
	} else {
		logInModelSlot := m.fullscreenLogUsesModelSlot(width, height)
		reserveRows := fullCanvasReserveRows
		if m.logOverlay && !logInModelSlot {
			reserveRows = logCanvasReserveRows
		}
		iconWidth, iconHeight, showIcon := fitCenterStageCanvas(width, height, reserveRows)
		showStage := showIcon || logInModelSlot
		if showStage {
			canvasW, canvasH = iconWidth, iconHeight
		} else {
			canvasW, canvasH = fitContentWidth(width), 0
		}

		icon := ""
		if logInModelSlot {
			icon = placeTUILogInCanvas(
				m.renderLogs(mode),
				iconWidth,
				iconHeight,
			)
		} else if showIcon {
			icon = renderModelRole(modelThreeRings, m.frame)
		}
		canvasW = fitContentWidth(width)
		body = m.renderISOFinishedBody(mode, icon)
	}

	placed := renderViewport(termWidth, termHeight, body)

	v := tea.NewView(placed)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeNone
	v.BackgroundColor = lipgloss.Color(bgTerm)
	v.WindowTitle = "qvOS installed"
	return v
}

func (m isoFinishedModel) renderISOSideBody(width, height int) string {
	leftWidth, rightWidth := sideColumnWidths(width)
	canvasW, canvasH = leftWidth, 0
	left := m.renderISOFinishedPanel(layoutTablet, false)
	if m.logOverlay {
		canvasW = rightWidth
		right := m.renderLogs(layoutTablet)
		return renderSideColumns(width, left, right)
	}
	right := renderIdentity("qvOS", "INSTALL / FINALE")

	if iconWidth, iconHeight, ok := fitSideIconCanvas(width, height); ok {
		canvasW, canvasH = iconWidth, iconHeight
		right = lipgloss.JoinVertical(
			lipgloss.Center,
			renderModelRole(modelThreeRings, m.frame),
			"",
			renderIdentity("qvOS", "INSTALL / FINALE"),
		)
		canvasW, canvasH = leftWidth, 0
	}
	return renderSideColumns(width, left, right)
}

func (m isoFinishedModel) renderISOFinishedBody(mode layoutMode, icon string) string {
	var lines []string
	if icon != "" {
		lines = append(lines, centerCanvas(icon), "")
	}
	lines = append(lines, m.renderISOFinishedPanel(mode, true))
	if m.logOverlay && !m.fullscreenLogUsesModelSlot(m.width, m.height) {
		lines = append(lines, "", centerCanvas(m.renderLogs(mode)))
	}
	return strings.Join(lines, "\n")
}

func (m isoFinishedModel) renderISOFinishedPanel(mode layoutMode, includeProduct bool) string {
	status := "INSTALLED"
	if m.duration != "" {
		status = "INSTALLED IN " + strings.ToUpper(m.duration)
	}

	var lines []string
	if includeProduct {
		lines = append(lines, centerCanvas(sWhite.Render("qvOS")))
	}
	lines = append(lines,
		centerCanvas(sGray.Render(status)),
		"",
		centerCanvas(renderISOActionRow("00", "REBOOT NOW", true, mode)),
	)

	lines = append(lines, "", centerTUIHints(
		canvasW,
		tuiHint{Key: "enter", Action: "reboot"},
		tuiHelpHint(),
	))
	return strings.Join(lines, "\n")
}

func (m isoFinishedModel) helpHints() []tuiHint {
	hints := []tuiHint{{Key: "enter", Action: "reboot into the installed qvOS system"}}
	if len(m.logLines) > 0 {
		hints = append(hints,
			tuiHint{Key: "v", Action: "toggle the qvOS install log panel"},
			tuiHint{Key: "ctrl+v", Action: "toggle original terminal output"},
		)
	}
	if m.logOverlay {
		hints = append(hints, tuiLogScrollHints()...)
	}
	return hints
}

func (m isoFinishedModel) logViewportRows() int {
	if m.terminalView {
		return terminalOutputContentHeight(m.height)
	}
	mode := layoutFor(m.width, m.height)
	if isSideComposition(m.width, m.height, m.fullscreen) {
		mode = layoutTablet
	}
	return actionLogVisibleRows(mode, m.height)
}

func (m isoFinishedModel) logRows() []string {
	return wrapTUILogLines(m.logLines, m.logContentWidth())
}

func (m isoFinishedModel) logContentWidth() int {
	return responsiveTUILogContentWidth(responsiveLogWidth{
		Width:      m.width,
		Height:     m.height,
		CenterMax:  maxCanvasW,
		Maximum:    logSideRightMax,
		Terminal:   m.terminalView,
		Fullscreen: m.fullscreen,
		ModelSlot:  m.fullscreenLogUsesModelSlot(m.width, m.height),
		SideRight:  true,
		Border:     true,
	})
}

func (m isoFinishedModel) renderLogs(mode layoutMode) string {
	return renderActionLogPanel(
		m.logLines,
		canvasW,
		mode,
		m.height,
		m.logScroll,
		"No command output",
	)
}

func (m isoFinishedModel) fullscreenLogUsesModelSlot(width, height int) bool {
	return fullscreenTUILogUsesModelSlot(
		m.fullscreen && m.logOverlay,
		width,
		height,
	)
}

func parseISOFinishedDuration(text string) string {
	clean := strings.TrimSpace(stripANSI(strings.ReplaceAll(strings.ReplaceAll(text, `\033[0m`, ""), `\e[0m`, "")))
	lines := strings.Split(clean, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if strings.HasPrefix(strings.ToLower(line), "total:") {
			return strings.TrimSpace(line[len("Total:"):])
		}
	}
	return ""
}
