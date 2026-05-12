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
	frame      int
	width      int
	height     int
	logPath    string
	noInput    bool
	progress   float64
	target     float64
	status     string
	logLines   []string
	logOverlay bool
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
	p := tea.NewProgram(newISOProgressModel(logPath, noInput), options...)
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

func (m isoProgressModel) Init() tea.Cmd {
	return tea.Batch(tick(), readISOProgressSnapshotCmd(m.logPath))
}

func (m isoProgressModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		m.progress = advanceScriptProgress(m.progress, m.target)
		return m, tea.Batch(tick(), readISOProgressSnapshotCmd(m.logPath))
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case isoProgressSnapshotMsg:
		if msg.status != "" {
			m.status = msg.status
		}
		if msg.progress >= 0 {
			m.target = max(m.target, msg.progress)
		}
		m.logLines = msg.lines
	case tea.KeyPressMsg:
		if m.noInput {
			return m, nil
		}
		if msg.String() == "v" || msg.String() == "V" {
			m.logOverlay = !m.logOverlay
		}
	}
	return m, nil
}

func (m isoProgressModel) View() tea.View {
	width, height := safeDimensions(m.width, m.height)
	mode := layoutFor(width, height)
	reserveRows := fullCanvasReserveRows
	if m.logOverlay {
		reserveRows = 22
		if mode == layoutMid {
			reserveRows = 18
		}
	}

	if mode == layoutFull {
		canvasW, canvasH = fitIconCanvasReserved(width, height, minCanvasW, reserveRows)
	} else if mode == layoutMid {
		canvasW, canvasH = fitIconCanvasReserved(width, height, 1, reserveRows)
	} else {
		canvasW, canvasH = fitSmallBody(width), 0
	}

	var icon string
	if mode != layoutSmall {
		icon = renderBloom(m.frame)
	}

	body := m.renderISOProgressBody(mode, icon)
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
	v.WindowTitle = "qvOS install"
	return v
}

func (m isoProgressModel) renderISOProgressBody(mode layoutMode, icon string) string {
	var lines []string
	if icon != "" {
		lines = append(lines, icon, "")
	}
	lines = append(lines, m.renderISOProgressPanel(mode))
	if m.logOverlay {
		lines = append(lines, "", centerCanvas(m.renderISOProgressLogs(mode)))
	}
	return strings.Join(lines, "\n")
}

func (m isoProgressModel) renderISOProgressPanel(mode layoutMode) string {
	if mode == layoutSmall {
		return renderReducedProgress("INSTALLING", loadRun, m.progress, mode)
	}

	progress := m.progress
	if progress > 0.97 && m.target < 1 {
		progress = 0.97
	}
	percentRaw := fmt.Sprintf("%3d%%", int(progress*100))
	statusRaw := trimDisplay(m.status, progressBarWidth-len(percentRaw)-1)
	gap := progressBarWidth - len(statusRaw) - len(percentRaw)
	if gap < 1 {
		gap = 1
	}

	bar := renderProgressBar(loadRun, progress, m.frame)
	statusLine := sGray.Render(statusRaw) + strings.Repeat(" ", gap) + sMid.Render(percentRaw)
	hint := sRed.Render("v") + sBright.Render(" logs")
	if m.noInput {
		hint = sBright.Render("logs")
	}

	ctr := func(s string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s)
	}

	if mode == layoutMid {
		return strings.Join([]string{
			ctr(sWhite.Render("INSTALLING")),
			"",
			ctr(statusLine),
			"",
			ctr(bar),
			"",
			ctr(hint),
		}, "\n")
	}

	return strings.Join([]string{
		ctr(sWhite.Render("INSTALLING")),
		"",
		ctr(statusLine),
		"",
		ctr(bar),
		"",
		ctr(hint),
	}, "\n")
}

func (m isoProgressModel) renderISOProgressLogs(mode layoutMode) string {
	width := canvasW
	height := 9
	if mode == layoutMid {
		height = 6
	}
	if width < 24 {
		width = 24
	}
	if width > 82 {
		width = 82
	}

	contentWidth := width - 2
	lines := m.logLines
	if len(lines) == 0 {
		lines = []string{"waiting for install log"}
	}
	if len(lines) > height {
		lines = lines[len(lines)-height:]
	}

	var body []string
	for _, line := range lines {
		body = append(body, trimDisplay(line, contentWidth))
	}

	return lipgloss.NewStyle().
		Width(width).
		Foreground(lipgloss.Color(mid)).
		Padding(0, 1).
		Render(strings.Join(body, "\n"))
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
