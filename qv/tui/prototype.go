package main

import (
	"errors"
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type prototypeLaunch int

const (
	prototypeNone prototypeLaunch = iota
	prototypeScript
	prototypeSudo
	prototypeFailure
	prototypeAppInstall
	prototypeAppSync
	prototypeAppRemove
	prototypeBootInfo
	prototypeBootLoading
	prototypeBootFinale
)

var prototypeSections = []section{
	{
		name: "SESSIONS",
		items: []item{
			{"00", "SCRIPT", "Progress + logs"},
			{"01", "SUDO", "Masked authorization"},
			{"02", "FAILURE", "Error + retry"},
		},
	},
	{
		name: "APPS",
		items: []item{
			{"00", "INSTALL", "Fake package setup"},
			{"01", "SYNC", "Fake application sync"},
			{"02", "REMOVE", "Fake cleanup"},
		},
	},
	{
		name: "BOOT",
		items: []item{
			{"00", "INFO", "Installer questions"},
			{"01", "LOADING", "Persistent install"},
			{"02", "FINALE", "Installed + reboot"},
		},
	},
}

type prototypeHubModel struct {
	tab           int
	cursor        int
	frame         int
	width, height int
	fullscreen    bool
	launch        prototypeLaunch
	helpOverlay   bool
}

func runPrototype() error {
	for {
		result, err := newTUIProgram(prototypeHubModel{}).Run()
		if err != nil {
			return err
		}

		hub, ok := result.(prototypeHubModel)
		if !ok || hub.launch == prototypeNone {
			return nil
		}

		switch hub.launch {
		case prototypeBootInfo:
			if err := runISOInstaller(true); err != nil {
				return err
			}
		case prototypeBootLoading:
			if err := runISOProgressPrototype(); err != nil {
				return err
			}
		case prototypeBootFinale:
			if err := runISOFinishedPrototype(); err != nil {
				return err
			}
		default:
			if err := runPrototypeSession(prototypeProfileFor(hub.launch)); err != nil {
				return err
			}
		}
	}
}

func (m prototypeHubModel) Init() tea.Cmd {
	return tea.Batch(tick(), detectFullscreenCmd())
}

func (m prototypeHubModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
		if helpOverlay, handled := handleTUIHelpKey(m.helpOverlay, msg); handled {
			m.helpOverlay = helpOverlay
			return m, nil
		}
		switch msg.String() {
		case "ctrl+c", "esc", "q":
			return m, tea.Quit
		case "tab", "right", "l":
			m.tab = (m.tab + 1) % len(prototypeSections)
			m.cursor = 0
		case "shift+tab", "left", "h":
			m.tab = (m.tab - 1 + len(prototypeSections)) % len(prototypeSections)
			m.cursor = 0
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(prototypeSections[m.tab].items)-1 {
				m.cursor++
			}
		case "enter":
			m.launch = prototypeLaunch(1 + m.tab*3 + m.cursor)
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m prototypeHubModel) View() tea.View {
	termWidth, termHeight := safeDimensions(m.width, m.height)
	width, height := termWidth, termHeight
	mode := layoutFor(width, height)

	var body string
	if m.helpOverlay {
		body = renderTUIHelp(width, "prototype controls", m.helpHints())
	} else if isSideComposition(width, height, m.fullscreen) {
		body = m.renderSideBody(width, height)
	} else {
		iconWidth, iconHeight, showIcon := fitCenterStageCanvas(width, height, fullCanvasReserveRows)
		if showIcon {
			canvasW, canvasH = iconWidth, iconHeight
		} else {
			canvasW, canvasH = fitContentWidth(width), 0
		}

		icon := ""
		if showIcon {
			icon = m.renderIcon()
		}
		canvasW = fitContentWidth(width)
		body = m.renderBody(mode, icon)
	}

	view := tea.NewView(renderViewport(termWidth, termHeight, body))
	view.AltScreen = true
	view.MouseMode = tea.MouseModeNone
	view.BackgroundColor = lipgloss.Color(bgTerm)
	view.WindowTitle = "qvOS prototype"
	return view
}

func (m prototypeHubModel) renderIcon() string {
	return renderModelRole(modelCore, m.frame)
}

func (m prototypeHubModel) helpHints() []tuiHint {
	return []tuiHint{
		{Key: "↑ / ↓  or  j / k", Action: "move between items"},
		{Key: "← / →  or  h / l", Action: "change page"},
		{Key: "tab / shift+tab", Action: "change page"},
		{Key: "enter", Action: "open the selected prototype"},
		{Key: "esc / q / ctrl+c", Action: "exit the prototype"},
	}
}

func (m prototypeHubModel) persistentHints() []tuiHint {
	return []tuiHint{
		{Key: "↑↓", Action: "move"},
		{Key: "?", Action: "help"},
	}
}

func (m prototypeHubModel) renderSideBody(width, height int) string {
	leftWidth, _ := sideColumnWidths(width)
	canvasW, canvasH = leftWidth, 0
	left := m.renderMenu(layoutMobile)
	page := "PROTOTYPE / " + prototypeSections[m.tab].name
	right := renderIdentity("qvOS", page)

	if iconWidth, iconHeight, ok := fitSideIconCanvas(width, height); ok {
		canvasW, canvasH = iconWidth, iconHeight
		right = lipgloss.JoinVertical(lipgloss.Center, m.renderIcon(), "", renderIdentity("qvOS", page))
		canvasW, canvasH = leftWidth, 0
	}

	return renderSideColumns(width, left, right)
}

func (m prototypeHubModel) renderBody(mode layoutMode, icon string) string {
	var lines []string
	if icon != "" {
		lines = append(lines, centerCanvas(icon), "")
	}
	lines = append(lines, centerCanvas(sWhite.Render("qvOS")), centerCanvas(sDim.Render("PROTOTYPE")))
	if mode != layoutMobile {
		lines = append(lines, "")
	}
	lines = append(lines, m.renderMenu(mode))
	return strings.Join(lines, "\n")
}

func (m prototypeHubModel) renderMenu(mode layoutMode) string {
	if mode == layoutMobile {
		active := prototypeSections[m.tab]
		metrics := measureMenu(prototypeSections)
		showDescriptions := compactMenuRowWidth(metrics, true) <= canvasW
		rows := []string{centerCanvas(renderPrototypeActiveTab(m.tab))}
		if m.height >= 7 {
			rows = append(rows, "")
			for i, entry := range active.items {
				rows = append(rows, centerCanvas(renderCompactMenuRow(entry, i == m.cursor, metrics, canvasW, showDescriptions)))
			}
		} else {
			rows = append(rows, centerCanvas(renderCompactMenuRow(active.items[m.cursor], true, metrics, canvasW, showDescriptions)))
		}
		rows = append(rows, "", centerCanvas(renderTUIHints(canvasW, m.persistentHints()...)))
		return strings.Join(rows, "\n")
	}

	availableWidth := canvasW
	showDescriptions := prototypeMenuWidth(true) <= availableWidth
	rows := renderPrototypeMenuRows(m.tab, m.cursor, showDescriptions)
	help := renderTUIHints(canvasW, m.persistentHints()...)

	return strings.Join([]string{
		centerCanvas(renderPrototypeTabs(m.tab)),
		"",
		centerCanvas(rows),
		"",
		centerCanvas(help),
	}, "\n")
}

func renderPrototypeTabs(active int) string {
	var parts []string
	for index, entry := range prototypeSections {
		if index == active {
			parts = append(parts, sRed.Render("[")+sWhite.Render(entry.name)+sRed.Render("]"))
		} else {
			parts = append(parts, sDim.Render(" ")+sGray.Render(entry.name)+sDim.Render(" "))
		}
	}
	return strings.Join(parts, sDim.Render("  "))
}

func renderPrototypeActiveTab(active int) string {
	return sDim.Render("< ") + sWhite.Render(prototypeSections[active].name) + sDim.Render(" >")
}

func prototypeMenuWidth(withDescriptions bool) int {
	metrics := measureMenu(prototypeSections)
	width := 7 + metrics.titleWidth
	if withDescriptions {
		width += 3 + metrics.descWidth
	}
	return width
}

func renderPrototypeMenuRows(tab, cursor int, showDescriptions bool) string {
	metrics := measureMenu(prototypeSections)
	rowWidth := prototypeMenuWidth(showDescriptions)
	var rows []string
	for index, entry := range prototypeSections[tab].items {
		selected := index == cursor
		marker := sDim.Render("╎")
		idStyle := sGray
		titleStyle := sMid
		descStyle := sDim
		if selected {
			marker = sRed.Render("▐")
			idStyle = sRed
			titleStyle = sWhite
			descStyle = sGray
		}

		line := marker + "  " +
			idStyle.Render(entry.id) + "  " +
			lipgloss.PlaceHorizontal(metrics.titleWidth, lipgloss.Left, titleStyle.Render(entry.title))
		if showDescriptions {
			line += "   " + descStyle.Render(entry.desc)
		}
		rows = append(rows, lipgloss.PlaceHorizontal(rowWidth, lipgloss.Left, line))
	}
	return lipgloss.JoinVertical(lipgloss.Left, rows...)
}

type prototypeStage struct {
	at     float64
	status string
	log    string
}

type prototypeProfile struct {
	title        string
	complete     string
	requiresSudo bool
	failOnce     bool
	stages       []prototypeStage
}

func prototypeProfileFor(launch prototypeLaunch) prototypeProfile {
	switch launch {
	case prototypeSudo:
		return prototypeProfile{
			title:        "REPAIR",
			complete:     "repair prototype complete",
			requiresSudo: true,
			stages: []prototypeStage{
				{0.08, "checking qvOS source", "source checkout verified"},
				{0.34, "repairing desktop payloads", "desktop payloads reconciled"},
				{0.70, "checking enabled integrations", "enabled integrations healthy"},
				{0.94, "final verification", "repair smoke test passed"},
			},
		}
	case prototypeFailure:
		return prototypeProfile{
			title:    "BUILD",
			complete: "build retry complete",
			failOnce: true,
			stages: []prototypeStage{
				{0.08, "staging source", "staged qvOS source"},
				{0.30, "applying ISO integration", "applied temporary builder patch"},
				{0.54, "resolving packages", "package mirror unavailable"},
				{0.76, "assembling image", "created ISO filesystem"},
				{0.94, "auditing image", "embedded source audit passed"},
			},
		}
	case prototypeAppInstall:
		return prototypeProfile{
			title:    "INSTALL APP",
			complete: "application ready",
			stages: []prototypeStage{
				{0.08, "checking package", "package owner resolved"},
				{0.34, "installing application", "package installed"},
				{0.68, "applying integration", "desktop integration applied"},
				{0.94, "checking launch", "application launch check passed"},
			},
		}
	case prototypeAppSync:
		return prototypeProfile{
			title:    "SYNC APP",
			complete: "application synchronized",
			stages: []prototypeStage{
				{0.10, "reading application state", "application state loaded"},
				{0.40, "synchronizing configuration", "configuration synchronized"},
				{0.76, "repairing adapters", "application adapters repaired"},
				{0.94, "checking health", "application health check passed"},
			},
		}
	case prototypeAppRemove:
		return prototypeProfile{
			title:    "REMOVE APP",
			complete: "application removed",
			stages: []prototypeStage{
				{0.10, "finding owned artifacts", "owned artifacts inventoried"},
				{0.42, "removing integration", "desktop integration removed"},
				{0.72, "removing package", "package removed"},
				{0.94, "checking leftovers", "no owned artifacts remain"},
			},
		}
	default:
		return prototypeProfile{
			title:    "RUN SCRIPT",
			complete: "script prototype complete",
			stages: []prototypeStage{
				{0.08, "preparing session", "session environment ready"},
				{0.30, "running script", "script emitted structured progress"},
				{0.64, "applying changes", "fake changes applied"},
				{0.90, "verifying result", "fake verification passed"},
			},
		}
	}
}

var errPrototypeFailure = errors.New("package mirror unavailable")

type prototypeSessionModel struct {
	profile       prototypeProfile
	frame         int
	width, height int
	fullscreen    bool
	password      []rune
	authError     string
	running       bool
	progress      float64
	stageIndex    int
	logLines      []string
	logOverlay    bool
	terminalView  bool
	helpOverlay   bool
	failed        bool
	done          bool
	attempt       int
}

func runPrototypeSession(profile prototypeProfile) error {
	model := prototypeSessionModel{
		profile: profile,
		running: !profile.requiresSudo,
	}
	_, err := newTUIProgram(model).Run()
	return err
}

func (m prototypeSessionModel) Init() tea.Cmd {
	return tea.Batch(tick(), detectFullscreenCmd())
}

func (m prototypeSessionModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		if m.running {
			m.progress += 0.0045
			if m.profile.failOnce && m.attempt == 0 && m.progress >= 0.56 {
				m.progress = 0.56
				m.running = false
				m.failed = true
				m.logLines = append(m.logLines, "error: "+errPrototypeFailure.Error())
			} else {
				m.advanceStages()
				if m.progress >= 1 {
					m.progress = 1
					m.running = false
					m.done = true
				}
			}
		}
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, detectFullscreenCmd()
	case fullscreenStateMsg:
		m.fullscreen = msg.fullscreen
	case tea.KeyPressMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m *prototypeSessionModel) advanceStages() {
	for m.stageIndex < len(m.profile.stages) && m.progress >= m.profile.stages[m.stageIndex].at {
		stage := m.profile.stages[m.stageIndex]
		m.logLines = append(m.logLines, stage.log)
		m.stageIndex++
	}
}

func (m prototypeSessionModel) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if helpOverlay, handled := handleTUIHelpKeyWithQuestion(m.helpOverlay, msg, !m.awaitingAuthorization()); handled {
		m.helpOverlay = helpOverlay
		return m, nil
	}
	if m.terminalView {
		switch msg.String() {
		case "ctrl+v":
			m.terminalView = false
		case "v", "V":
			m.terminalView = false
			m.logOverlay = true
		case "ctrl+c", "esc":
			clearRunes(m.password)
			m.password = nil
			return m, tea.Quit
		}
		return m, nil
	}
	if msg.String() == "ctrl+c" || msg.String() == "esc" {
		clearRunes(m.password)
		m.password = nil
		return m, tea.Quit
	}

	if m.profile.requiresSudo && !m.running && !m.failed && !m.done && m.attempt == 0 {
		switch msg.String() {
		case "enter":
			if len(m.password) == 0 {
				m.authError = "password required"
				return m, nil
			}
			clearRunes(m.password)
			m.password = nil
			m.authError = ""
			m.running = true
			m.attempt = 1
			m.logLines = append(m.logLines, "prototype authorization accepted")
		case "backspace", "ctrl+h":
			if len(m.password) > 0 {
				m.password[len(m.password)-1] = 0
				m.password = m.password[:len(m.password)-1]
			}
		case "ctrl+u":
			clearRunes(m.password)
			m.password = nil
		default:
			if text := msg.Key().Text; text != "" {
				m.password = append(m.password, []rune(text)...)
				m.authError = ""
			}
		}
		return m, nil
	}

	switch msg.String() {
	case "v", "V":
		m.logOverlay = !m.logOverlay
	case "ctrl+v":
		m.terminalView = true
	case "r":
		if m.failed {
			m.attempt++
			m.progress = 0
			m.stageIndex = 0
			m.failed = false
			m.running = true
			m.logLines = append(m.logLines, "retrying with cached prototype data")
		}
	case "enter":
		if m.done || m.failed {
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m prototypeSessionModel) View() tea.View {
	termWidth, termHeight := safeDimensions(m.width, m.height)
	width, height := termWidth, termHeight
	mode := layoutFor(width, height)

	var body string
	if m.helpOverlay {
		body = renderTUIHelp(width, m.profile.title+" controls", m.helpHints())
	} else if m.terminalView {
		body = renderTUITerminalOutput(
			width,
			height,
			"PROTOTYPE / "+m.profile.title,
			m.logLines,
			m.terminalHints(),
		)
	} else if isSideComposition(width, height, m.fullscreen) {
		body = m.renderSideBody(width, height)
	} else {
		reserveRows := fullCanvasReserveRows
		if m.logOverlay {
			reserveRows = 22
		}
		iconWidth, iconHeight, showIcon := fitCenterStageCanvas(width, height, reserveRows)
		if showIcon {
			canvasW, canvasH = iconWidth, iconHeight
		} else {
			canvasW, canvasH = fitContentWidth(width), 0
		}

		icon := ""
		if showIcon {
			icon = renderModelRole(modelTwoRings, m.frame)
		}
		canvasW = fitContentWidth(width)
		body = m.renderBody(mode, icon)
	}

	view := tea.NewView(renderViewport(termWidth, termHeight, body))
	view.AltScreen = true
	view.MouseMode = tea.MouseModeNone
	view.BackgroundColor = lipgloss.Color(bgTerm)
	view.WindowTitle = "qvOS session prototype"
	return view
}

func (m prototypeSessionModel) renderSideBody(width, height int) string {
	leftWidth, _ := sideColumnWidths(width)
	canvasW, canvasH = leftWidth, 0
	left := m.renderPanel(layoutTablet)
	right := renderIdentity("qvOS", "PROTOTYPE / "+m.profile.title)

	if m.logOverlay {
		right = m.renderLogs(layoutTablet)
		return renderSideColumns(width, left, right)
	}
	if iconWidth, iconHeight, ok := fitSideIconCanvas(width, height); ok {
		canvasW, canvasH = iconWidth, iconHeight
		right = lipgloss.JoinVertical(
			lipgloss.Center,
			renderModelRole(modelTwoRings, m.frame),
			"",
			renderIdentity("qvOS", "PROTOTYPE / "+m.profile.title),
		)
		canvasW, canvasH = leftWidth, 0
	}
	return renderSideColumns(width, left, right)
}

func (m prototypeSessionModel) renderBody(mode layoutMode, icon string) string {
	var lines []string
	if icon != "" {
		lines = append(lines, centerCanvas(icon), "")
	}
	lines = append(lines, m.renderPanel(mode))
	if m.logOverlay {
		lines = append(lines, "", centerCanvas(m.renderLogs(mode)))
	}
	return strings.Join(lines, "\n")
}

func (m prototypeSessionModel) awaitingAuthorization() bool {
	return m.profile.requiresSudo && !m.running && !m.failed && !m.done && m.attempt == 0
}

func (m prototypeSessionModel) helpHints() []tuiHint {
	if m.terminalView {
		return []tuiHint{
			{Key: "ctrl+v", Action: "return to the qvOS view"},
			{Key: "v", Action: "return with the log panel open"},
			{Key: "esc / ctrl+c", Action: "return to the prototype hub"},
		}
	}
	if m.awaitingAuthorization() {
		return []tuiHint{
			{Key: "type", Action: "enter the prototype password"},
			{Key: "backspace", Action: "delete one character"},
			{Key: "ctrl+u", Action: "clear the password"},
			{Key: "enter", Action: "authorize the prototype"},
			{Key: "esc / ctrl+c", Action: "return to the prototype hub"},
		}
	}

	hints := []tuiHint{
		{Key: "v", Action: "toggle the qvOS log panel"},
		{Key: "ctrl+v", Action: "toggle original terminal output"},
		{Key: "esc / ctrl+c", Action: "return to the prototype hub"},
	}
	if m.failed {
		hints = append([]tuiHint{
			{Key: "r", Action: "retry the prototype"},
			{Key: "enter", Action: "return to the prototype hub"},
		}, hints...)
	} else if m.done {
		hints = append([]tuiHint{{Key: "enter", Action: "return to the prototype hub"}}, hints...)
	}
	return hints
}

func (m prototypeSessionModel) persistentHints() []tuiHint {
	if m.awaitingAuthorization() {
		return []tuiHint{
			{Key: "enter", Action: "authorize"},
			{Key: "f1", Action: "help"},
		}
	}

	if m.failed {
		return []tuiHint{
			{Key: "r", Action: "retry"},
			{Key: "?", Action: "help"},
		}
	}
	if m.done {
		return []tuiHint{
			{Key: "enter", Action: "return"},
			{Key: "?", Action: "help"},
		}
	}
	return []tuiHint{
		{Key: "esc", Action: "cancel"},
		{Key: "?", Action: "help"},
	}
}

func (m prototypeSessionModel) terminalHints() []tuiHint {
	return []tuiHint{
		{Key: "ctrl+v", Action: "qvOS view"},
		{Key: "?", Action: "help"},
	}
}

func (m prototypeSessionModel) renderPanel(mode layoutMode) string {
	if m.awaitingAuthorization() {
		title := centerCanvas(sWhite.Render(m.profile.title + " AUTH"))
		status := centerCanvas(sGray.Render("prototype only · no command will run"))
		if m.authError != "" {
			status = centerCanvas(sRed.Render(m.authError))
		}
		if mode == layoutMobile {
			content := strings.Join([]string{title, centerCanvas(renderPasswordField(m.password, mode))}, "\n")
			return appendTUIHints(content, canvasW, m.persistentHints()...)
		}
		content := strings.Join([]string{
			title,
			"",
			status,
			"",
			centerCanvas(renderPasswordField(m.password, mode)),
			"",
		}, "\n")
		return appendTUIHints(content, canvasW, m.persistentHints()...)
	}

	if mode == layoutMobile {
		phase := loadRun
		if m.failed {
			phase = loadErr
		}
		if m.done {
			phase = loadOK
		}
		return appendTUIHints(
			renderReducedProgress(m.profile.title, phase, m.progress, mode),
			canvasW,
			m.persistentHints()...,
		)
	}

	title := m.profile.title
	status := m.currentStatus()
	phase := loadRun
	if m.failed {
		title += " FAILED"
		status = errPrototypeFailure.Error()
		phase = loadErr
	} else if m.done {
		title = m.profile.complete
		phase = loadOK
	}

	percent := fmt.Sprintf("%3d%%", int(m.progress*100))
	status = trimDisplay(status, progressBarWidth-len(percent)-1)
	gap := progressBarWidth - len(status) - len(percent)
	if gap < 1 {
		gap = 1
	}
	statusStyle := sGray
	if m.failed {
		statusStyle = sRed
	}

	content := strings.Join([]string{
		centerCanvas(sWhite.Render(strings.ToUpper(title))),
		"",
		centerCanvas(statusStyle.Render(status) + strings.Repeat(" ", gap) + sMid.Render(percent)),
		"",
		centerCanvas(renderProgressBar(phase, m.progress, m.frame)),
		"",
	}, "\n")
	return appendTUIHints(content, canvasW, m.persistentHints()...)
}

func (m prototypeSessionModel) currentStatus() string {
	if m.stageIndex == 0 {
		return "starting prototype"
	}
	index := m.stageIndex - 1
	if index >= len(m.profile.stages) {
		return m.profile.complete
	}
	return m.profile.stages[index].status
}

func (m prototypeSessionModel) renderLogs(mode layoutMode) string {
	width := min(canvasW, 74)
	if width < 1 {
		width = 1
	}
	height := 9
	if mode == layoutTablet {
		height = 6
	}
	if mode == layoutMobile {
		height = 3
	}

	contentWidth := max(1, width-4)
	lines := append([]string(nil), m.logLines...)
	if len(lines) == 0 {
		lines = []string{"waiting for prototype logs"}
	}
	if len(lines) > height {
		lines = lines[len(lines)-height:]
	}
	for index, line := range lines {
		lines[index] = trimDisplay(line, contentWidth)
	}

	return lipgloss.NewStyle().
		Width(width).
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(deepRed)).
		Foreground(lipgloss.Color(mid)).
		Padding(0, 1).
		Render(strings.Join(lines, "\n"))
}

func runISOProgressPrototype() error {
	_, err := newTUIProgram(newISOProgressPrototypeModel()).Run()
	return err
}

func runISOFinishedPrototype() error {
	model := newISOFinishedModel("", "8m 42s")
	_, err := newTUIProgram(model, tea.WithFilter(filterISOFinishedExitMessages)).Run()
	return err
}
