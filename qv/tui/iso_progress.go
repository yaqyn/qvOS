package main

import (
	"bytes"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

const (
	defaultISOProgressLogPath = "/var/log/omarchy-install.log"
	isoProgressPollFrames     = 16
)

type isoProgressModel struct {
	frame        int
	width        int
	height       int
	logPath      string
	noInput      bool
	prototype    bool
	previewAge   int
	progress     float64
	status       string
	logLines     []string
	logOverlay   bool
	terminalView bool
	helpOverlay  bool
}

type isoProgressSnapshotMsg struct {
	status   string
	progress float64
	lines    []string
}

var isoProgressStepRE = regexp.MustCompile(`\(([0-9]+)/([0-9]+)\)`)

func runISOProgress(args []string) error {
	logPath := defaultISOProgressLogPath
	noInput := false
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--log":
			if i+1 >= len(args) {
				return fmt.Errorf("--log requires a path")
			}
			i++
			logPath = strings.TrimSpace(args[i])
		case "--no-input":
			noInput = true
		default:
			return fmt.Errorf("unknown --iso-progress option: %s", args[i])
		}
	}
	if logPath == "" {
		logPath = defaultISOProgressLogPath
	}

	options := []tea.ProgramOption{tea.WithFilter(filterISOProgressExitMessages)}
	// Output-only progress still consumes terminal protocol replies and accepts
	// read-only terminal/help controls. It ignores every action key.
	p := newTUIProgram(newISOProgressModel(logPath, noInput), options...)
	_, err := p.Run()
	return err
}

func filterISOProgressExitMessages(_ tea.Model, msg tea.Msg) tea.Msg {
	switch msg.(type) {
	case tea.QuitMsg, tea.InterruptMsg, tea.SuspendMsg:
		return nil
	default:
		return msg
	}
}

func newISOProgressModel(logPath string, noInput ...bool) isoProgressModel {
	outputOnly := len(noInput) > 0 && noInput[0]
	return isoProgressModel{
		logPath:  logPath,
		noInput:  outputOnly,
		status:   "preparing installation",
		progress: 0,
	}
}

func newISOProgressPrototypeModel() isoProgressModel {
	return isoProgressModel{
		prototype: true,
		status:    "preparing base system",
		logLines: []string{
			"prototype: no installer commands will run",
		},
	}
}

func (m isoProgressModel) Init() tea.Cmd {
	if m.prototype {
		return initialTUICommand(tick())
	}
	return initialTUICommand(tea.Batch(
		tick(),
		readISOProgressSnapshotCmd(m.logPath),
	))
}

func (m isoProgressModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		if m.prototype {
			m.advancePrototype()
			return m, tick()
		}
		if m.frame%isoProgressPollFrames == 0 {
			return m, tea.Batch(tick(), readISOProgressSnapshotCmd(m.logPath))
		}
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case isoProgressSnapshotMsg:
		if msg.status != "" {
			m.status = msg.status
		}
		if msg.progress >= 0 {
			m.progress = max(m.progress, msg.progress)
		}
		m.logLines = msg.lines
	case tea.KeyPressMsg:
		if helpOverlay, handled := handleTUIHelpKey(m.helpOverlay, msg); handled {
			m.helpOverlay = helpOverlay
			return m, nil
		}
		if m.terminalView {
			switch msg.String() {
			case "v", "V":
				m.terminalView = false
				m.logOverlay = true
			case "ctrl+v", "esc":
				m.terminalView = false
			}
			return m, nil
		}
		switch msg.String() {
		case "v", "V":
			m.logOverlay = !m.logOverlay
			return m, nil
		case "ctrl+v":
			m.terminalView = true
			return m, nil
		}
		if m.noInput {
			return m, nil
		}
		if m.prototype {
			switch msg.String() {
			case "esc", "ctrl+c":
				return m, tea.Quit
			case "enter":
				if m.progress >= 1 {
					return m, tea.Quit
				}
			}
		}
	}
	return m, nil
}

func (m *isoProgressModel) advancePrototype() {
	if m.progress >= 1 {
		return
	}

	m.previewAge++
	m.progress = min(1, float64(m.previewAge)/360)
	stages := []struct {
		at     float64
		status string
		log    string
	}{
		{0.02, "preparing base system", "installing Arch base system"},
		{0.18, "partitioning encrypted disk", "created encrypted qvOS layout"},
		{0.38, "installing system packages", "base packages installed"},
		{0.58, "installing qvOS", "started qvOS installation"},
		{0.76, "applying desktop configuration", "desktop configuration applied"},
		{0.90, "applying qvOS integrations", "qvOS integrations applied"},
		{1.00, "install complete", "installation completed successfully"},
	}

	completed := len(m.logLines) - 1
	for completed < len(stages) && m.progress >= stages[completed].at {
		stage := stages[completed]
		m.status = stage.status
		m.logLines = append(m.logLines, stage.log)
		completed++
	}
}

func (m isoProgressModel) View() tea.View {
	termWidth, termHeight := safeDimensions(m.width, m.height)
	width, height := termWidth, termHeight
	mode := layoutFor(width, height)

	var body string
	if m.helpOverlay {
		body = renderTUIHelp(width, "install progress controls", m.helpHints())
	} else if m.terminalView {
		body = renderTUITerminalOutput(
			width,
			height,
			"INSTALL",
			m.logLines,
			0,
			"",
			m.logEmptyStatus(),
			[]tuiHint{
				{Key: "v", Action: "split"},
				{Key: "ctrl+v", Action: "progress"},
				{Key: "?", Action: "help"},
			},
		)
	} else if m.logOverlay {
		body = m.renderISOProgressWithLog(width, height, mode)
	} else {
		canvasW, canvasH = fitContentWidth(width), 0
		body = m.renderISOProgressPanel(mode)
	}

	placed := renderViewport(termWidth, termHeight, body)

	v := tea.NewView(placed)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeNone
	v.BackgroundColor = lipgloss.Color(bgTerm)
	v.WindowTitle = "qvOS install"
	return v
}

func (m isoProgressModel) helpHints() []tuiHint {
	if m.terminalView {
		return []tuiHint{
			{Key: "v", Action: "show split progress and terminal"},
			{Key: "ctrl+v / esc", Action: "return to installation progress"},
		}
	}

	logAction := "show the terminal beside progress"
	if m.logOverlay {
		logAction = "hide the terminal beside progress"
	}
	hints := []tuiHint{
		{Key: "v", Action: logAction},
		{Key: "ctrl+v", Action: "open the full installer terminal"},
	}
	if m.prototype {
		hints = append(hints,
			tuiHint{Key: "enter", Action: "return when the prototype completes"},
			tuiHint{Key: "esc / ctrl+c", Action: "return to the prototype hub"},
		)
	}
	return hints
}

func (m isoProgressModel) persistentHints() []tuiHint {
	logAction := "log"
	if m.logOverlay {
		logAction = "progress"
	}
	return []tuiHint{
		{Key: "v", Action: logAction},
		{Key: "ctrl+v", Action: "terminal"},
		{Key: "?", Action: "help"},
	}
}

func (m isoProgressModel) renderISOProgressPanel(mode layoutMode) string {
	return renderProgressScreen(progressScreen{
		Title:    "Installing qvOS",
		Status:   m.status,
		Phase:    loadRun,
		Progress: m.progress,
		Bar:      true,
		Hints:    m.persistentHints(),
	}, mode)
}

func (m isoProgressModel) renderISOProgressWithLog(width, height int, mode layoutMode) string {
	if width >= desktopMinWidth && isSideComposition(width, height, false) {
		leftWidth, rightWidth := sideColumnWidths(width)
		canvasW, canvasH = leftWidth, 0
		progress := m.renderISOProgressPanel(layoutTablet)
		canvasW = rightWidth
		terminal := m.renderISOMiniTerminal(rightWidth, mode, height)
		canvasW = fitContentWidth(width)
		return renderISODividedColumns(width, progress, terminal)
	}

	canvasW, canvasH = fitContentWidth(width), 0
	progress := m.renderISOProgressPanel(mode)
	terminal := m.renderISOMiniTerminal(canvasW, mode, height)
	return lipgloss.JoinVertical(lipgloss.Center, progress, "", terminal)
}

func (m isoProgressModel) renderISOMiniTerminal(width int, mode layoutMode, height int) string {
	panelHeight := actionLogPanelHeight(mode, height)
	return lipgloss.JoinVertical(
		lipgloss.Center,
		sDim.Render("TERMINAL"),
		"",
		renderLogPanel(logPanelScreen{
			Lines:       m.logLines,
			Width:       min(logSideRightMax, max(1, width)),
			Height:      panelHeight,
			VisibleRows: max(1, panelHeight-2),
			Empty:       m.logEmptyStatus(),
			Border:      true,
		}),
	)
}

func (m isoProgressModel) logEmptyStatus() string {
	if m.progress < 1 {
		return preparingLabel(m.frame)
	}
	return "No command output"
}

func readISOProgressSnapshotCmd(logPath string) tea.Cmd {
	return func() tea.Msg {
		text, lines := readISOProgressLog(logPath)
		status, progress := parseISOProgressLog(text)
		return isoProgressSnapshotMsg{
			status:   status,
			progress: progress,
			lines:    lines,
		}
	}
}

func readISOProgressLog(logPath string) (string, []string) {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return "", nil
	}
	text := string(data)
	lines := make([]string, 0)
	cursor := 0
	_ = readTerminalFrames(bytes.NewReader(data), func(frame terminalFrame) error {
		if frame.update {
			frame.line = sanitizeLogLine(frame.line)
		}
		lines, cursor, _ = applyTerminalFrame(lines, cursor, frame)
		return nil
	})
	return text, visibleISOProgressLines(lines)
}

func visibleISOProgressLines(lines []string) []string {
	visible := make([]string, 0, len(lines))
	for _, line := range lines {
		lower := strings.ToLower(strings.TrimSpace(line))
		if strings.HasPrefix(lower, "qvos iso progress:") ||
			strings.HasPrefix(lower, "qvos target apply:") ||
			lower == "qvos install complete" {
			continue
		}
		visible = append(visible, line)
	}
	return visible
}

func parseISOProgressLog(text string) (string, float64) {
	clean := strings.TrimSpace(stripANSI(strings.ReplaceAll(strings.ReplaceAll(text, `\033[0m`, ""), `\e[0m`, "")))
	lower := strings.ToLower(clean)
	status := "preparing installation"
	progress := 0.0

	for _, marker := range []struct {
		token    string
		status   string
		progress float64
	}{
		{"cleaning up existing holders", "cleaning install disk", 0.04},
		{"fetching arch linux package databases", "syncing package database", 0.08},
		{"starting device modifications", "partitioning disk", 0.12},
		{"installing packages", "installing base system", 0.22},
		{"installation completed without any errors", "base system installed", 0.34},
		{"configuring login", "configuring login", 0.90},
		{"total:", "install complete", 1.00},
	} {
		if strings.Contains(lower, marker.token) && marker.progress >= progress {
			status = marker.status
			progress = marker.progress
		}
	}

	stepMatches := isoProgressStepRE.FindAllStringSubmatch(clean, -1)
	if len(stepMatches) > 0 {
		last := stepMatches[len(stepMatches)-1]
		current, currentErr := strconv.Atoi(last[1])
		total, totalErr := strconv.Atoi(last[2])
		if currentErr == nil && totalErr == nil && total > 0 {
			ratio := float64(current) / float64(total)
			if ratio < 0 {
				ratio = 0
			}
			if ratio > 1 {
				ratio = 1
			}
			progress = max(progress, 0.36+ratio*0.56)
		}
	}

	if scriptStatus, scriptProgress, ok := parseISOInstallScriptProgress(clean); ok {
		status = scriptStatus
		progress = max(progress, scriptProgress)
	}
	if strings.Contains(lower, "total:") {
		status = "install complete"
		progress = 1
	}

	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}
	return status, progress
}

func parseISOInstallScriptProgress(clean string) (string, float64, bool) {
	status := ""
	progress := -1.0
	for _, rawLine := range strings.Split(clean, "\n") {
		line := strings.TrimSpace(rawLine)
		marker := strings.Index(line, " Starting: ")
		if marker < 0 {
			continue
		}

		path := strings.TrimSpace(line[marker+len(" Starting: "):])
		if path == "" {
			continue
		}
		status = isoInstallScriptStatus(path)
		progress = max(progress, isoInstallScriptMilestone(path))
	}

	if status == "" || progress < 0 {
		return "", -1, false
	}
	return status, progress, true
}

func isoInstallScriptStatus(path string) string {
	name := path
	if index := strings.LastIndex(name, "/"); index >= 0 {
		name = name[index+1:]
	}
	name = strings.TrimSuffix(name, ".sh")
	name = strings.ReplaceAll(strings.ReplaceAll(name, "-", " "), "_", " ")

	switch {
	case strings.Contains(path, "/qv/security/"):
		return "applying security defaults"
	case strings.Contains(path, "/qv/install/"):
		return "applying qvOS configuration"
	case strings.Contains(path, "/install/preflight/"):
		return "checking " + name
	case strings.Contains(path, "/install/packaging/"):
		return "installing " + name
	case strings.Contains(path, "/install/config/"):
		return "configuring " + name
	case strings.Contains(path, "/install/login/"):
		return "configuring " + name
	default:
		return "running " + name
	}
}

func isoInstallScriptMilestone(path string) float64 {
	switch {
	case strings.Contains(path, "/qv/security/"):
		return 0.96
	case strings.Contains(path, "/install/login/"):
		return 0.92
	case strings.Contains(path, "/qv/install/"):
		return 0.88
	case strings.Contains(path, "/install/config/"):
		return 0.72
	case strings.Contains(path, "/install/packaging/"):
		return 0.62
	case strings.Contains(path, "/install/preflight/"):
		return 0.58
	default:
		return 0.36
	}
}
