package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// -- palette --

const (
	bgTerm  = "#060606" // terminal background — set when qvos launches
	dim     = "#2a2a2a"
	gray    = "#5a5a5a"
	mid     = "#8a8a8a"
	bright  = "#c8c8c8"
	white   = "#f0f0f0"
	red     = "#c81010"
	hotRed  = "#ff2828"
	deepRed = "#6a0606"
)

var (
	sDim     = lipgloss.NewStyle().Foreground(lipgloss.Color(dim))
	sGray    = lipgloss.NewStyle().Foreground(lipgloss.Color(gray))
	sMid     = lipgloss.NewStyle().Foreground(lipgloss.Color(mid))
	sBright  = lipgloss.NewStyle().Foreground(lipgloss.Color(bright))
	sWhite   = lipgloss.NewStyle().Foreground(lipgloss.Color(white)).Bold(true)
	sRed     = lipgloss.NewStyle().Foreground(lipgloss.Color(red)).Bold(true)
	sHot     = lipgloss.NewStyle().Foreground(lipgloss.Color(hotRed)).Bold(true)
	sDeepRed = lipgloss.NewStyle().Foreground(lipgloss.Color(deepRed))
)

// -- menu data --

type item struct{ id, title, desc string }

type section struct {
	name  string
	items []item
}

var sections = []section{
	{
		name: "INSTALL",
		items: []item{
			{"00", "APPLY", "Install qvOS"},
			{"01", "UPDATE", "Sync qvOS"},
			{"02", "RESET", "Reset to Omarchy"},
			{"03", "BUILD", "Build qvOS ISO"},
		},
	},
	{
		name: "SYSTEM",
		items: []item{
			{"00", "DOCTOR", "Run checks"},
			{"01", "UPDATE", "Sync qvOS"},
			{"02", "BACKUP", "Save snapshot"},
		},
	},
	{
		name: "TWEAK",
		items: []item{
			{"00", "KEYBIND", "Edit bindings"},
			{"01", "BROWSER", "Set browser"},
			{"02", "DEBLOAT", "Remove extras"},
		},
	},
	{
		name: "ABOUT",
		items: []item{
			{"00", "YAQIN", "Creator"},
			{"01", "EMAIL", "Contact"},
			{"02", "TOOLS", "Credits"},
		},
	},
}

type layoutMode int

const (
	layoutFull layoutMode = iota
	layoutMid
	layoutSmall
)

func layoutFor(width, height int) layoutMode {
	switch {
	case width < 42 || height < 18:
		return layoutSmall
	case width < 90 || height < 34:
		return layoutMid
	default:
		return layoutFull
	}
}

func safeDimensions(width, height int) (int, int) {
	if width < 1 {
		width = 1
	}
	if height < 1 {
		height = 1
	}
	return width, height
}

// computeMenuRowWidth returns the widest rendered row across every section,
// given whether descriptions are shown. mirrors the layout of the rows built
// in View(). used so rows pad to a uniform width — left edge stays fixed
// across tab switches, no visual shift from longer descriptions.
func computeMenuRowWidth(withDesc bool) int {
	max := 0
	for _, s := range sections {
		for _, it := range s.items {
			w := 7 + len(it.title) // marker(1) + "  " + id(2) + "  " + title
			if withDesc {
				w += 3 + len(it.desc)
			}
			if w > max {
				max = w
			}
		}
	}
	return max
}

func menuDescriptionsFit(availableWidth int) bool {
	return computeMenuRowWidth(true) <= availableWidth
}

// -- animation ticker --

const (
	framesPerSecond = 30
	framesPerTick   = 2
)

type tickMsg time.Time

func tick() tea.Cmd {
	return tea.Tick(time.Second/framesPerSecond, func(t time.Time) tea.Msg { return tickMsg(t) })
}

// -- model --

type loadPhase int

const (
	loadRun loadPhase = iota
	loadOK
	loadErr
)

type actionMode int

const (
	actionBuild actionMode = iota
	actionReset
	actionApply
	actionUpdate
)

type model struct {
	tab             int
	cursor          int
	frame           int
	width, height   int
	loading         bool
	action          actionMode
	loadStart       int
	scriptRunning   bool
	scriptDone      bool
	scriptErr       error
	scriptPath      string
	sudoChecking    bool
	sudoPrompt      bool
	sudoPassword    []rune
	sudoErr         error
	scriptCancel    context.CancelFunc
	scriptEvents    <-chan scriptEvent
	scriptStatus    string
	scriptProgress  float64
	scriptTarget    float64
	scriptLogLines  []string
	scriptArtifact  string
	scriptRelease   string
	scriptCanceling bool
	scriptCanceled  bool
	logOverlay      bool
}

func isRootAction(action actionMode) bool {
	return action == actionApply || action == actionReset || action == actionUpdate
}

func isScriptAction(action actionMode) bool {
	return action == actionBuild || isRootAction(action)
}

func (m model) loadPhase() loadPhase {
	if isScriptAction(m.action) {
		switch {
		case m.scriptErr != nil:
			return loadErr
		case m.scriptDone:
			return loadOK
		default:
			return loadRun
		}
	}

	return loadRun
}

func (m model) loadProgress() float64 {
	if isScriptAction(m.action) {
		if m.scriptErr != nil {
			if m.scriptPath == "" {
				return 0
			}
			return 1
		}
		if m.scriptDone {
			return 1
		}
		if m.sudoPrompt || m.sudoChecking {
			return 0
		}
		progress := m.scriptProgress
		if progress < 0 {
			progress = 0
		}
		if progress > 0.97 && !m.scriptDone {
			progress = 0.97
		}
		if progress > 1 {
			progress = 1
		}
		return progress
	}
	return 0
}

func advanceScriptProgress(current float64, target float64) float64 {
	if target <= current {
		return current
	}

	delta := target - current
	step := 0.0015 + delta*0.045
	if step > 0.007 {
		step = 0.007
	}
	if step < 0.002 {
		step = 0.002
	}
	if current+step > target {
		return target
	}
	return current + step
}

func realisticProgress(progress float64) float64 {
	if progress <= 0 {
		return 0
	}
	if progress >= 1 {
		return 1
	}

	type segment struct {
		startIn  float64
		endIn    float64
		startOut float64
		endOut   float64
	}

	earlyHoldStart := 0.12
	earlyHoldEnd := earlyHoldStart + 1.0/float64(buildDurationSeconds)
	midHoldStart := 0.52
	midHoldEnd := midHoldStart + 2.0/float64(buildDurationSeconds)
	finalApproach := 0.97

	segments := []segment{
		{0.00, earlyHoldStart, 0.00, 0.18},
		{earlyHoldStart, earlyHoldEnd, 0.18, 0.18},
		{earlyHoldEnd, midHoldStart, 0.18, 0.50},
		{midHoldStart, midHoldEnd, 0.50, 0.50},
		{midHoldEnd, finalApproach, 0.50, 0.97},
		{finalApproach, 1.00, 0.97, 1.00},
	}

	for _, s := range segments {
		if progress <= s.endIn {
			if s.endIn == s.startIn {
				return s.endOut
			}
			local := (progress - s.startIn) / (s.endIn - s.startIn)
			local = local * local * (3 - 2*local)
			return s.startOut + local*(s.endOut-s.startOut)
		}
	}
	return progress
}

func (m model) Init() tea.Cmd { return tick() }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		if m.scriptRunning && !m.sudoPrompt && !m.sudoChecking {
			m.scriptProgress = advanceScriptProgress(m.scriptProgress, m.scriptTarget)
		}
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height

	case scriptDoneMsg:
		if m.action != msg.action || m.scriptPath != msg.script {
			return m, nil
		}
		m.scriptRunning = false
		m.scriptDone = true
		m.scriptErr = msg.err
		m.scriptCancel = nil
		m.scriptEvents = nil
		m.scriptCanceling = false
		if msg.err == nil {
			m.scriptProgress = 1
			m.scriptTarget = 1
		}
		return m, nil

	case scriptStartedMsg:
		if m.action != msg.action || m.scriptPath != msg.script {
			return m, nil
		}
		m.scriptCancel = msg.cancel
		m.scriptEvents = msg.events
		return m, waitScriptEventCmd(msg.events)

	case scriptEventMsg:
		if m.action != msg.event.action || m.scriptPath != msg.event.script {
			return m, nil
		}
		if msg.event.line != "" {
			cleanLine := sanitizeLogLine(msg.event.line)
			m.scriptLogLines = appendLimited(m.scriptLogLines, cleanLine, maxScriptLogLines)
			if m.action == actionBuild {
				if artifact, ok := buildArtifactFromLine(cleanLine); ok {
					m.scriptArtifact = artifact
				}
				if release, ok := buildReleaseFromLine(cleanLine); ok {
					m.scriptRelease = release
				}
			}
		}
		statusFloor := max(m.scriptTarget, m.scriptProgress)
		if msg.event.status != "" && (msg.event.progress < 0 || msg.event.progress >= statusFloor || msg.event.done) {
			m.scriptStatus = msg.event.status
		}
		if msg.event.progress >= 0 {
			if !msg.event.done || msg.event.err == nil {
				m.scriptTarget = max(m.scriptTarget, msg.event.progress)
			}
		}
		if msg.event.done {
			canceled := errors.Is(msg.event.err, errScriptCanceled) && m.scriptCanceling
			m.scriptRunning = false
			m.scriptDone = true
			m.scriptCanceled = canceled
			m.scriptErr = msg.event.err
			if canceled {
				m.scriptErr = nil
				m.scriptStatus = "cleanup complete - good to go"
			}
			m.scriptCancel = nil
			m.scriptEvents = nil
			m.scriptCanceling = false
			if msg.event.err == nil || canceled {
				m.scriptProgress = 1
				m.scriptTarget = 1
			}
			return m, nil
		}
		return m, waitScriptEventCmd(m.scriptEvents)

	case sudoCheckDoneMsg:
		if m.action != msg.action || m.scriptPath != msg.script {
			return m, nil
		}
		m.sudoChecking = false
		if msg.err != nil {
			m.sudoPrompt = true
			return m, nil
		}
		return m.startRootScriptRun(msg.action, msg.script)

	case sudoAuthDoneMsg:
		if m.action != msg.action || m.scriptPath != msg.script {
			return m, nil
		}
		m.sudoChecking = false
		if msg.err != nil {
			m.sudoPrompt = true
			m.sudoErr = msg.err
			return m, nil
		}
		return m.startRootScriptRun(msg.action, msg.script)

	case tea.MouseClickMsg:
		if !m.loading {
			return m.mainMouse(msg)
		}
		return m, nil

	case tea.MouseWheelMsg:
		return m, nil

	case tea.KeyPressMsg:
		if m.loading {
			if m.sudoPrompt {
				return m.handleSudoKey(msg)
			}
			phase := m.loadPhase()
			switch msg.String() {
			case "ctrl+c":
				if m.scriptRunning && m.scriptCancel != nil {
					m.scriptCanceling = true
					m.scriptStatus = "cleaning build stage"
					m.scriptTarget = max(m.scriptTarget, 0.98)
					m.scriptCancel()
					return m, nil
				}
				if m.scriptRunning || m.sudoChecking {
					return m, nil
				}
				return m, tea.Quit
			case "esc":
				if !m.scriptRunning && !m.sudoChecking {
					m.loading = false
				}
			case "enter":
				if phase != loadRun {
					m.loading = false
				}
			case "v":
				if isScriptAction(m.action) {
					m.logOverlay = !m.logOverlay
				}
			case "r":
				if isRootAction(m.action) && phase == loadErr {
					return m.startRootAction(m.action)
				}
				if m.action == actionBuild && phase == loadErr {
					return m.startBuildAction()
				}
			}
			return m, nil
		}
		n := len(sections[m.tab].items)
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "tab", "right", "l":
			m.tab = (m.tab + 1) % len(sections)
			m.cursor = 0
		case "shift+tab", "left", "h":
			m.tab = (m.tab - 1 + len(sections)) % len(sections)
			m.cursor = 0
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < n-1 {
				m.cursor++
			}
		case "enter":
			if m.tab == 0 && m.cursor == 0 {
				return m.startRootAction(actionApply)
			}
			if m.tab == 0 && m.cursor == 1 {
				return m.startRootAction(actionUpdate)
			}
			if m.tab == 0 && m.cursor == 2 {
				return m.startRootAction(actionReset)
			}
			if m.tab == 0 && m.cursor == 3 {
				return m.startBuildAction()
			}
		}
	}
	return m, nil
}

func (m model) View() tea.View {
	width, height := safeDimensions(m.width, m.height)
	mode := layoutFor(width, height)

	// scale the canvas to fit — mutates canvasW/canvasH for this frame
	if mode == layoutFull {
		canvasW, canvasH = fitCanvas(width, height)
	} else if mode == layoutMid {
		canvasW, canvasH = fitMidCanvas(width, height)
	} else {
		canvasW, canvasH = fitSmallBody(width), 0
	}

	icon := m.renderIconForMode(mode)

	var body string
	if mode == layoutFull {
		body = m.renderFullBody(icon)
	} else {
		body = m.renderReducedBody(mode, icon)
	}

	placed := lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, body)

	v := tea.NewView(placed)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeCellMotion
	v.BackgroundColor = lipgloss.Color(bgTerm)
	v.WindowTitle = "qvOS"
	return v
}

func (m model) renderFullBody(icon string) string {
	return m.renderNormalFullBody(icon)
}

func (m model) renderNormalFullBody(icon string) string {
	title := sWhite.Render("qvOS")
	tagline := sDim.Render("· · · · ·")
	return lipgloss.JoinVertical(lipgloss.Center,
		icon, "", title, tagline, "", m.renderMiddle(layoutFull),
	)
}

func (m model) renderIconForMode(mode layoutMode) string {
	if mode == layoutSmall {
		return ""
	}
	return m.renderActiveIcon()
}

func (m model) renderActiveIcon() string {
	switch m.tab {
	case 1:
		return renderKnot(m.frame)
	case 2:
		return renderHopf(m.frame)
	case 3:
		return renderTorus(m.frame)
	default:
		return renderBloom(m.frame)
	}
}

func (m model) renderMiddle(mode layoutMode) string {
	if m.loading {
		if isScriptAction(m.action) {
			return m.renderRootActionFor(mode)
		}
	}

	if mode == layoutFull {
		return m.renderFullMenu()
	}
	if mode == layoutMid {
		return m.renderMidMenu()
	}
	return m.renderReducedMenu(mode)
}

func (m model) renderReducedBody(mode layoutMode, icon string) string {
	titleRows, middleRows, gapRows := m.reducedBodyRows(mode)
	var lines []string
	if icon != "" {
		lines = append(lines, icon)
	}
	for i := 0; i < gapRows; i++ {
		lines = append(lines, "")
	}
	if titleRows > 0 {
		lines = append(lines, sWhite.Render("qvOS"), "")
	}
	if middleRows > 0 {
		lines = append(lines, m.renderMiddle(mode))
	}
	return strings.Join(lines, "\n")
}

func (m model) reducedBodyRows(mode layoutMode) (titleRows, middleRows, gapRows int) {
	if mode == layoutMid && m.height >= 24 {
		titleRows = 2
	}

	middleRows = m.reducedMiddleRows(mode)

	if mode == layoutMid && m.height >= titleRows+middleRows+canvasH+1 {
		gapRows = 1
	}
	return titleRows, middleRows, gapRows
}

func (m model) reducedMiddleRows(mode layoutMode) int {
	if m.height <= 1 {
		return 0
	}

	if m.loading {
		if mode == layoutSmall {
			return 1
		}
		if m.sudoPrompt && m.sudoErr != nil {
			return 3
		}
		return 2
	}

	if m.height <= 2 {
		return 1
	}
	if mode == layoutMid {
		return 7
	}
	if m.height >= 7 {
		return 5
	}
	return 2
}

func (m model) renderFullMenu() string {
	tabs := renderTabs(m.tab)

	// Drop descriptions on narrow terminals so rows do not overflow.
	showDesc := menuDescriptionsFit(canvasW)
	menu := m.renderMenuRows(showDesc)

	help := sDim.Render("←↑↓→") + sGray.Render("  move    ") +
		sDim.Render("⏎") + sGray.Render(" select    ") +
		sDim.Render("⌖") + sGray.Render("  click    ") +
		sDim.Render("ctrl+c") + sGray.Render(" exit")

	ctr := func(s string) string { return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s) }
	return strings.Join([]string{
		ctr(tabs),
		"",
		ctr(menu),
		"",
		"",
		ctr(help),
	}, "\n")
}

func (m model) renderMidMenu() string {
	tabs := renderTabs(m.tab)
	showDesc := menuDescriptionsFit(canvasW)
	menu := m.renderMenuRows(showDesc)

	help := sDim.Render("←↑↓→") + sGray.Render(" move   ") +
		sDim.Render("⏎") + sGray.Render(" select   ") +
		sDim.Render("ctrl+c") + sGray.Render(" exit")

	return strings.Join([]string{
		centerCanvas(tabs),
		"",
		centerCanvas(menu),
		"",
		centerCanvas(help),
	}, "\n")
}

func (m model) renderReducedMenu(mode layoutMode) string {
	active := sections[m.tab]
	rows := []string{centerCanvas(renderActiveTab(m.tab))}

	if m.height <= 2 {
		return strings.Join(rows, "\n")
	}

	if mode == layoutMid || m.height >= 7 {
		rows = append(rows, "")
		for i, it := range active.items {
			rows = append(rows, centerCanvas(renderMenuRow(it, i == m.cursor, mode)))
		}
		return strings.Join(rows, "\n")
	}

	selected := active.items[m.cursor]
	rows = append(rows, centerCanvas(renderMenuRow(selected, true, mode)))
	return strings.Join(rows, "\n")
}

func renderActiveTab(active int) string {
	name := sections[active].name
	return sDim.Render("< ") + sWhite.Render(name) + sDim.Render(" >")
}

func renderMenuRow(it item, selected bool, mode layoutMode) string {
	idStyle := sGray
	titleStyle := sMid
	if selected {
		idStyle = sRed
		titleStyle = sWhite
	}

	if mode == layoutSmall {
		return idStyle.Render(it.id) + " " + titleStyle.Render(it.title)
	}

	marker := sDim.Render("╎")
	if selected {
		marker = sRed.Render("▐")
	}
	return marker + "  " + idStyle.Render(it.id) + "  " + titleStyle.Render(it.title)
}

func (m model) renderMenuRows(showDesc bool) string {
	menuRowWidth := computeMenuRowWidth(showDesc)
	active := sections[m.tab]

	var rows []string
	for i, it := range active.items {
		selected := i == m.cursor
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
			idStyle.Render(it.id) + "  " +
			titleStyle.Render(it.title)
		if showDesc {
			line += "   " + descStyle.Render(it.desc)
		}
		line = lipgloss.PlaceHorizontal(menuRowWidth, lipgloss.Left, line)
		rows = append(rows, line)
	}
	return lipgloss.JoinVertical(lipgloss.Left, rows...)
}

func centerCanvas(s string) string {
	if canvasW < 1 {
		canvasW = 1
	}
	return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s)
}

// mainMouse routes left clicks on the main menu. Click on a tab chip → switch
// tabs; click on a menu item → select it; click on the already-selected item
// → activate (same as ⏎).
func (m model) mainMouse(msg tea.MouseClickMsg) (model, tea.Cmd) {
	if msg.Button != tea.MouseLeft {
		return m, nil
	}
	if layoutFor(m.width, m.height) != layoutFull {
		return m, nil
	}
	nItems := len(sections[m.tab].items)

	// body layout mirrors View(): icon + blank + title + tagline + blank + middle
	// middle: tabs + blank + menu(nItems) + blank + blank + help = 5+nItems rows
	bodyH := canvasH + 1 + 1 + 1 + 1 + (1 + 1 + nItems + 1 + 1 + 1)
	topY := (m.height - bodyH) / 2
	if topY < 0 {
		topY = 0
	}
	tabsY := topY + canvasH + 4 // icon + blank + title + tagline + blank
	menuStartY := tabsY + 2

	y := msg.Y

	// tab row — compute each tab's x range from the rendered string widths
	if y == tabsY {
		// tabs are centered as a single row: "[NAME]  [NAME]  ..."
		// each label is len(name)+2 (for the brackets), separated by "  " (2 spaces).
		total := 0
		for _, s := range sections {
			total += len(s.name) + 2
		}
		total += (len(sections) - 1) * 2
		leftColumnX := (m.width - canvasW) / 2
		if leftColumnX < 0 {
			leftColumnX = 0
		}
		startX := leftColumnX + (canvasW-total)/2
		if startX < 0 {
			startX = 0
		}
		cx := startX
		for i, s := range sections {
			w := len(s.name) + 2
			if msg.X >= cx && msg.X < cx+w {
				m.tab = i
				m.cursor = 0
				return m, nil
			}
			cx += w + 2
		}
		return m, nil
	}

	// menu rows
	for i := 0; i < nItems; i++ {
		if y == menuStartY+i {
			if m.cursor == i {
				return m.activateMenuItem()
			}
			m.cursor = i
			return m, nil
		}
	}
	return m, nil
}

// activateMenuItem mirrors the keyboard Enter branch for the main menu.
func (m model) activateMenuItem() (model, tea.Cmd) {
	if m.tab == 0 && m.cursor == 0 {
		return m.startRootAction(actionApply)
	}
	if m.tab == 0 && m.cursor == 1 {
		return m.startRootAction(actionUpdate)
	}
	if m.tab == 0 && m.cursor == 2 {
		return m.startRootAction(actionReset)
	}
	if m.tab == 0 && m.cursor == 3 {
		return m.startBuildAction()
	}
	return m, nil
}

type scriptDoneMsg struct {
	action actionMode
	script string
	err    error
}

type scriptStartedMsg struct {
	action actionMode
	script string
	cancel context.CancelFunc
	events <-chan scriptEvent
}

type scriptEventMsg struct {
	event scriptEvent
}

type scriptEvent struct {
	action   actionMode
	script   string
	line     string
	status   string
	progress float64
	done     bool
	err      error
}

var errScriptCanceled = errors.New("canceled")

type sudoCheckDoneMsg struct {
	action actionMode
	script string
	err    error
}

type sudoAuthDoneMsg struct {
	action actionMode
	script string
	err    error
}

func (m model) startRootAction(action actionMode) (model, tea.Cmd) {
	script, err := findRootScript(action)
	m.loading = true
	m.action = action
	m.loadStart = m.frame
	m.scriptRunning = false
	m.scriptDone = false
	m.scriptErr = nil
	m.scriptPath = script
	m.sudoChecking = true
	m.sudoPrompt = false
	m.sudoPassword = nil
	m.sudoErr = nil
	m.scriptCancel = nil
	m.scriptEvents = nil
	m.scriptStatus = "authorizing sudo"
	m.scriptProgress = 0
	m.scriptTarget = 0
	m.scriptLogLines = nil
	m.scriptArtifact = ""
	m.scriptRelease = ""
	m.scriptCanceling = false
	m.scriptCanceled = false
	m.logOverlay = false

	if err != nil {
		m.sudoChecking = false
		m.scriptDone = true
		m.scriptErr = err
		return m, nil
	}

	return m, checkSudoCachedCmd(action, script)
}

func (m model) startBuildAction() (model, tea.Cmd) {
	script, err := findBuildScript()
	m.loading = true
	m.action = actionBuild
	m.loadStart = m.frame
	m.scriptRunning = false
	m.scriptDone = false
	m.scriptErr = nil
	m.scriptPath = script
	m.sudoChecking = false
	m.sudoPrompt = false
	m.sudoPassword = nil
	m.sudoErr = nil
	m.scriptCancel = nil
	m.scriptEvents = nil
	m.scriptStatus = "starting ISO build"
	m.scriptProgress = 0
	m.scriptTarget = 0
	m.scriptLogLines = nil
	m.scriptArtifact = ""
	m.scriptRelease = ""
	m.scriptCanceling = false
	m.scriptCanceled = false
	m.logOverlay = false

	if err != nil {
		m.scriptDone = true
		m.scriptErr = err
		return m, nil
	}

	m.scriptRunning = true
	return m, runRootScriptCmd(actionBuild, script)
}

func (m model) startRootScriptRun(action actionMode, script string) (model, tea.Cmd) {
	m.loading = true
	m.action = action
	m.loadStart = m.frame
	m.scriptRunning = true
	m.scriptDone = false
	m.scriptErr = nil
	m.scriptPath = script
	m.sudoChecking = false
	m.sudoPrompt = false
	m.sudoPassword = nil
	m.sudoErr = nil
	m.scriptCancel = nil
	m.scriptEvents = nil
	m.scriptStatus = "starting " + strings.ToLower(rootActionName(action))
	m.scriptProgress = 0
	m.scriptTarget = 0
	m.scriptLogLines = nil
	m.scriptArtifact = ""
	m.scriptRelease = ""
	m.scriptCanceling = false
	m.scriptCanceled = false
	m.logOverlay = false
	return m, runRootScriptCmd(action, script)
}

func (m model) handleSudoKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "esc":
		m.sudoPassword = nil
		m.loading = false
		return m, nil
	case "enter":
		if len(m.sudoPassword) == 0 {
			m.sudoErr = fmt.Errorf("password required")
			return m, nil
		}
		password := append([]rune(nil), m.sudoPassword...)
		clearRunes(m.sudoPassword)
		m.sudoPassword = nil
		m.sudoPrompt = false
		m.sudoChecking = true
		m.sudoErr = nil
		return m, authorizeSudoCmd(m.action, m.scriptPath, password)
	case "backspace", "ctrl+h":
		if len(m.sudoPassword) > 0 {
			m.sudoPassword[len(m.sudoPassword)-1] = 0
			m.sudoPassword = m.sudoPassword[:len(m.sudoPassword)-1]
		}
	default:
		if text := msg.Key().Text; text != "" {
			m.sudoPassword = append(m.sudoPassword, []rune(text)...)
			m.sudoErr = nil
		}
	}
	return m, nil
}

func checkSudoCachedCmd(action actionMode, script string) tea.Cmd {
	return func() tea.Msg {
		err := exec.Command("sudo", "-n", "-v").Run()
		return sudoCheckDoneMsg{action: action, script: script, err: err}
	}
}

func authorizeSudoCmd(action actionMode, script string, password []rune) tea.Cmd {
	secret := runesToBytes(password)
	clearRunes(password)
	return func() tea.Msg {
		err := authorizeSudo(secret)
		clearBytes(secret)
		if err != nil {
			err = fmt.Errorf("sudo authorization failed")
		}
		return sudoAuthDoneMsg{action: action, script: script, err: err}
	}
}

func runRootScriptCmd(action actionMode, script string) tea.Cmd {
	ctx, cancel := context.WithCancel(context.Background())
	events := make(chan scriptEvent, 1024)
	go runRootScriptStream(ctx, action, script, events)

	return func() tea.Msg {
		return scriptStartedMsg{action: action, script: script, cancel: cancel, events: events}
	}
}

func waitScriptEventCmd(events <-chan scriptEvent) tea.Cmd {
	return func() tea.Msg {
		event, ok := <-events
		if !ok {
			return nil
		}
		return scriptEventMsg{event: event}
	}
}

func authorizeSudo(secret []byte) error {
	cmd := exec.Command("sudo", "-S", "-p", "", "-v")
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	if _, err := stdin.Write(secret); err != nil {
		_ = stdin.Close()
		_ = cmd.Wait()
		return err
	}
	if _, err := stdin.Write([]byte("\n")); err != nil {
		_ = stdin.Close()
		_ = cmd.Wait()
		return err
	}
	if err := stdin.Close(); err != nil {
		_ = cmd.Wait()
		return err
	}
	return cmd.Wait()
}

func runRootScript(action actionMode, script string) error {
	events := make(chan scriptEvent, 1024)
	go runRootScriptStream(context.Background(), action, script, events)

	var finalErr error
	for event := range events {
		if event.done {
			finalErr = event.err
		}
	}
	return finalErr
}

func runRootScriptStream(ctx context.Context, action actionMode, script string, events chan<- scriptEvent) {
	defer close(events)

	runnableScript, cleanupRunnableScript, err := snapshotRunnableScript(script)
	if err != nil {
		events <- scriptEvent{action: action, script: script, status: "could not snapshot script", progress: 0, done: true, err: err}
		return
	}
	defer cleanupRunnableScript()

	cmd := exec.CommandContext(ctx, "/bin/bash", runnableScript)
	cmd.Env = os.Environ()
	if strings.TrimSpace(os.Getenv("QVOS_TUI_BINARY")) == "" {
		if exe, err := currentExecutablePath(); err == nil {
			cmd.Env = append(cmd.Env, "QVOS_TUI_BINARY="+exe)
		}
	}
	if action == actionBuild {
		if qvosEnvEnabled("QVOS_BUILD_PREPARE_ONLY") {
			cmd.Args = append(cmd.Args, "--prepare-only")
		} else {
			cmd.Args = append(cmd.Args, "--allow-downloads")
		}
		cmd.Env = append(cmd.Env, "QVOS_ISO_PARENT_LOGGING=1")
		if strings.TrimSpace(os.Getenv("QVOS_ISO_RELEASE_DIR")) == "" {
			cmd.Env = append(cmd.Env, "QVOS_ISO_RELEASE_DIR="+defaultISOReleaseDir())
		}
	}
	cmd.Dir = filepath.Dir(script)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return os.ErrProcessDone
		}
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		if err == syscall.ESRCH {
			return os.ErrProcessDone
		}
		return err
	}
	cmd.WaitDelay = 30 * time.Second

	var logFile *os.File
	var lockFile *os.File
	if action == actionBuild {
		var err error
		logFile, lockFile, err = openBuildLog()
		if err != nil {
			events <- scriptEvent{action: action, script: script, status: "could not create build log", progress: 0, done: true, err: fmt.Errorf("could not create build log: %w", err)}
			return
		}
		defer logFile.Close()
		defer closeBuildLock(lockFile)
	} else {
		done := make(chan struct{})
		defer close(done)
		go keepSudoAlive(done)
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		events <- scriptEvent{action: action, script: script, status: "could not capture stdout", progress: 0, done: true, err: err}
		return
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		events <- scriptEvent{action: action, script: script, status: "could not capture stderr", progress: 0, done: true, err: err}
		return
	}

	if err := cmd.Start(); err != nil {
		events <- scriptEvent{action: action, script: script, status: "could not start script", progress: 0, done: true, err: err}
		return
	}

	outputDone := make(chan struct{}, 2)
	scan := func(r io.Reader) {
		defer func() { outputDone <- struct{}{} }()
		scanner := bufio.NewScanner(r)
		buf := make([]byte, 0, 64*1024)
		scanner.Buffer(buf, 1024*1024)
		for scanner.Scan() {
			line := scanner.Text()
			if logFile != nil {
				_, _ = fmt.Fprintln(logFile, line)
			}
			status, progress := scriptProgressFromLine(action, line)
			events <- scriptEvent{action: action, script: script, line: line, status: status, progress: progress}
		}
	}
	go scan(stdout)
	go scan(stderr)

	err = cmd.Wait()
	<-outputDone
	<-outputDone

	if ctx.Err() != nil {
		err = errScriptCanceled
	}
	status := rootActionCompleteStatus(action)
	if err != nil {
		status = shortError(err)
	}
	events <- scriptEvent{action: action, script: script, status: status, progress: 1, done: true, err: err}
}

func snapshotRunnableScript(script string) (string, func(), error) {
	info, err := os.Stat(script)
	if err != nil {
		return "", func() {}, err
	}
	if !info.Mode().IsRegular() {
		return script, func() {}, nil
	}

	data, err := os.ReadFile(script)
	if err != nil {
		return "", func() {}, err
	}

	tmp, err := os.CreateTemp(filepath.Dir(script), ".qvos-run-*.sh")
	if err != nil {
		return "", func() {}, err
	}
	tmpPath := tmp.Name()
	cleanup := func() { _ = os.Remove(tmpPath) }

	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		cleanup()
		return "", func() {}, err
	}
	if err := tmp.Chmod(0o700); err != nil {
		_ = tmp.Close()
		cleanup()
		return "", func() {}, err
	}
	if err := tmp.Close(); err != nil {
		cleanup()
		return "", func() {}, err
	}

	return tmpPath, cleanup, nil
}

func openBuildLog() (*os.File, *os.File, error) {
	logPath := qvosBuildLogPath()
	if err := os.MkdirAll(filepath.Dir(logPath), 0o755); err != nil {
		return nil, nil, err
	}

	lockFile, err := os.OpenFile(qvosBuildLockPath(), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, nil, err
	}

	if err := syscall.Flock(int(lockFile.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = lockFile.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) || errors.Is(err, syscall.EAGAIN) {
			return nil, nil, fmt.Errorf("another qvOS ISO build is already running")
		}
		return nil, nil, err
	}

	logFile, err := os.Create(logPath)
	if err != nil {
		closeBuildLock(lockFile)
		return nil, nil, err
	}

	return logFile, lockFile, nil
}

func closeBuildLock(lockFile *os.File) {
	if lockFile == nil {
		return
	}
	_ = syscall.Flock(int(lockFile.Fd()), syscall.LOCK_UN)
	_ = lockFile.Close()
}

func scriptProgressFromLine(action actionMode, line string) (string, float64) {
	clean := sanitizeLogLine(line)
	if clean == "" {
		return "", -1
	}

	switch action {
	case actionBuild:
		return buildProgressFromLine(clean)
	case actionApply:
		return domainProgressFromLine(clean, "qvOS install:", installDomainOrder)
	case actionReset:
		return domainProgressFromLine(clean, "qvOS reset:", revertDomainOrder)
	case actionUpdate:
		return domainProgressFromLine(clean, "qvOS update:", installDomainOrder)
	default:
		return clean, -1
	}
}

var buildStages = []struct {
	token    string
	status   string
	progress float64
}{
	{"qvOS ISO preflight:", "checking build host", 0.04},
	{"cleaning old stage", "cleaning old stage", 0.08},
	{"stage ready", "preparing clean stage", 0.10},
	{"fresh-cloning qvOS source ", "cloning qvOS source", 0.18},
	{"fresh-cloning ISO builder source ", "cloning ISO builder", 0.28},
	{"validating qvOS payload", "validating qvOS payload", 0.38},
	{"staging qvOS TUI installer", "staging TUI binary", 0.52},
	{"patching staged ISO installer", "patching ISO installer", 0.58},
	{"starting ISO builder", "starting ISO builder", 0.64},
	{"qvOS ISO progress: preparing build cache", "preparing build cache", 0.66},
	{"qvOS ISO progress: starting build container", "starting build container", 0.67},
	{"qvOS ISO progress: preparing build tools", "preparing build tools", 0.68},
	{"qvOS ISO progress: staging live filesystem", "staging live filesystem", 0.70},
	{"qvOS ISO progress: staging qvOS system", "staging qvOS system", 0.72},
	{"qvOS ISO progress: caching node runtime", "caching node runtime", 0.74},
	{"qvOS ISO progress: resolving package set", "resolving package set", 0.76},
	{"qvOS ISO progress: indexing package mirror", "indexing package mirror", 0.86},
	{"qvOS ISO progress: creating ISO image", "creating ISO image", 0.90},
	{"[mkarchiso] INFO: Installing packages", "installing live packages", 0.905},
	{"[mkarchiso] INFO: Preparing kernel and initramfs", "preparing live kernel", 0.915},
	{"[mkarchiso] INFO: Setting up SYSLINUX", "staging BIOS boot", 0.925},
	{"[mkarchiso] INFO: Setting up GRUB", "staging UEFI boot", 0.930},
	{"[mkarchiso] INFO: Creating SquashFS image", "compressing live system", 0.935},
	{"[mkarchiso] INFO: Creating ISO image", "writing ISO image", 0.945},
	{"qvOS ISO progress: finalizing ISO image", "finalizing ISO image", 0.950},
	{"qvOS ISO progress: naming ISO artifact", "naming ISO artifact", 0.955},
	{"copying ISO artifact", "copying ISO artifact", 0.965},
	{"cleaning stage", "cleaning build stage", 0.985},
	{"qvOS ISO build complete", "ISO build complete", 1.00},
}

func buildProgressFromLine(line string) (string, float64) {
	if status, progress, ok := packageDownloadProgressFromLine(line); ok {
		return status, progress
	}
	if status, progress, ok := packageIndexProgressFromLine(line); ok {
		return status, progress
	}
	for _, stage := range buildStages {
		if strings.Contains(line, stage.token) {
			return stage.status, stage.progress
		}
	}
	return "", -1
}

func buildArtifactFromLine(line string) (string, bool) {
	const prefix = "qvOS ISO artifact:"

	if !strings.HasPrefix(line, prefix) {
		return "", false
	}
	artifact := strings.TrimSpace(strings.TrimPrefix(line, prefix))
	return artifact, artifact != ""
}

func buildReleaseFromLine(line string) (string, bool) {
	const prefix = "qvOS ISO release dir:"

	if !strings.HasPrefix(line, prefix) {
		return "", false
	}
	release := strings.TrimSpace(strings.TrimPrefix(line, prefix))
	return release, release != ""
}

func packageDownloadProgressFromLine(line string) (string, float64, bool) {
	return countedBuildProgressFromLine(line, "qvOS ISO progress: downloading ISO packages ", "downloading ISO packages", 0.78, 0.84)
}

func packageIndexProgressFromLine(line string) (string, float64, bool) {
	return countedBuildProgressFromLine(line, "qvOS ISO progress: indexing package mirror ", "indexing package mirror", 0.86, 0.89)
}

func countedBuildProgressFromLine(line, prefix, status string, start, end float64) (string, float64, bool) {
	if !strings.HasPrefix(line, prefix) {
		return "", -1, false
	}

	rest := strings.TrimSpace(strings.TrimPrefix(line, prefix))
	fields := strings.Fields(rest)
	if len(fields) < 2 {
		return status, start, true
	}

	downloaded, downloadedErr := strconv.Atoi(fields[0])
	total, totalErr := strconv.Atoi(fields[1])
	if downloadedErr != nil || totalErr != nil || total <= 0 {
		return status, start, true
	}

	ratio := float64(downloaded) / float64(total)
	if ratio < 0 {
		ratio = 0
	}
	if ratio > 1 {
		ratio = 1
	}
	return status, start + ratio*(end-start), true
}

var installDomainOrder = []string{
	"Runtime", "Defaults", "Icons", "Hyprland", "Theme", "Branding", "SDDM", "Fastfetch", "Screensaver", "GTK", "Waybar", "Tmux",
}

var revertDomainOrder = []string{
	"Tmux", "Waybar", "GTK", "Screensaver", "Fastfetch", "SDDM", "Branding", "Theme", "Hyprland", "Icons", "Defaults", "Retired domains", "Runtime",
}

func domainProgressFromLine(line string, prefix string, order []string) (string, float64) {
	if !strings.HasPrefix(line, prefix) {
		return line, -1
	}
	name := strings.TrimSpace(strings.TrimPrefix(line, prefix))
	if name == "" {
		return line, -1
	}
	for i, step := range order {
		if name == step || strings.HasPrefix(name, step+" ") {
			return strings.ToLower(name), float64(i+1) / float64(len(order)+1)
		}
	}
	return strings.ToLower(name), -1
}

const maxScriptLogLines = 240

func appendLimited(lines []string, line string, limit int) []string {
	if line == "" {
		return lines
	}
	lines = append(lines, line)
	if len(lines) > limit {
		copy(lines, lines[len(lines)-limit:])
		lines = lines[:limit]
	}
	return lines
}

func sanitizeLogLine(line string) string {
	line = strings.ReplaceAll(line, `\033[0m`, "")
	line = strings.ReplaceAll(line, `\e[0m`, "")
	line = strings.TrimSpace(stripANSI(line))
	if len(line) > 180 {
		line = line[:177] + "..."
	}
	return line
}

func stripANSI(s string) string {
	var out strings.Builder
	out.Grow(len(s))
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if ch != 0x1b {
			out.WriteByte(ch)
			continue
		}

		if i+1 >= len(s) {
			continue
		}
		i++
		switch s[i] {
		case '[':
			for i+1 < len(s) {
				i++
				if s[i] >= 0x40 && s[i] <= 0x7e {
					break
				}
			}
		case ']':
			for i+1 < len(s) {
				i++
				if s[i] == 0x07 {
					break
				}
				if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '\\' {
					i++
					break
				}
			}
		default:
			continue
		}
	}
	return out.String()
}

func defaultISOReleaseDir() string {
	home := strings.TrimSpace(os.Getenv("HOME"))
	if home == "" {
		if userHome, err := os.UserHomeDir(); err == nil {
			home = userHome
		}
	}
	if home == "" {
		return filepath.Join(os.TempDir(), "qvOS-Release")
	}
	return filepath.Join(home, "qvOS-Release")
}

func currentExecutablePath() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	if realExe, err := filepath.EvalSymlinks(exe); err == nil {
		exe = realExe
	}
	return filepath.Abs(exe)
}

func clearRunes(value []rune) {
	for i := range value {
		value[i] = 0
	}
}

func runesToBytes(value []rune) []byte {
	var out []byte
	for _, r := range value {
		out = utf8.AppendRune(out, r)
	}
	return out
}

func clearBytes(value []byte) {
	for i := range value {
		value[i] = 0
	}
}

func keepSudoAlive(done <-chan struct{}) {
	ticker := time.NewTicker(45 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-done:
			return
		case <-ticker.C:
			_ = exec.Command("sudo", "-n", "-v").Run()
		}
	}
}

// -- action progress --

const buildDurationSeconds = 18
const buildFrames = framesPerSecond * framesPerTick * buildDurationSeconds

const progressBarWidth = 34

func renderProgressBar(phase loadPhase, progress float64, elapsed int) string {
	_ = elapsed

	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}

	full := int(math.Round(progress * float64(progressBarWidth)))
	if full > progressBarWidth {
		full = progressBarWidth
	}

	var sb strings.Builder
	for i := 0; i < full; i++ {
		sb.WriteString(sDeepRed.Render("━"))
	}
	if phase == loadRun && full > 0 && full < progressBarWidth {
		sb.WriteString(sRed.Render("━"))
		full++
	}
	for i := full; i < progressBarWidth; i++ {
		sb.WriteString(sDim.Render("─"))
	}
	return sb.String()
}

func renderReducedProgress(label string, phase loadPhase, progress float64, mode layoutMode) string {
	percent := fmt.Sprintf("%d%%", int(progress*100))
	percentStyle := sDeepRed
	if phase == loadErr {
		percent = "ERR"
		percentStyle = sRed
	}
	if phase == loadOK {
		percent = "100%"
		percentStyle = sWhite
	}

	if mode == layoutSmall {
		return centerCanvas(percentStyle.Render(percent))
	}

	return strings.Join([]string{
		centerCanvas(sWhite.Render(label)),
		centerCanvas(percentStyle.Render(percent)),
	}, "\n")
}

func (m model) renderRootAction() string {
	return m.renderRootActionFor(layoutFull)
}

func (m model) renderRootActionFor(mode layoutMode) string {
	if m.sudoPrompt {
		return m.renderSudoPromptFor(mode)
	}
	progress := m.renderRootProgressFor(mode)
	if !m.logOverlay {
		return progress
	}
	return strings.Join([]string{
		progress,
		"",
		centerCanvas(m.renderRootLogOverlayFor(mode)),
	}, "\n")
}

func (m model) renderSudoPrompt() string {
	return m.renderSudoPromptFor(layoutFull)
}

func (m model) renderSudoPromptFor(mode layoutMode) string {
	title := sWhite.Render(rootActionName(m.action) + " AUTH")
	status := sGray.Render("sudo password required")
	if m.sudoErr != nil {
		status = sRed.Render(shortError(m.sudoErr))
	}
	field := renderPasswordField(m.sudoPassword, mode)

	if mode == layoutSmall {
		return strings.Join([]string{
			centerCanvas(title),
			centerCanvas(field),
		}, "\n")
	}

	if mode == layoutMid {
		lines := []string{centerCanvas(title)}
		if m.sudoErr != nil {
			lines = append(lines, centerCanvas(status))
		}
		lines = append(lines, centerCanvas(field))
		return strings.Join(lines, "\n")
	}

	hint := sDim.Render("⏎") + sGray.Render("  authorize    ") +
		sDim.Render("esc") + sGray.Render("  cancel    ") +
		sDim.Render("ctrl+c") + sGray.Render("  exit")

	ctr := func(s string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s)
	}

	return strings.Join([]string{
		ctr(title),
		"",
		ctr(status),
		"",
		ctr(field),
		"",
		"",
		ctr(hint),
	}, "\n")
}

func renderPasswordField(password []rune, mode layoutMode) string {
	fieldWidth := 28
	if mode == layoutMid {
		fieldWidth = 18
	}
	if mode == layoutSmall {
		fieldWidth = 10
	}

	count := len(password)
	if count > fieldWidth {
		count = fieldWidth
	}
	leftPad := (fieldWidth - count) / 2
	rightPad := fieldWidth - count - leftPad
	filled := strings.Repeat("●", count)

	return sDeepRed.Render("▐ ") +
		sDim.Render(strings.Repeat("─", leftPad)) +
		sDeepRed.Render(filled) +
		sDim.Render(strings.Repeat("─", rightPad)) +
		sDeepRed.Render(" ▌")
}

func (m model) renderRootProgress() string {
	return m.renderRootProgressFor(layoutFull)
}

func (m model) renderRootProgressFor(mode layoutMode) string {
	phase := m.loadPhase()
	progress := m.loadProgress()
	elapsed := m.frame - m.loadStart
	if phase == loadOK && m.action == actionBuild && !m.scriptCanceled {
		return m.renderBuildFinishedFor(mode)
	}
	if mode != layoutFull {
		return renderReducedProgress(rootActionName(m.action), phase, progress, mode)
	}

	bar := renderProgressBar(phase, progress, elapsed)
	percentRaw := fmt.Sprintf("%3d%%", int(progress*100))

	var op, stageRaw, hint string
	switch phase {
	case loadOK:
		if m.scriptCanceled {
			op = sWhite.Render("CANCELED")
			stageRaw = "cleanup complete - good to go"
		} else {
			op = sWhite.Render(rootActionPastTense(m.action))
			stageRaw = rootActionCompleteStatus(m.action)
		}
		hint = sDim.Render("⏎") + sGray.Render("  return    ") +
			sDim.Render("v") + sGray.Render("  logs")
	case loadErr:
		op = sRed.Render(rootActionName(m.action) + " FAILED")
		stageRaw = shortError(m.scriptErr)
		hint = sDim.Render("r") + sGray.Render("  retry    ") +
			sDim.Render("v") + sGray.Render("  logs    ") +
			sDim.Render("esc") + sGray.Render("  return")
	default:
		op = sWhite.Render(rootActionActiveTitle(m.action))
		if m.sudoChecking {
			stageRaw = "authorizing sudo"
		} else if m.scriptCanceling {
			stageRaw = "cleaning build stage"
		} else if m.scriptStatus != "" {
			stageRaw = m.scriptStatus
		} else {
			stageRaw = rootActionRunningStatus(m.action)
		}
		hint = sDim.Render("ctrl+c") + sGray.Render("  cancel    ") +
			sDim.Render("v") + sGray.Render("  logs")
	}

	if stageRaw == "" {
		stageRaw = "script failed"
	}
	stageRaw = trimDisplay(stageRaw, progressBarWidth-len(percentRaw)-1)

	gap := progressBarWidth - len(stageRaw) - len(percentRaw)
	if gap < 1 {
		gap = 1
	}
	stageStyle := sGray
	if phase == loadErr {
		stageStyle = sRed
	}
	statusLine := stageStyle.Render(stageRaw) + strings.Repeat(" ", gap) + sMid.Render(percentRaw)

	ctr := func(s string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s)
	}

	return strings.Join([]string{
		ctr(op),
		"",
		ctr(statusLine),
		"",
		ctr(bar),
		"",
		"",
		ctr(hint),
	}, "\n")
}

func (m model) renderBuildFinishedFor(mode layoutMode) string {
	releaseName := "qvOS ISO"
	if m.scriptArtifact != "" {
		releaseName = filepath.Base(m.scriptArtifact)
	}

	releaseDir := m.scriptRelease
	if releaseDir == "" && m.scriptArtifact != "" {
		releaseDir = filepath.Dir(m.scriptArtifact)
	}
	if releaseDir == "" {
		releaseDir = defaultISOReleaseDir()
	}

	if mode == layoutSmall {
		return centerCanvas(sWhite.Render("BUILD FINISHED"))
	}
	if mode == layoutMid {
		return strings.Join([]string{
			centerCanvas(sWhite.Render("BUILD FINISHED")),
			centerCanvas(sGray.Render(trimDisplay(releaseName, canvasW))),
		}, "\n")
	}

	labelWidth := 8
	nameWidth := max(12, canvasW-labelWidth-2)
	dirWidth := max(12, canvasW-labelWidth-2)
	nameLine := sGray.Render("release ") + sWhite.Render(trimDisplay(releaseName, nameWidth))
	dirLine := sGray.Render("folder  ") + sMid.Render(trimDisplay(releaseDir, dirWidth))
	hint := sDim.Render("⏎") + sGray.Render("  return    ") +
		sDim.Render("v") + sGray.Render("  logs")

	ctr := func(s string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s)
	}

	return strings.Join([]string{
		ctr(sWhite.Render("BUILD FINISHED")),
		"",
		ctr(nameLine),
		ctr(dirLine),
		"",
		ctr(hint),
	}, "\n")
}

func (m model) renderRootLogOverlayFor(mode layoutMode) string {
	width := canvasW
	height := 10
	if mode == layoutMid {
		width = canvasW
		height = 7
	}
	if mode == layoutSmall {
		width = canvasW
		height = 3
	}
	if width < 20 {
		width = 20
	}
	if width > 74 {
		width = 74
	}

	contentWidth := width - 4
	lines := m.scriptLogLines
	if len(lines) == 0 {
		lines = []string{"waiting for logs"}
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
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(deepRed)).
		Foreground(lipgloss.Color(mid)).
		Padding(0, 1).
		Render(strings.Join(body, "\n"))
}

func rootActionName(action actionMode) string {
	switch action {
	case actionReset:
		return "RESET"
	case actionApply:
		return "APPLY"
	case actionUpdate:
		return "UPDATE"
	default:
		return "BUILD"
	}
}

func rootActionPastTense(action actionMode) string {
	switch action {
	case actionBuild:
		return "BUILT"
	case actionReset:
		return "RESET"
	case actionApply:
		return "APPLIED"
	case actionUpdate:
		return "UPDATED"
	default:
		return "READY"
	}
}

func rootActionActiveTitle(action actionMode) string {
	switch action {
	case actionBuild:
		return "BUILDING"
	case actionReset:
		return "RESETTING"
	case actionApply:
		return "APPLYING"
	case actionUpdate:
		return "UPDATING"
	default:
		return "RUNNING"
	}
}

func rootActionRunningStatus(action actionMode) string {
	switch action {
	case actionBuild:
		return "ISO build running in background"
	case actionReset:
		return "reset running in background"
	case actionApply:
		return "installer running in background"
	case actionUpdate:
		return "update running in background"
	default:
		return "script running in background"
	}
}

func rootActionCompleteStatus(action actionMode) string {
	switch action {
	case actionBuild:
		return "ISO build complete"
	case actionReset:
		return "fresh reset complete"
	case actionApply:
		return "install complete"
	case actionUpdate:
		return "update complete"
	default:
		return "complete"
	}
}

func renderTabs(active int) string {
	var parts []string
	for i, s := range sections {
		if i == active {
			parts = append(parts, sRed.Render("[")+sWhite.Render(s.name)+sRed.Render("]"))
		} else {
			parts = append(parts, sDim.Render(" ")+sGray.Render(s.name)+sDim.Render(" "))
		}
	}
	return strings.Join(parts, sDim.Render("  "))
}

// -- 3D rendering primitives --

// canvas sizing — the 3D shape scales to fit the terminal.
// `canvasW`/`canvasH` are mutated each frame by fitCanvas() in View().
var (
	canvasW = 64
	canvasH = 32
)

const (
	maxCanvasW = 64
	maxCanvasH = 32
	minCanvasW = 24

	fullCanvasReserveRows = 12
	iconCanvasScale       = 0.82
	smallBodyMaxW         = 32
)

// fitCanvas returns a canvas size that fits inside the given terminal while
// respecting the min/max and the 2:1 horizontal:vertical cell aspect. Full and
// mid use the same vertical reserve so the icon shrinks continuously across the
// layout boundary instead of jumping to a larger canvas.
func fitCanvas(termW, termH int) (int, int) {
	return fitIconCanvasReserved(termW, termH, minCanvasW, fullCanvasReserveRows)
}

func fitMidCanvas(termW, termH int) (int, int) {
	return fitIconCanvasReserved(termW, termH, 1, fullCanvasReserveRows)
}

func fitIconCanvasReserved(termW, termH int, minW int, reserveRows int) (int, int) {
	availW := termW - 4
	if availW < 1 {
		availW = 1
	}
	if reserveRows < 0 {
		reserveRows = 0
	}
	availH := termH - reserveRows
	if availH < 1 {
		availH = 1
	}
	if minW < 1 {
		minW = 1
	}

	w := maxCanvasW
	if w > availW {
		w = availW
	}
	if w > availH*2 {
		w = availH * 2
	}

	w = int(math.Round(float64(w) * iconCanvasScale))
	if w < minW {
		w = minW
	}
	if w > maxCanvasW {
		w = maxCanvasW
	}
	if w > availW {
		w = availW
	}
	if w > availH*2 {
		w = availH * 2
	}

	h := w / 2
	if h < 1 {
		h = 1
	}
	if h > maxCanvasH {
		h = maxCanvasH
	}
	if h > availH {
		h = availH
	}
	return w, h
}

func fitIconCanvas(termW, termH int, minW int) (int, int) {
	return fitIconCanvasReserved(termW, termH, minW, fullCanvasReserveRows)
}

func fitSmallBody(termW int) int {
	if termW < 1 {
		return 1
	}
	if termW < smallBodyMaxW {
		return termW
	}
	return smallBodyMaxW
}

var ramp = []rune(" .,:;-+*oO#%@")

type cell struct {
	ch    rune
	style lipgloss.Style
}

// scene holds working state for rendering one 3D shape: char grid, per-pixel
// z-buffer, rotation trig, normalized light direction, projection scale, and
// Phong specular exponent.
type scene struct {
	grid       []cell
	zbuf       []float64
	cY, sY     float64
	cX, sX     float64
	lx, ly, lz float64
	halfW      float64
	halfH      float64
	scale      float64
	shn        float64
}

// sceneCfg configures a new scene. `fit` is the world-space radius that should
// map to the horizontal canvas edge — smaller `fit` makes the object bigger.
// Light direction is provided un-normalized and normalized internally.
type sceneCfg struct {
	aY, aX     float64
	fit        float64
	shn        float64
	lx, ly, lz float64
}

func newScene(cfg sceneCfg) *scene {
	cY, sY := math.Cos(cfg.aY), math.Sin(cfg.aY)
	cX, sX := math.Cos(cfg.aX), math.Sin(cfg.aX)
	ln := 1.0 / math.Sqrt(cfg.lx*cfg.lx+cfg.ly*cfg.ly+cfg.lz*cfg.lz)

	halfW := float64(canvasW-1) / 2
	halfH := float64(canvasH-1) / 2

	zbuf := make([]float64, canvasW*canvasH)
	negInf := math.Inf(-1)
	for i := range zbuf {
		zbuf[i] = negInf
	}

	return &scene{
		grid:  make([]cell, canvasW*canvasH),
		zbuf:  zbuf,
		cY:    cY,
		sY:    sY,
		cX:    cX,
		sX:    sX,
		lx:    cfg.lx * ln,
		ly:    cfg.ly * ln,
		lz:    cfg.lz * ln,
		halfW: halfW,
		halfH: halfH,
		scale: halfW / cfg.fit,
		shn:   cfg.shn,
	}
}

// project rotates a world point+normal (Y then X), orthographically projects
// to screen space, runs a z-buffer test, and returns grid index + rotated
// normal. ok=false if off-canvas or occluded.
func (sc *scene) project(wx, wy, wz, nx, ny, nz float64) (idx int, nrx, nry, nrz float64, ok bool) {
	x1 := wx*sc.cY + wz*sc.sY
	z1 := -wx*sc.sY + wz*sc.cY
	y1 := wy
	nx1 := nx*sc.cY + nz*sc.sY
	nz1 := -nx*sc.sY + nz*sc.cY
	ny1 := ny

	x2 := x1
	y2 := y1*sc.cX - z1*sc.sX
	z2 := y1*sc.sX + z1*sc.cX
	nrx = nx1
	nry = ny1*sc.cX - nz1*sc.sX
	nrz = ny1*sc.sX + nz1*sc.cX

	sxf := x2*sc.scale + sc.halfW
	syf := -y2*sc.scale*0.5 + sc.halfH
	sxi := int(sxf + 0.5)
	syi := int(syf + 0.5)
	if sxi < 0 || sxi >= canvasW || syi < 0 || syi >= canvasH {
		return 0, 0, 0, 0, false
	}
	idx = syi*canvasW + sxi
	if z2 <= sc.zbuf[idx] {
		return idx, nrx, nry, nrz, false
	}
	sc.zbuf[idx] = z2
	return idx, nrx, nry, nrz, true
}

// phongGray picks a char + grayscale style for a rotated normal via Lambertian
// diffuse + Phong specular. View direction is assumed to be (0,0,1).
func (sc *scene) phongGray(nrx, nry, nrz float64) (rune, lipgloss.Style) {
	NdL := nrx*sc.lx + nry*sc.ly + nrz*sc.lz
	if NdL < 0 {
		NdL = 0
	}
	spec := 2*NdL*nrz - sc.lz
	if spec < 0 {
		spec = 0
	}
	spec = math.Pow(spec, sc.shn)

	brightness := NdL*0.78 + spec*0.50
	if brightness > 1 {
		brightness = 1
	}

	ri := int(brightness * float64(len(ramp)-1))
	if ri < 0 {
		ri = 0
	}
	if ri >= len(ramp) {
		ri = len(ramp) - 1
	}
	ch := ramp[ri]

	var style lipgloss.Style
	switch {
	case brightness > 0.93:
		style = sWhite
	case brightness > 0.70:
		style = sBright
	case brightness > 0.48:
		style = sMid
	case brightness > 0.26:
		style = sGray
	default:
		style = sDim
	}
	return ch, style
}

// plotGray = project → phongGray → commit for one world point+normal.
func (sc *scene) plotGray(wx, wy, wz, nx, ny, nz float64) {
	idx, nrx, nry, nrz, ok := sc.project(wx, wy, wz, nx, ny, nz)
	if !ok {
		return
	}
	ch, style := sc.phongGray(nrx, nry, nrz)
	sc.grid[idx] = cell{ch: ch, style: style}
}

// String renders the grid with ANSI escapes per styled cell.
func (sc *scene) String() string {
	var sb strings.Builder
	sb.Grow(canvasH * (canvasW + 1))
	for y := 0; y < canvasH; y++ {
		for x := 0; x < canvasW; x++ {
			c := sc.grid[y*canvasW+x]
			if c.ch == 0 || c.ch == ' ' {
				sb.WriteRune(' ')
			} else {
				sb.WriteString(c.style.Render(string(c.ch)))
			}
		}
		if y < canvasH-1 {
			sb.WriteRune('\n')
		}
	}
	return sb.String()
}

// -- INSTALL: bloom — animated displaced sphere --

const (
	bloomUN  = 240
	bloomVN  = 72
	bloomShn = 18.0
)

func renderBloom(frame int) string {
	t := float64(frame) * 0.018
	sc := newScene(sceneCfg{
		aY:  float64(frame) * 0.011,
		aX:  float64(frame) * 0.005,
		fit: 1.34,
		shn: bloomShn,
		lx:  -0.45, ly: -0.55, lz: 0.71,
	})

	pulseRaw := math.Sin(t * 2.4)
	pulse := 0.35 + 0.65*pulseRaw*pulseRaw

	for ui := 0; ui < bloomUN; ui++ {
		theta := float64(ui) / float64(bloomUN) * 2 * math.Pi
		cth, sth := math.Cos(theta), math.Sin(theta)

		for vi := 0; vi < bloomVN; vi++ {
			phi := float64(vi)/float64(bloomVN-1)*math.Pi - math.Pi/2
			cph, sph := math.Cos(phi), math.Sin(phi)

			// Three traveling surface waves that beat and never quite repeat.
			a1 := 3*theta + 2*phi + t*1.5
			s1, c1 := math.Sin(a1), math.Cos(a1)
			a2 := 5*theta + phi + t*0.9
			s2, c2 := math.Sin(a2), math.Cos(a2)
			a3 := theta + 4*phi + t*1.2
			s3, c3 := math.Sin(a3), math.Cos(a3)

			disp := pulse * (0.15*s1 + 0.10*c2 + 0.07*s3)
			r := 1 + disp

			drDtheta := pulse * (0.45*c1 - 0.50*s2 + 0.07*c3)
			drDphi := pulse * (0.30*c1 - 0.10*s2 + 0.28*c3)

			wx := r * cph * cth
			wy := r * cph * sth
			wz := r * sph

			dxDt := cph * (drDtheta*cth - r*sth)
			dyDt := cph * (drDtheta*sth + r*cth)
			dzDt := drDtheta * sph
			dxDp := cth * (drDphi*cph - r*sph)
			dyDp := sth * (drDphi*cph - r*sph)
			dzDp := drDphi*sph + r*cph

			nx := dyDt*dzDp - dzDt*dyDp
			ny := dzDt*dxDp - dxDt*dzDp
			nz := dxDt*dyDp - dyDt*dxDp
			nlen := math.Sqrt(nx*nx + ny*ny + nz*nz)
			if nlen < 1e-9 {
				continue
			}
			nx /= nlen
			ny /= nlen
			nz /= nlen

			idx, nrx, nry, nrz, ok := sc.project(wx, wy, wz, nx, ny, nz)
			if !ok {
				continue
			}

			// Custom shading: Lambertian + spec + heat (bulges) + thin (valleys).
			NdL := nrx*sc.lx + nry*sc.ly + nrz*sc.lz
			if NdL < 0 {
				NdL = 0
			}
			spec := 2*NdL*nrz - sc.lz
			if spec < 0 {
				spec = 0
			}
			spec = math.Pow(spec, sc.shn)

			var heat, thin float64
			if disp > 0 {
				heat = disp / 0.28
				if heat > 1 {
					heat = 1
				}
			} else if disp < 0 {
				thin = -disp / 0.28
				if thin > 1 {
					thin = 1
				}
			}

			brightness := NdL*0.72 + spec*0.45 + heat*0.22 + thin*0.15
			if brightness > 1 {
				brightness = 1
			}

			ri := int(brightness * float64(len(ramp)-1))
			if ri < 0 {
				ri = 0
			}
			if ri >= len(ramp) {
				ri = len(ramp) - 1
			}
			ch := ramp[ri]

			var style lipgloss.Style
			switch {
			case heat > 0.70:
				style = sHot
			case heat > 0.40:
				style = sRed
			case thin > 0.55:
				style = sRed
			case thin > 0.25:
				style = sDeepRed
			case brightness > 0.93:
				style = sWhite
			case brightness > 0.70:
				style = sBright
			case brightness > 0.48:
				style = sMid
			case brightness > 0.26:
				style = sGray
			default:
				style = sDim
			}
			sc.grid[idx] = cell{ch: ch, style: style}
		}
	}
	return sc.String()
}

// -- ABOUT: torus --

const (
	torusR   = 1.00
	torusRr  = 0.32
	torusUN  = 256
	torusVN  = 72
	torusShn = 22.0
)

func renderTorus(frame int) string {
	sc := newScene(sceneCfg{
		aY:  float64(frame) * 0.010,
		aX:  float64(frame) * 0.013,
		fit: torusR + torusRr,
		shn: torusShn,
		lx:  0.50, ly: -0.55, lz: 0.67,
	})

	for ui := 0; ui < torusUN; ui++ {
		u := float64(ui) / float64(torusUN) * 2 * math.Pi
		cu, su := math.Cos(u), math.Sin(u)
		for vi := 0; vi < torusVN; vi++ {
			v := float64(vi) / float64(torusVN) * 2 * math.Pi
			cv, sv := math.Cos(v), math.Sin(v)

			sc.plotGray(
				(torusR+torusRr*cv)*cu,
				torusRr*sv,
				(torusR+torusRr*cv)*su,
				cv*cu, sv, cv*su,
			)
		}
	}
	return sc.String()
}

// -- SYSTEM: trefoil knot tubular surface --

const (
	knotCurveN = 520
	knotRingN  = 34
	knotR      = 0.42
	knotTube   = 0.36
	knotShn    = 18.0
)

func knotPos(t float64) (x, y, z float64) {
	r := 2 + math.Cos(3*t)
	return knotR * r * math.Cos(2*t),
		knotR * r * math.Sin(2*t),
		knotR * math.Sin(3*t)
}

func renderKnot(frame int) string {
	sc := newScene(sceneCfg{
		aY:  float64(frame) * 0.011,
		aX:  float64(frame) * 0.008,
		fit: 1.65,
		shn: knotShn,
		lx:  -0.50, ly: -0.48, lz: 0.72,
	})

	const dt = 0.0015
	const upX, upY, upZ = 0.0, 1.0, 0.0

	for ci := 0; ci < knotCurveN; ci++ {
		t := float64(ci) / float64(knotCurveN) * 2 * math.Pi
		px, py, pz := knotPos(t)
		qx, qy, qz := knotPos(t + dt)

		tx := qx - px
		ty := qy - py
		tz := qz - pz
		tn := 1.0 / math.Sqrt(tx*tx+ty*ty+tz*tz)
		tx *= tn
		ty *= tn
		tz *= tn

		// Up-vector-projected frame: N and B orthogonal to T.
		dotUT := upX*tx + upY*ty + upZ*tz
		fnx := upX - dotUT*tx
		fny := upY - dotUT*ty
		fnz := upZ - dotUT*tz
		fn := 1.0 / math.Sqrt(fnx*fnx+fny*fny+fnz*fnz)
		fnx *= fn
		fny *= fn
		fnz *= fn

		fbx := ty*fnz - tz*fny
		fby := tz*fnx - tx*fnz
		fbz := tx*fny - ty*fnx

		for ri := 0; ri < knotRingN; ri++ {
			theta := float64(ri) / float64(knotRingN) * 2 * math.Pi
			ct, st := math.Cos(theta), math.Sin(theta)

			nx := ct*fnx + st*fbx
			ny := ct*fny + st*fby
			nz := ct*fnz + st*fbz

			sc.plotGray(
				px+knotTube*nx,
				py+knotTube*ny,
				pz+knotTube*nz,
				nx, ny, nz,
			)
		}
	}
	return sc.String()
}

// -- TWEAK: Hopf link (two interlocked rings) --

const (
	hopfUN     = 200
	hopfVN     = 52
	hopfR      = 0.60
	hopfRr     = 0.25
	hopfShn    = 22.0
	hopfOffset = 0.30
)

func renderHopf(frame int) string {
	sc := newScene(sceneCfg{
		aY:  float64(frame) * 0.010,
		aX:  float64(frame) * 0.012,
		fit: 1.20,
		shn: hopfShn,
		lx:  -0.48, ly: -0.52, lz: 0.71,
	})

	// Ring A: XY plane at (-offset, 0, 0); hole along +Z.
	for ui := 0; ui < hopfUN; ui++ {
		u := float64(ui) / float64(hopfUN) * 2 * math.Pi
		cu, su := math.Cos(u), math.Sin(u)
		for vi := 0; vi < hopfVN; vi++ {
			v := float64(vi) / float64(hopfVN) * 2 * math.Pi
			cv, sv := math.Cos(v), math.Sin(v)
			sc.plotGray(
				-hopfOffset+(hopfR+hopfRr*cv)*cu,
				(hopfR+hopfRr*cv)*su,
				hopfRr*sv,
				cv*cu, cv*su, sv,
			)
		}
	}
	// Ring B: XZ plane at (+offset, 0, 0); hole along +Y — links Ring A.
	for ui := 0; ui < hopfUN; ui++ {
		u := float64(ui) / float64(hopfUN) * 2 * math.Pi
		cu, su := math.Cos(u), math.Sin(u)
		for vi := 0; vi < hopfVN; vi++ {
			v := float64(vi) / float64(hopfVN) * 2 * math.Pi
			cv, sv := math.Cos(v), math.Sin(v)
			sc.plotGray(
				hopfOffset+(hopfR+hopfRr*cv)*cu,
				hopfRr*sv,
				(hopfR+hopfRr*cv)*su,
				cv*cu, sv, cv*su,
			)
		}
	}
	return sc.String()
}

func openRootLogCmd(action actionMode) tea.Cmd {
	path := qvosRootLogPath(action)
	if _, err := os.Stat(path); err != nil {
		return nil
	}
	return openEditorCmd(path)
}

func openEditorCmd(path string) tea.Cmd {
	editor := strings.TrimSpace(os.Getenv("VISUAL"))
	if editor == "" {
		editor = strings.TrimSpace(os.Getenv("EDITOR"))
	}
	if editor == "" {
		editor = "vi"
	}

	parts := strings.Fields(editor)
	if len(parts) == 0 {
		parts = []string{"vi"}
	}
	args := append(parts[1:], path)
	return tea.ExecProcess(exec.Command(parts[0], args...), func(error) tea.Msg { return nil })
}

func findRootScript(action actionMode) (string, error) {
	scriptName, envName, err := rootScriptSpec(action)
	if err != nil {
		return "", err
	}

	if override := strings.TrimSpace(os.Getenv(envName)); override != "" {
		return resolveRootScript(override)
	}

	var candidates []string
	if wd, err := os.Getwd(); err == nil {
		candidates = append(candidates, filepath.Join(wd, scriptName))
	}
	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(exe), scriptName))
		if realExe, err := filepath.EvalSymlinks(exe); err == nil {
			candidates = append(candidates, filepath.Join(filepath.Dir(realExe), scriptName))
		}
	}

	seen := make(map[string]bool)
	for _, candidate := range candidates {
		path, err := filepath.Abs(candidate)
		if err != nil || seen[path] {
			continue
		}
		seen[path] = true
		if err := validateRootScript(path); err == nil {
			return path, nil
		}
	}

	return "", fmt.Errorf("%s not found; set %s or provide %s in the project/binary directory", scriptName, envName, scriptName)
}

func findInstallScript() (string, error) {
	return findRootScript(actionApply)
}

func findBuildScript() (string, error) {
	return findRootScript(actionBuild)
}

func rootScriptSpec(action actionMode) (scriptName string, envName string, err error) {
	switch action {
	case actionBuild:
		return "bin/qvos-build", "QVOS_BUILD_SCRIPT", nil
	case actionReset:
		return "bin/qvos-reset", "QVOS_REVERT_SCRIPT", nil
	case actionApply:
		return "bin/qvos-apply", "QVOS_INSTALL_SCRIPT", nil
	case actionUpdate:
		return "bin/qvos-update", "QVOS_UPDATE_SCRIPT", nil
	default:
		return "", "", fmt.Errorf("action %d does not have a root script", action)
	}
}

func resolveRootScript(path string) (string, error) {
	path, err := resolveUserPath(path)
	if err != nil {
		return "", err
	}
	if err := validateRootScript(path); err != nil {
		return "", err
	}
	return path, nil
}

func validateRootScript(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("%s is a directory", path)
	}
	return nil
}

func qvosRootLogPath(action actionMode) string {
	switch action {
	case actionBuild:
		return qvosBuildLogPath()
	case actionReset:
		return qvosRevertLogPath()
	case actionApply:
		return qvosInstallLogPath()
	case actionUpdate:
		return qvosUpdateLogPath()
	default:
		return qvosInstallLogPath()
	}
}

func qvosBuildLogPath() string {
	return qvosStateLogPath("iso", "build.log")
}

func qvosBuildLockPath() string {
	return qvosStateLogPath("iso", "build.lock")
}

func qvosEnvEnabled(name string) bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(name))) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func qvosInstallLogPath() string {
	return qvosStateLogPath("install", "root-install.log")
}

func qvosRevertLogPath() string {
	return qvosStateLogPath("revert", "root-revert.log")
}

func qvosUpdateLogPath() string {
	return qvosStateLogPath("update", "root-update.log")
}

func qvosStateLogPath(domain string, name string) string {
	stateHome := strings.TrimSpace(os.Getenv("XDG_STATE_HOME"))
	if stateHome == "" {
		home, err := os.UserHomeDir()
		if err != nil || home == "" {
			return filepath.Join(os.TempDir(), "qvos", domain, name)
		}
		stateHome = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(stateHome, "qvos", domain, name)
}

func shortError(err error) string {
	if err == nil {
		return ""
	}
	text := strings.TrimSpace(err.Error())
	text = strings.Join(strings.Fields(text), " ")
	if len(text) > 42 {
		text = text[:39] + "..."
	}
	return text
}

func shouldDefaultToISOInstaller() bool {
	if os.Getenv("QVOS_ISO_INSTALLER") == "1" {
		return true
	}
	if os.Geteuid() != 0 {
		return false
	}
	if _, err := os.Stat("/run/archiso"); err != nil {
		return false
	}
	for _, path := range []string{"/root/.automated_script.sh", "/root/configurator", "/root/omarchy", "/root/qvos"} {
		if _, err := os.Stat(path); err != nil {
			return false
		}
	}
	return true
}

// -- main --

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--iso-installer-preview" {
		if err := runISOInstaller(true); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if (len(os.Args) > 1 && os.Args[1] == "--iso-installer") || (len(os.Args) == 1 && shouldDefaultToISOInstaller()) {
		if err := runISOInstaller(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "--iso-progress" {
		if err := runISOProgress(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "--iso-finished" {
		if err := runISOFinished(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	p := tea.NewProgram(model{})
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
