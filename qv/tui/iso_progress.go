package main

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

const (
	defaultISOProgressLogPath = "/var/log/omarchy-install.log"
	isoProgressTailBytes      = 96 * 1024
)

type isoProgressModel struct {
	frame         int
	width         int
	height        int
	fullscreen    bool
	logPath       string
	noInput       bool
	prototype     bool
	previewAge    int
	progress      float64
	target        float64
	status        string
	logLines      []string
	logOverlay    bool
	terminalView  bool
	logScroll     int
	logCopyStatus string
	helpOverlay   bool
}

type isoProgressSnapshotMsg struct {
	status   string
	progress float64
	lines    []string
}

var (
	isoProgressStepRE  = regexp.MustCompile(`\(([0-9]+)/([0-9]+)\)`)
	isoProgressStartRE = regexp.MustCompile(`Starting: .*/([^/\s]+)\.sh`)
)

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
	if noInput {
		options = append(options, tea.WithInput(nil))
	}
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
		logPath:    logPath,
		noInput:    outputOnly,
		status:     "base system",
		progress:   0,
		target:     0,
		logOverlay: outputOnly,
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
		return tea.Batch(tick(), detectFullscreenCmd())
	}
	return tea.Batch(tick(), detectFullscreenCmd(), readISOProgressSnapshotCmd(m.logPath))
}

func (m isoProgressModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		if m.prototype {
			m.advancePrototype()
			return m, tick()
		}
		m.progress = advanceScriptProgress(m.progress, m.target)
		return m, tea.Batch(tick(), readISOProgressSnapshotCmd(m.logPath))
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, detectFullscreenCmd()
	case fullscreenStateMsg:
		m.fullscreen = msg.fullscreen
	case isoProgressSnapshotMsg:
		if msg.status != "" {
			m.status = msg.status
		}
		if msg.progress >= 0 {
			m.target = max(m.target, msg.progress)
		}
		if m.logScroll > 0 && len(msg.lines) > len(m.logLines) {
			m.logScroll = min(
				m.logScroll+len(msg.lines)-len(m.logLines),
				max(0, len(msg.lines)-m.logViewportRows()),
			)
		}
		m.logLines = msg.lines
	case tuiLogCopiedMsg:
		m.logCopyStatus = tuiLogCopyResultStatus(msg.err)
		return m, nil
	case tea.KeyPressMsg:
		if m.noInput {
			return m, nil
		}
		if helpOverlay, handled := handleTUIHelpKey(m.helpOverlay, msg); handled {
			m.helpOverlay = helpOverlay
			return m, nil
		}
		if m.logOverlay || m.terminalView {
			if offset, handled := updateTUILogScroll(
				m.logScroll,
				msg.String(),
				len(m.logLines),
				m.logViewportRows(),
			); handled {
				m.logScroll = offset
				return m, nil
			}
		}
		if m.terminalView {
			switch msg.String() {
			case "y", "Y":
				var cmd tea.Cmd
				m.logCopyStatus, cmd = beginTUILogCopy(m.logLines)
				return m, cmd
			case "ctrl+v":
				m.terminalView = false
				m.logCopyStatus = ""
			case "v", "V":
				m.terminalView = false
				m.logOverlay = true
				m.logCopyStatus = ""
			case "esc", "ctrl+c":
				if m.prototype {
					return m, tea.Quit
				}
			}
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
		if msg.String() == "v" || msg.String() == "V" {
			m.logOverlay = !m.logOverlay
		}
		if msg.String() == "ctrl+v" {
			m.terminalView = true
			m.logCopyStatus = ""
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
	m.target = m.progress
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
		if m.logScroll > 0 {
			m.logScroll = min(
				m.logScroll+1,
				max(0, len(m.logLines)-m.logViewportRows()),
			)
		}
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
			m.logScroll,
			m.logCopyStatus,
			m.terminalHints(),
		)
	} else if isSideComposition(width, height, m.fullscreen) {
		body = m.renderISOSideBody(width, height)
	} else {
		reserveRows := fullCanvasReserveRows
		if m.logOverlay {
			reserveRows = 22
			if mode == layoutTablet {
				reserveRows = 18
			}
		}

		iconWidth, iconHeight, showIcon := fitCenterStageCanvas(width, height, reserveRows)
		if showIcon {
			canvasW, canvasH = iconWidth, iconHeight
		} else {
			canvasW, canvasH = fitContentWidth(width), 0
		}

		var icon string
		if showIcon {
			icon = renderModelRole(modelTwoRings, m.frame)
		}
		canvasW = fitContentWidth(width)
		body = m.renderISOProgressBody(mode, icon)
	}

	placed := renderViewport(termWidth, termHeight, body)

	v := tea.NewView(placed)
	v.AltScreen = true
	if m.terminalView {
		v.MouseMode = tea.MouseModeNone
	} else {
		v.MouseMode = tea.MouseModeCellMotion
	}
	v.BackgroundColor = lipgloss.Color(bgTerm)
	v.WindowTitle = "qvOS install"
	return v
}

func (m isoProgressModel) renderISOSideBody(width, height int) string {
	leftWidth, _ := sideColumnWidths(width)
	canvasW, canvasH = leftWidth, 0
	left := m.renderISOProgressPanel(layoutTablet)
	right := renderIdentity("qvOS", "INSTALL / LOADING")

	if m.logOverlay {
		right = m.renderISOProgressLogs(layoutTablet)
		return renderSideColumns(width, left, right)
	}
	if iconWidth, iconHeight, ok := fitSideIconCanvas(width, height); ok {
		canvasW, canvasH = iconWidth, iconHeight
		right = lipgloss.JoinVertical(
			lipgloss.Center,
			renderModelRole(modelTwoRings, m.frame),
			"",
			renderIdentity("qvOS", "INSTALL / LOADING"),
		)
		canvasW, canvasH = leftWidth, 0
	}
	return renderSideColumns(width, left, right)
}

func (m isoProgressModel) renderISOProgressBody(mode layoutMode, icon string) string {
	var lines []string
	if icon != "" {
		lines = append(lines, centerCanvas(icon), "")
	}
	lines = append(lines, m.renderISOProgressPanel(mode))
	if m.logOverlay {
		lines = append(lines, "", centerCanvas(m.renderISOProgressLogs(mode)))
	}
	return strings.Join(lines, "\n")
}

func (m isoProgressModel) helpHints() []tuiHint {
	if m.terminalView {
		hints := []tuiHint{
			{Key: "ctrl+v", Action: "switch to the qvOS install view"},
			{Key: "v", Action: "return with the log panel open"},
		}
		hints = append(hints, tuiTerminalLogHints()...)
		if m.prototype {
			hints = append(hints, tuiHint{Key: "esc / ctrl+c", Action: "return to the prototype hub"})
		}
		return hints
	}

	hints := []tuiHint{
		{Key: "v", Action: "toggle the qvOS install log panel"},
		{Key: "ctrl+v", Action: "toggle original terminal output"},
	}
	if m.logOverlay {
		hints = append(hints, tuiLogScrollHints()...)
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
	if m.noInput {
		return nil
	}
	logAction := "logs"
	if m.logOverlay {
		logAction = "close logs"
	}
	if m.prototype && m.progress >= 1 {
		return []tuiHint{
			{Key: "enter", Action: "return"},
			tuiHelpHint(),
		}
	}
	return []tuiHint{
		{Key: "v", Action: logAction},
		tuiHelpHint(),
	}
}

func (m isoProgressModel) terminalHints() []tuiHint {
	return []tuiHint{
		{Key: "ctrl+v", Action: "switch"},
		tuiHelpHint(),
	}
}

func (m isoProgressModel) renderISOProgressPanel(mode layoutMode) string {
	progress := m.progress
	if progress > 0.97 && m.target < 1 {
		progress = 0.97
	}
	return renderProgressScreen(progressScreen{
		Title:    "INSTALLING",
		Status:   m.status,
		Phase:    loadRun,
		Progress: progress,
		Bar:      true,
		Hints:    m.persistentHints(),
	}, mode)
}

func isoProgressLogRows(mode layoutMode) int {
	height := 9
	if mode == layoutTablet {
		height = 6
	}
	return height
}

func (m isoProgressModel) logViewportRows() int {
	if m.terminalView {
		return terminalOutputContentHeight(m.height)
	}
	mode := layoutFor(m.width, m.height)
	if isSideComposition(m.width, m.height, m.fullscreen) {
		mode = layoutTablet
	}
	return isoProgressLogRows(mode)
}

func (m isoProgressModel) renderISOProgressLogs(mode layoutMode) string {
	width := canvasW
	if width < 1 {
		width = 1
	}
	if width > 82 {
		width = 82
	}

	height := isoProgressLogRows(mode)
	return renderLogPanel(logPanelScreen{
		Lines:       m.logLines,
		Width:       width,
		VisibleRows: height,
		Scroll:      m.logScroll,
		Empty:       "waiting for install log",
	})
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
	data, err := readTail(logPath, isoProgressTailBytes)
	if err != nil {
		return "", nil
	}
	text := string(data)
	rawLines := strings.Split(text, "\n")
	lines := make([]string, 0, len(rawLines))
	for _, line := range rawLines {
		clean := sanitizeLogLine(line)
		if clean == "" {
			continue
		}
		lines = appendLimited(lines, clean, maxScriptLogLines)
	}
	return text, lines
}

func readTail(path string, maxBytes int64) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return nil, err
	}

	offset := int64(0)
	if info.Size() > maxBytes {
		offset = info.Size() - maxBytes
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		return nil, err
	}

	data, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}
	return data, nil
}

func parseISOProgressLog(text string) (string, float64) {
	clean := strings.TrimSpace(stripANSI(strings.ReplaceAll(strings.ReplaceAll(text, `\033[0m`, ""), `\e[0m`, "")))
	lower := strings.ToLower(clean)
	status := "base system"
	progress := 0.01

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
		{"qvos iso progress: applying qvos baseline", "applying qvOS baseline", 0.92},
		{"qvos iso hook: apply qvos", "applying qvOS baseline", 0.92},
		{"qvos iso: applying qvos baseline", "applying qvOS baseline", 0.92},
		{"qvos target apply: runtime installed", "installing runtime", 0.93},
		{"qvos iso: removing omarchy preinstalled webapps", "removing webapps", 0.985},
		{"qvos install complete", "qvOS baseline complete", 0.96},
		{"qvos iso: first install complete", "qvOS baseline complete", 0.99},
		{"total:", "install complete", 1.00},
	} {
		if strings.Contains(lower, marker.token) {
			status = marker.status
			progress = marker.progress
		}
	}

	if applyStatus, applyProgress, ok := parseISOApplyDomainProgress(clean); ok && applyProgress >= progress {
		status = applyStatus
		progress = applyProgress
	}
	if applyStatus, applyProgress, ok := parseISOApplyCountProgress(clean); ok && applyProgress >= progress {
		status = applyStatus
		progress = applyProgress
	}

	startMatches := isoProgressStartRE.FindAllStringSubmatch(clean, -1)
	if len(startMatches) > 0 {
		last := startMatches[len(startMatches)-1]
		if len(last) > 1 && last[1] != "" {
			status = strings.ReplaceAll(last[1], "-", " ")
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

	if strings.Contains(lower, "qvos install complete") {
		status = "qvOS baseline complete"
		progress = max(progress, 0.96)
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

func parseISOApplyDomainProgress(clean string) (string, float64, bool) {
	const (
		start = 0.935
		span  = 0.045
	)

	status := ""
	progress := -1.0
	for _, rawLine := range strings.Split(clean, "\n") {
		line := strings.TrimSpace(rawLine)
		lowerLine := strings.ToLower(line)
		if !strings.HasPrefix(lowerLine, "qvos target apply:") {
			continue
		}

		name := strings.TrimSpace(line[len("qvOS target apply:"):])
		if name == "" || strings.HasPrefix(strings.ToLower(name), "runtime installed") {
			continue
		}

		for i, domain := range installDomainOrder {
			if strings.EqualFold(name, domain) || strings.HasPrefix(strings.ToLower(name), strings.ToLower(domain)+" ") {
				status = "applying " + strings.ToLower(domain)
				progress = start + (float64(i+1)/float64(len(installDomainOrder)+1))*span
				break
			}
		}
	}

	if progress < 0 {
		return "", -1, false
	}
	if progress > 0.985 {
		progress = 0.985
	}
	return status, progress, true
}

func parseISOApplyCountProgress(clean string) (string, float64, bool) {
	const (
		prefix = "qvOS ISO progress: applying qvOS domain "
		start  = 0.925
		span   = 0.055
	)

	status := ""
	progress := -1.0
	for _, rawLine := range strings.Split(clean, "\n") {
		line := strings.TrimSpace(rawLine)
		if !strings.HasPrefix(line, prefix) {
			continue
		}

		fields := strings.Fields(strings.TrimSpace(strings.TrimPrefix(line, prefix)))
		if len(fields) < 3 {
			continue
		}

		current, currentErr := strconv.Atoi(fields[0])
		total, totalErr := strconv.Atoi(fields[1])
		if currentErr != nil || totalErr != nil || total <= 0 {
			continue
		}

		if current < 0 {
			current = 0
		}
		if current > total {
			current = total
		}

		name := strings.Join(fields[2:], " ")
		status = "applying " + strings.ToLower(name)
		progress = start + (float64(current)/float64(total))*span
	}

	if progress < 0 {
		return "", -1, false
	}
	if progress > 0.985 {
		progress = 0.985
	}
	return status, progress, true
}
