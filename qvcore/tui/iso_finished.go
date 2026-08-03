package main

import (
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type isoFinishedModel struct {
	width        int
	height       int
	allowQuit    bool
	helpOverlay  bool
	timerStopped bool
}

const isoFinishedRebootDelay = 5 * time.Second

type isoFinishedRebootMsg struct{}

func isoFinishedRebootCmd() tea.Cmd {
	return tea.Tick(isoFinishedRebootDelay, func(time.Time) tea.Msg {
		return isoFinishedRebootMsg{}
	})
}

func runISOFinished() error {
	p := newTUIProgram(
		newISOFinishedModel(),
		tea.WithFilter(filterISOFinishedExitMessages),
	)
	_, err := p.Run()
	return err
}

func newISOFinishedModel() isoFinishedModel {
	return isoFinishedModel{}
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

func (m isoFinishedModel) Init() tea.Cmd {
	return initialTUICommand(isoFinishedRebootCmd())
}

func (m isoFinishedModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case isoFinishedRebootMsg:
		if m.timerStopped {
			return m, nil
		}
		m.allowQuit = true
		return m, tea.Quit
	case tea.KeyPressMsg:
		m.timerStopped = true
		if helpOverlay, handled := handleTUIHelpKey(m.helpOverlay, msg); handled {
			m.helpOverlay = helpOverlay
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
	width := termWidth

	var body string
	if m.helpOverlay {
		body = renderTUIHelp(width, "install finale controls", m.helpHints())
	} else {
		canvasW, canvasH = fitContentWidth(width), 0
		body = m.renderISOFinishedPanel()
	}

	placed := renderViewport(termWidth, termHeight, body)

	v := tea.NewView(placed)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeNone
	v.BackgroundColor = lipgloss.Color(bgTerm)
	v.WindowTitle = "qvOS installed"
	return v
}

func (m isoFinishedModel) renderISOFinishedPanel() string {
	return strings.Join([]string{
		centerCanvas(sGray.Render("Finished")),
		"",
		centerCanvas(renderISOPrimaryAction("Reboot")),
	}, "\n")
}

func (m isoFinishedModel) helpHints() []tuiHint {
	return []tuiHint{{Key: "enter", Action: "reboot into the installed qvOS system"}}
}
