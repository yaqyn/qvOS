package main

import (
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type isoFinishedModel struct {
	frame     int
	width     int
	height    int
	logPath   string
	duration  string
	allowQuit bool
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
	p := tea.NewProgram(newISOFinishedModel(logPath, parseISOFinishedDuration(text)), tea.WithFilter(filterISOFinishedExitMessages))
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

func (m isoFinishedModel) Init() tea.Cmd { return tick() }

func (m isoFinishedModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case tea.KeyPressMsg:
		if msg.String() == "enter" {
			m.allowQuit = true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m isoFinishedModel) View() tea.View {
	width, height := safeDimensions(m.width, m.height)
	mode := layoutFor(width, height)

	if mode == layoutFull {
		canvasW, canvasH = fitCanvas(width, height)
	} else if mode == layoutMid {
		canvasW, canvasH = fitMidCanvas(width, height)
	} else {
		canvasW, canvasH = fitSmallBody(width), 0
	}

	icon := ""
	if mode != layoutSmall {
		icon = renderBloom(m.frame)
	}

	body := m.renderISOFinishedBody(mode, icon)
	placed := lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, body)
	placed = lipgloss.NewStyle().
		Width(width).
		Height(height).
		Background(lipgloss.Color("#000000")).
		Render(placed)

	v := tea.NewView(placed)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeNone
	v.BackgroundColor = lipgloss.Color("#000000")
	v.WindowTitle = "qvOS installed"
	return v
}

func (m isoFinishedModel) renderISOFinishedBody(mode layoutMode, icon string) string {
	var lines []string
	if icon != "" {
		lines = append(lines, icon, "")
	}

	status := "INSTALLED"
	if m.duration != "" {
		status = "INSTALLED IN " + strings.ToUpper(m.duration)
	}

	lines = append(lines,
		centerCanvas(sWhite.Render("qvOS")),
		centerCanvas(sGray.Render(status)),
		"",
		centerCanvas(renderISOActionRow("00", "REBOOT NOW", true, mode)),
	)

	if mode == layoutFull {
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
