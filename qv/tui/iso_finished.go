package main

import (
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type isoFinishedModel struct {
	frame      int
	width      int
	height     int
	fullscreen bool
	logPath    string
	duration   string
	allowQuit  bool
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

	text, _ := readISOProgressLog(logPath)
	p := newTUIProgram(newISOFinishedModel(logPath, parseISOFinishedDuration(text)), tea.WithFilter(filterISOFinishedExitMessages))
	_, err := p.Run()
	return err
}

func newISOFinishedModel(logPath string, duration string) isoFinishedModel {
	return isoFinishedModel{
		logPath:  logPath,
		duration: strings.TrimSpace(duration),
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
	case tea.KeyPressMsg:
		if msg.String() == "enter" {
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
	if isSideComposition(width, height, m.fullscreen) {
		body = m.renderISOSideBody(width, height)
	} else {
		iconWidth, iconHeight, showIcon := fitCenterStageCanvas(width, height, fullCanvasReserveRows)
		if showIcon {
			canvasW, canvasH = iconWidth, iconHeight
		} else {
			canvasW, canvasH = fitContentWidth(width), 0
		}

		icon := ""
		if showIcon {
			icon = renderBloom(m.frame)
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
	leftWidth, _ := sideColumnWidths(width)
	canvasW, canvasH = leftWidth, 0
	left := m.renderISOFinishedPanel(layoutTablet, false)
	right := renderIdentity("qvOS", "INSTALL / FINALE")

	if iconWidth, iconHeight, ok := fitSideIconCanvas(width, height); ok {
		canvasW, canvasH = iconWidth, iconHeight
		right = lipgloss.JoinVertical(
			lipgloss.Center,
			renderBloom(m.frame),
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

	if mode == layoutDesktop {
		lines = append(lines, "", centerCanvas(sDim.Render("enter  reboot")))
	}
	return strings.Join(lines, "\n")
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
