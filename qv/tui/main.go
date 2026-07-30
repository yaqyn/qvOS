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
	"unicode"
	"unicode/utf8"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	actionflow "github.com/Yaqyn-qvOS/qvOS/action"
	updateflow "github.com/Yaqyn-qvOS/qvOS/update"
)

// -- palette --

const (
	bgTerm  = "#020202"
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

var buildSourceHash = "unmanaged"

func tuiEnvironment() []string {
	// The qvOS TUI owns its branded palette; keep terminal capability detection
	// while preventing a caller's generic color opt-out from erasing it.
	env := make([]string, 0, len(os.Environ()))
	for _, entry := range os.Environ() {
		if strings.HasPrefix(entry, "NO_COLOR=") {
			continue
		}
		env = append(env, entry)
	}
	return env
}

func newTUIProgram(model tea.Model, options ...tea.ProgramOption) *tea.Program {
	options = append(options, tea.WithEnvironment(tuiEnvironment()))
	return tea.NewProgram(model, options...)
}

// -- menu data --

type hubAction string

const (
	hubActionUpdate hubAction = "qvos.update"
	hubActionBuild  hubAction = "qvos.iso.build"
)

type item struct {
	id, title, desc string
	action          hubAction
}

type section struct {
	name  string
	items []item
}

var sections = []section{
	{
		name: "SYSTEM",
		items: []item{
			{id: "00", title: "UPDATE", desc: "Sync qvOS", action: hubActionUpdate},
			{id: "01", title: "BUILD", desc: "Build qvOS ISO", action: hubActionBuild},
		},
	},
}

func validateHubCatalog(catalog []section) error {
	if len(catalog) == 0 {
		return errors.New("qvOS hub has no sections")
	}

	seenSections := make(map[string]struct{}, len(catalog))
	seenActions := make(map[hubAction]struct{})
	for _, section := range catalog {
		if strings.TrimSpace(section.name) == "" {
			return errors.New("qvOS hub has an unnamed section")
		}
		if _, exists := seenSections[section.name]; exists {
			return fmt.Errorf("qvOS hub section is duplicated: %s", section.name)
		}
		seenSections[section.name] = struct{}{}
		if len(section.items) == 0 {
			return fmt.Errorf("qvOS hub section has no actions: %s", section.name)
		}

		seenIDs := make(map[string]struct{}, len(section.items))
		for _, entry := range section.items {
			if strings.TrimSpace(entry.id) == "" ||
				strings.TrimSpace(entry.title) == "" ||
				strings.TrimSpace(entry.desc) == "" {
				return fmt.Errorf("qvOS hub section %s has incomplete action metadata", section.name)
			}
			if _, exists := seenIDs[entry.id]; exists {
				return fmt.Errorf("qvOS hub action id is duplicated in %s: %s", section.name, entry.id)
			}
			seenIDs[entry.id] = struct{}{}
			switch entry.action {
			case hubActionUpdate, hubActionBuild:
			default:
				return fmt.Errorf("qvOS hub action is unsupported: %s", entry.action)
			}
			if _, exists := seenActions[entry.action]; exists {
				return fmt.Errorf("qvOS hub action is duplicated: %s", entry.action)
			}
			seenActions[entry.action] = struct{}{}
		}
	}
	return nil
}

type layoutMode int

const (
	layoutDesktop layoutMode = iota
	layoutTablet
	layoutMobile
)

const (
	desktopMinWidth  = 96
	desktopMinHeight = 34
	tabletMinWidth   = 60
	tabletMinHeight  = 26
	cellAspectWidth  = 20
	cellAspectHeight = 49
	sideGap          = 6
	sidePadding      = 4
	sideLeftMax      = 48
	sideRightMax     = 64
	logSideLeftMax   = 36
	logSideRightMax  = 96
)

func layoutFor(width, height int) layoutMode {
	switch {
	case width >= desktopMinWidth && height >= desktopMinHeight:
		return layoutDesktop
	case width >= tabletMinWidth && height >= tabletMinHeight:
		return layoutTablet
	default:
		return layoutMobile
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

// The live Alacritty grid measures 98x40 cells in a 720x720 window. Compare
// the calibrated physical aspect, while letting true fullscreen canvases use
// their dedicated centered composition.
func isSideComposition(width, height int, fullscreen bool) bool {
	if fullscreen {
		return false
	}
	return width*cellAspectWidth > height*cellAspectHeight
}

func renderViewport(width, height int, body string) string {
	return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, body)
}

func sideColumnWidths(width int) (int, int) {
	available := width - sideGap - sidePadding*2
	if available < 2 {
		available = 2
	}
	leftWidth := available * 2 / 5
	rightWidth := available - leftWidth
	if leftWidth > sideLeftMax {
		leftWidth = sideLeftMax
	}
	if rightWidth > sideRightMax {
		rightWidth = sideRightMax
	}
	if leftWidth < 1 {
		leftWidth = 1
	}
	if rightWidth < 1 {
		rightWidth = 1
	}
	return leftWidth, rightWidth
}

func renderSideColumns(width int, left, right string) string {
	leftWidth, rightWidth := sideColumnWidths(width)
	return renderColumnPair(leftWidth, rightWidth, left, right)
}

func sideLogColumnWidths(width int) (int, int) {
	available := width - sideGap - sidePadding*2
	if available < 2 {
		available = 2
	}

	leftWidth := available * 3 / 10
	if leftWidth > logSideLeftMax {
		leftWidth = logSideLeftMax
	}
	if leftWidth < 1 {
		leftWidth = 1
	}

	rightWidth := available - leftWidth
	if rightWidth > logSideRightMax {
		rightWidth = logSideRightMax
	}
	if rightWidth < 1 {
		rightWidth = 1
	}
	return leftWidth, rightWidth
}

func renderSideLogColumns(width int, left, right string) string {
	leftWidth, rightWidth := sideLogColumnWidths(width)
	return renderColumnPair(leftWidth, rightWidth, left, right)
}

func renderColumnPair(leftWidth, rightWidth int, left, right string) string {
	leftColumn := lipgloss.NewStyle().Width(leftWidth).Align(lipgloss.Center)
	rightColumn := lipgloss.NewStyle().Width(rightWidth).Align(lipgloss.Center)
	return lipgloss.JoinHorizontal(
		lipgloss.Center,
		leftColumn.Render(left),
		strings.Repeat(" ", sideGap),
		rightColumn.Render(right),
	)
}

func renderIdentity(product, page string) string {
	return strings.Join([]string{
		sWhite.Render(product),
		sDim.Render(strings.ToUpper(page)),
	}, "\n")
}

type menuMetrics struct {
	titleWidth int
	descWidth  int
}

func measureMenu(catalog []section) menuMetrics {
	var metrics menuMetrics
	for _, s := range catalog {
		for _, it := range s.items {
			if width := lipgloss.Width(it.title); width > metrics.titleWidth {
				metrics.titleWidth = width
			}
			if width := lipgloss.Width(it.desc); width > metrics.descWidth {
				metrics.descWidth = width
			}
		}
	}
	return metrics
}

// computeMenuRowWidth returns the stable width shared by every menu row.
// Titles occupy one measured column so descriptions always begin at the same
// cell, even when the active section changes.
func computeMenuRowWidth(withDesc bool) int {
	metrics := measureMenu(sections)
	width := 7 + metrics.titleWidth
	if withDesc {
		width += 3 + metrics.descWidth
	}
	return width
}

func menuDescriptionsFit(availableWidth int) bool {
	return computeMenuRowWidth(true) <= availableWidth
}

// -- animation ticker --

const (
	framesPerSecond = 30
	framesPerTick   = 2
	animationSpeed  = 1.6
)

func animationFrame(frame int) float64 {
	return float64(frame) * animationSpeed
}

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
	actionUpdate
	actionGeneric
)

var currentActionSpec actionflow.Spec

type modelRole uint8

const (
	modelCore modelRole = iota
	modelThreeRings
	modelTwoRings
	modelOneRing
)

type model struct {
	tab               int
	cursor            int
	frame             int
	width, height     int
	fullscreen        bool
	loading           bool
	action            actionMode
	loadStart         int
	scriptRunning     bool
	scriptDone        bool
	scriptErr         error
	scriptPath        string
	sudoChecking      bool
	sudoPrompt        bool
	sudoPassword      []rune
	sudoErr           error
	scriptCancel      context.CancelFunc
	scriptEvents      <-chan scriptEvent
	scriptStatus      string
	scriptProgress    float64
	scriptTarget      float64
	scriptLogLines    []string
	scriptArtifact    string
	scriptRelease     string
	scriptCanceling   bool
	scriptCanceled    bool
	logOverlay        bool
	terminalView      bool
	logScroll         int
	logCopyStatus     string
	helpOverlay       bool
	updateConfirm     bool
	updateChoice      int
	updateStopConfirm bool
	updateStopChoice  int
	updatePreflight   bool
	dedicatedAction   bool
	updateCanceled    bool
	startImmediately  bool
}

func isRootAction(action actionMode) bool {
	return action == actionUpdate || action == actionGeneric
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
		if m.sudoPrompt || m.sudoChecking || m.updatePreflight {
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

func (m model) Init() tea.Cmd {
	commands := []tea.Cmd{tick(), detectFullscreenCmd()}
	if m.startImmediately {
		commands = append(commands, startImmediateActionCmd())
	}
	return tea.Batch(commands...)
}

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
		return m, detectFullscreenCmd()
	case fullscreenStateMsg:
		m.fullscreen = msg.fullscreen

	case startImmediateActionMsg:
		if !m.startImmediately || !isOneRingAction(m.action) {
			return m, nil
		}
		m.startImmediately = false
		return m.startRootAction(m.action)

	case tuiLogCopiedMsg:
		m.logCopyStatus = tuiLogCopyResultStatus(msg.err)
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
			if cleanLine != "" {
				m.scriptLogLines = appendLimited(m.scriptLogLines, cleanLine, maxScriptLogLines)
				if m.logScroll > 0 {
					m.logScroll = min(
						m.logScroll+1,
						max(0, len(m.scriptLogLines)-m.logViewportRows()),
					)
				}
			}
			if cleanLine != "" && m.action == actionBuild {
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
				m.scriptStatus = rootActionCanceledStatus(m.action)
			}
			m.scriptCancel = nil
			m.scriptEvents = nil
			m.scriptCanceling = false
			m.updateStopConfirm = false
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

	case rootPreflightDoneMsg:
		if m.action != msg.action || m.scriptPath != msg.script {
			return m, nil
		}
		m.updatePreflight = false
		if msg.err != nil {
			m.scriptDone = true
			m.scriptErr = msg.err
			m.scriptStatus = shortError(msg.err)
			return m, nil
		}
		if !requirementsForAction(msg.action).Authorization {
			return m.startRootScriptRun(msg.action, msg.script)
		}
		m.sudoChecking = true
		m.scriptStatus = "authorizing sudo"
		return m, checkSudoCachedCmd(msg.action, msg.script)

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
		if m.helpOverlay || m.terminalView {
			return m, nil
		}
		if !m.loading {
			return m.mainMouse(msg)
		}
		return m, nil

	case tea.MouseWheelMsg:
		return m, nil

	case tea.KeyPressMsg:
		if helpOverlay, handled := handleTUIHelpKeyWithQuestion(m.helpOverlay, msg, !m.sudoPrompt); handled {
			m.helpOverlay = helpOverlay
			return m, nil
		}
		if m.loading && isScriptAction(m.action) &&
			(m.logOverlay || m.terminalView || isOneRingAction(m.action)) {
			logLines := m.scriptLogLines
			visibleRows := m.logViewportRows()
			if isOneRingAction(m.action) {
				logLines, visibleRows = m.oneRingInformationLines()
			}
			if offset, handled := updateTUILogScroll(
				m.logScroll,
				msg.String(),
				len(logLines),
				visibleRows,
			); handled {
				m.logScroll = offset
				return m, nil
			}
		}
		if m.terminalView {
			switch msg.String() {
			case "y", "Y":
				var cmd tea.Cmd
				m.logCopyStatus, cmd = beginTUILogCopy(m.scriptLogLines)
				return m, cmd
			case "ctrl+v":
				m.terminalView = false
				m.logCopyStatus = ""
				return m, nil
			case "v", "V":
				m.terminalView = false
				m.logOverlay = true
				m.logCopyStatus = ""
				return m, nil
			case "ctrl+c", "ctrl+z":
				if m.loadPhase() != loadRun {
					return m, nil
				}
				m.terminalView = false
			default:
				return m, nil
			}
		}
		if m.loading {
			if m.updateStopConfirm {
				return m.handleUpdateStopConfirmationKey(msg)
			}
			if m.updateConfirm {
				return m.handleUpdateConfirmationKey(msg)
			}
			if m.sudoPrompt {
				return m.handleSudoKey(msg)
			}
			phase := m.loadPhase()
			switch msg.String() {
			case "ctrl+c", "ctrl+z":
				if m.scriptRunning && m.scriptCancel != nil {
					if requiresStopConfirmation(m.action) && !m.scriptCanceling {
						m.terminalView = false
						m.updateStopConfirm = true
						m.updateStopChoice = 0
						return m, nil
					}
					m.scriptCanceling = true
					m.scriptStatus = rootActionCancelingStatus(m.action)
					m.scriptTarget = max(m.scriptTarget, 0.98)
					m.scriptCancel()
					return m, nil
				}
				if m.scriptRunning || m.sudoChecking || m.updatePreflight {
					return m, nil
				}
				return m, tea.Quit
			case "esc":
				if !m.scriptRunning && !m.sudoChecking && !m.updatePreflight {
					return m.leaveRootAction()
				}
			case "enter":
				if phase != loadRun {
					return m.leaveRootAction()
				}
			case "v", "V":
				if isScriptAction(m.action) && !isOneRingAction(m.action) {
					m.logOverlay = !m.logOverlay
				}
			case "ctrl+v":
				if isScriptAction(m.action) && !isOneRingAction(m.action) {
					m.terminalView = true
					m.logCopyStatus = ""
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
			return m.activateMenuItem()
		}
	}
	return m, nil
}

func (m model) View() tea.View {
	termWidth, termHeight := safeDimensions(m.width, m.height)
	width, height := termWidth, termHeight
	mode := layoutFor(width, height)

	var body string
	if m.helpOverlay {
		body = renderTUIHelp(width, m.helpTitle(), m.helpHints())
	} else if m.terminalView && m.loading && isScriptAction(m.action) {
		body = renderTUITerminalOutput(
			width,
			height,
			rootActionName(m.action),
			m.scriptLogLines,
			m.logScroll,
			m.logCopyStatus,
			m.terminalHints(),
		)
	} else if isSideComposition(width, height, m.fullscreen) {
		body = m.renderSideBody(width, height)
	} else {
		reserveRows := fullCanvasReserveRows
		if m.loading && m.logOverlay {
			reserveRows = logCanvasReserveRows
		}
		var showIcon bool
		canvasW, canvasH, showIcon = fitCenterStageCanvas(width, height, reserveRows)
		if !showIcon {
			canvasW, canvasH = min(maxCanvasW, max(1, width-4)), 0
		}

		icon := ""
		if showIcon {
			icon = m.renderActiveIcon()
		}
		if m.loading && m.logOverlay {
			canvasW = fitLogContentWidth(width)
		} else {
			canvasW = fitContentWidth(width)
		}
		if mode == layoutDesktop {
			body = m.renderDesktopBody(icon)
		} else {
			body = m.renderReducedBody(mode, icon)
		}
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
	v.WindowTitle = "qvOS"
	return v
}

func (m model) renderSideBody(width, height int) string {
	leftWidth, _ := sideColumnWidths(width)
	page := sections[m.tab].name
	if m.loading {
		page = rootActionName(m.action)
		if m.logOverlay {
			logLeftWidth, logRightWidth := sideLogColumnWidths(width)
			canvasW, canvasH = logLeftWidth, 0
			left := m.renderRootProgressFor(layoutTablet)
			canvasW = logRightWidth
			right := m.renderRootLogOverlayFor(layoutTablet)
			return renderSideLogColumns(width, left, right)
		}
	}

	canvasW, canvasH = leftWidth, 0
	middleMode := layoutMobile
	if m.loading && isScriptAction(m.action) &&
		!m.updateConfirm && !m.updateStopConfirm && !m.sudoPrompt &&
		leftWidth >= progressBarWidth {
		middleMode = layoutTablet
	}
	left := m.renderMiddle(middleMode)
	right := renderIdentity("qvOS", page)

	if iconWidth, iconHeight, ok := fitSideIconCanvas(width, height); ok {
		canvasW, canvasH = iconWidth, iconHeight
		icon := m.renderActiveIcon()
		right = lipgloss.JoinVertical(lipgloss.Center, icon, "", renderIdentity("qvOS", page))
		canvasW, canvasH = leftWidth, 0
	}

	return renderSideColumns(width, left, right)
}

func (m model) renderDesktopBody(icon string) string {
	title := sWhite.Render("qvOS")
	tagline := sDim.Render("· · · · ·")
	lines := []string{icon, "", title, tagline, ""}
	if m.loading {
		lines = append(lines, "")
	}
	lines = append(lines, m.renderMiddle(layoutDesktop))
	return lipgloss.JoinVertical(lipgloss.Center, lines...)
}

func (m model) renderActiveIcon() string {
	return renderModelRole(m.activeModelRole(), m.frame)
}

func (m model) activeModelRole() modelRole {
	if m.loading && isScriptAction(m.action) {
		return requirementsForAction(m.action).Model
	}
	return modelCore
}

func (m model) helpTitle() string {
	if m.terminalView && m.loading {
		return rootActionName(m.action) + " terminal output"
	}
	if m.loading {
		return rootActionName(m.action) + " controls"
	}
	if m.tab >= 0 && m.tab < len(sections) {
		return sections[m.tab].name + " controls"
	}
	return "controls"
}

func (m model) helpHints() []tuiHint {
	if !m.loading {
		hints := []tuiHint{
			{Key: "↑ / ↓  or  j / k", Action: "move between items"},
		}
		if len(sections) > 1 {
			hints = append(hints,
				tuiHint{Key: "← / →  or  h / l", Action: "change page"},
				tuiHint{Key: "tab / shift+tab", Action: "change page"},
			)
		}
		hints = append(hints, tuiHint{Key: "enter", Action: "open the selected item"})
		hints = append(hints, tuiHint{Key: "ctrl+c", Action: "exit qvOS"})
		if layoutFor(m.width, m.height) == layoutDesktop {
			hints = append(hints, tuiHint{Key: "mouse", Action: "select or open an item"})
		}
		return hints
	}
	if m.terminalView {
		return m.terminalHelpHints()
	}
	if m.updateStopConfirm {
		keepAction := "keep updating"
		if m.action == actionGeneric {
			keepAction = strings.ToLower(currentActionSpec.KeepRunningAction())
		}
		return []tuiHint{
			{Key: "arrows / hjkl / tab", Action: "choose an option"},
			{Key: "enter", Action: "confirm the selected option"},
			{Key: "esc", Action: keepAction},
		}
	}
	if m.updateConfirm {
		cancelAction := "cancel before updating"
		if m.action == actionGeneric {
			cancelAction = "cancel before starting"
		}
		return []tuiHint{
			{Key: "arrows / hjkl / tab", Action: "choose an option"},
			{Key: "enter", Action: "continue with the selected option"},
			{Key: "esc / ctrl+c / ctrl+z", Action: cancelAction},
		}
	}
	if m.sudoPrompt {
		return []tuiHint{
			{Key: "type", Action: "enter the sudo password"},
			{Key: "backspace", Action: "delete one character"},
			{Key: "ctrl+u", Action: "clear the password"},
			{Key: "enter", Action: "authorize"},
			{Key: "esc", Action: "cancel and return"},
			{Key: "ctrl+c / ctrl+z", Action: "cancel or exit"},
		}
	}
	if isOneRingAction(m.action) {
		return m.oneRingHelpHints()
	}

	phase := m.loadPhase()
	hints := []tuiHint{
		{Key: "v", Action: "toggle the qvOS log panel"},
		{Key: "ctrl+v", Action: "toggle original terminal output"},
	}
	if m.logOverlay {
		hints = append(hints, tuiLogScrollHints()...)
	}
	switch phase {
	case loadErr:
		hints = append([]tuiHint{
			{Key: "r", Action: "retry the action"},
			{Key: "enter / esc", Action: "return"},
		}, hints...)
	case loadOK:
		hints = append([]tuiHint{{Key: "enter / esc", Action: "return"}}, hints...)
	default:
		action := "cancel the action"
		if isRootAction(m.action) {
			action = "open safe stop options"
		}
		hints = append([]tuiHint{{Key: "ctrl+c / ctrl+z", Action: action}}, hints...)
	}
	return hints
}

func (m model) oneRingHelpHints() []tuiHint {
	phase := m.loadPhase()
	hints := make([]tuiHint, 0, 4)
	lines, visibleRows := m.oneRingInformationLines()
	if len(lines) > visibleRows {
		hints = append(hints, tuiLogScrollHints()...)
	}
	switch phase {
	case loadErr:
		hints = append([]tuiHint{
			{Key: "r", Action: "retry"},
			{Key: "enter / esc", Action: "return"},
		}, hints...)
	case loadOK:
		hints = append([]tuiHint{{Key: "enter / esc", Action: "return"}}, hints...)
	default:
		hints = append([]tuiHint{{Key: "ctrl+c / ctrl+z", Action: "cancel"}}, hints...)
	}
	return hints
}

func (m model) hubPersistentHints() []tuiHint {
	return []tuiHint{
		{Key: "↑↓", Action: "move"},
		tuiHelpHint(),
	}
}

func (m model) rootPersistentHints() []tuiHint {
	if m.updateStopConfirm {
		return []tuiHint{
			{Key: "←→", Action: "choose"},
			tuiHelpHint(),
		}
	}
	if m.updateConfirm {
		return []tuiHint{
			{Key: "←→", Action: "choose"},
			tuiHelpHint(),
		}
	}
	if m.sudoPrompt {
		return []tuiHint{
			{Key: "enter", Action: "authorize"},
			tuiHelpHint(),
		}
	}
	if isOneRingAction(m.action) {
		switch m.loadPhase() {
		case loadErr:
			return []tuiHint{
				{Key: "r", Action: "retry"},
				tuiHelpHint(),
			}
		case loadOK:
			return []tuiHint{
				{Key: "enter", Action: "return"},
				tuiHelpHint(),
			}
		default:
			return []tuiHint{
				{Key: "ctrl+c/z", Action: "cancel"},
				tuiHelpHint(),
			}
		}
	}

	switch m.loadPhase() {
	case loadErr:
		return []tuiHint{
			{Key: "r", Action: "retry"},
			tuiHelpHint(),
		}
	case loadOK:
		return []tuiHint{
			{Key: "enter", Action: "return"},
			tuiHelpHint(),
		}
	default:
		action := "cancel"
		if isRootAction(m.action) {
			action = "stop options"
		}
		return []tuiHint{
			{Key: "ctrl+c/z", Action: action},
			tuiHelpHint(),
		}
	}
}

func (m model) terminalHelpHints() []tuiHint {
	hints := []tuiHint{
		{Key: "ctrl+v", Action: "switch to the qvOS view"},
		{Key: "v", Action: "return with the log panel open"},
	}
	hints = append(hints, tuiTerminalLogHints()...)
	if m.loadPhase() == loadRun {
		action := "cancel the action"
		if isRootAction(m.action) {
			action = "open safe stop options"
		}
		hints = append(hints, tuiHint{Key: "ctrl+c / ctrl+z", Action: action})
	}
	return hints
}

func (m model) terminalHints() []tuiHint {
	return []tuiHint{
		{Key: "ctrl+v", Action: "switch"},
		tuiHelpHint(),
	}
}

func (m model) renderMiddle(mode layoutMode) string {
	if m.loading {
		if isScriptAction(m.action) {
			return m.renderRootActionFor(mode)
		}
	}

	if mode == layoutDesktop {
		return m.renderFullMenu()
	}
	if mode == layoutTablet {
		return m.renderMidMenu()
	}
	return m.renderReducedMenu(mode)
}

func (m model) renderReducedBody(mode layoutMode, icon string) string {
	titleRows, middleRows, gapRows := m.reducedBodyRows(mode)
	if icon != "" && m.loading && gapRows == 0 &&
		m.height >= canvasH+middleRows+1 {
		gapRows = 1
	}
	var lines []string
	if icon != "" {
		lines = append(lines, centerCanvas(icon))
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
	if mode == layoutTablet && m.height >= tabletMinHeight {
		titleRows = 2
	}

	middleRows = m.reducedMiddleRows(mode)

	if mode == layoutTablet && m.height >= titleRows+middleRows+canvasH+1 {
		gapRows = 1
	}
	return titleRows, middleRows, gapRows
}

func (m model) reducedMiddleRows(mode layoutMode) int {
	if m.height <= 1 {
		return 0
	}

	if m.loading {
		if mode == layoutMobile {
			if m.sudoPrompt && m.sudoErr != nil {
				return 4
			}
			return 3
		}
		if m.sudoPrompt && m.sudoErr != nil {
			return 3
		}
		return 2
	}

	if m.height <= 2 {
		return 1
	}
	if mode == layoutTablet {
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

	help := renderTUIHints(canvasW, m.hubPersistentHints()...)

	ctr := func(s string) string { return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s) }
	lines := []string{
		ctr(tabs),
		"",
		ctr(menu),
	}
	lines = append(lines, "", ctr(help))
	return strings.Join(lines, "\n")
}

func (m model) renderMidMenu() string {
	tabs := renderTabs(m.tab)
	showDesc := menuDescriptionsFit(canvasW)
	menu := m.renderMenuRows(showDesc)

	help := renderTUIHints(canvasW, m.hubPersistentHints()...)

	lines := []string{
		centerCanvas(tabs),
		"",
		centerCanvas(menu),
	}
	lines = append(lines, "", centerCanvas(help))
	return strings.Join(lines, "\n")
}

func (m model) renderReducedMenu(mode layoutMode) string {
	active := sections[m.tab]
	rows := []string{centerCanvas(renderActiveTab(m.tab))}
	metrics := measureMenu(sections)
	showDescriptions := compactMenuRowWidth(metrics, true) <= canvasW

	if m.height <= 2 {
		return strings.Join(rows, "\n")
	}

	if mode == layoutTablet || m.height >= 7 {
		rows = append(rows, "")
		for i, it := range active.items {
			rows = append(rows, centerCanvas(renderCompactMenuRow(it, i == m.cursor, metrics, canvasW, showDescriptions)))
		}
		rows = append(rows, "", centerCanvas(renderTUIHints(canvasW, m.hubPersistentHints()...)))
		return strings.Join(rows, "\n")
	}

	selected := active.items[m.cursor]
	rows = append(rows, centerCanvas(renderCompactMenuRow(selected, true, metrics, canvasW, showDescriptions)))
	if m.height >= 4 {
		rows = append(rows, centerCanvas(renderTUIHints(canvasW, m.hubPersistentHints()...)))
	}
	return strings.Join(rows, "\n")
}

func renderActiveTab(active int) string {
	name := sections[active].name
	if len(sections) == 1 {
		return sWhite.Render(name)
	}
	return sDim.Render("< ") + sWhite.Render(name) + sDim.Render(" >")
}

func compactMenuRowWidth(metrics menuMetrics, withDescription bool) int {
	width := 4 + metrics.titleWidth
	if withDescription {
		width += 2 + metrics.descWidth
	}
	return width
}

func renderCompactMenuRow(it item, selected bool, metrics menuMetrics, availableWidth int, showDescription bool) string {
	idStyle := sGray
	titleStyle := sMid
	descStyle := sDim
	if selected {
		idStyle = sRed
		titleStyle = sWhite
		descStyle = sGray
	}

	titleWidth := metrics.titleWidth
	if maximum := max(1, availableWidth-4); titleWidth > maximum {
		titleWidth = maximum
	}
	title := lipgloss.PlaceHorizontal(titleWidth, lipgloss.Left, titleStyle.Render(trimDisplay(it.title, titleWidth)))
	line := idStyle.Render(it.id) + "  " + title

	if showDescription {
		line += "  " + descStyle.Render(it.desc)
	}

	rowWidth := compactMenuRowWidth(metrics, showDescription)
	if rowWidth > availableWidth {
		rowWidth = availableWidth
	}
	return lipgloss.PlaceHorizontal(rowWidth, lipgloss.Left, line)
}

func (m model) renderMenuRows(showDesc bool) string {
	menuRowWidth := computeMenuRowWidth(showDesc)
	metrics := measureMenu(sections)
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
			lipgloss.PlaceHorizontal(metrics.titleWidth, lipgloss.Left, titleStyle.Render(it.title))
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
	if layoutFor(m.width, m.height) != layoutDesktop {
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

// activateMenuItem resolves a stable catalog action. Its tab and cursor are
// presentation state only and never define behavior.
func (m model) activateMenuItem() (model, tea.Cmd) {
	if m.tab < 0 || m.tab >= len(sections) ||
		m.cursor < 0 || m.cursor >= len(sections[m.tab].items) {
		return m, nil
	}

	switch sections[m.tab].items[m.cursor].action {
	case hubActionUpdate:
		return m.beginUpdateConfirmation(false)
	case hubActionBuild:
		return m.startBuildAction()
	default:
		return m, nil
	}
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

type rootPreflightDoneMsg struct {
	action actionMode
	script string
	err    error
}

type startImmediateActionMsg struct{}

func startImmediateActionCmd() tea.Cmd {
	return func() tea.Msg { return startImmediateActionMsg{} }
}

func (m model) beginUpdateConfirmation(dedicated bool) (model, tea.Cmd) {
	clearRunes(m.sudoPassword)
	m.loading = true
	m.action = actionUpdate
	m.loadStart = m.frame
	m.scriptRunning = false
	m.scriptDone = false
	m.scriptErr = nil
	m.scriptPath = ""
	m.sudoChecking = false
	m.sudoPrompt = false
	m.sudoPassword = nil
	m.sudoErr = nil
	m.scriptCancel = nil
	m.scriptEvents = nil
	m.scriptStatus = ""
	m.scriptProgress = 0
	m.scriptTarget = 0
	m.scriptLogLines = nil
	m.scriptArtifact = ""
	m.scriptRelease = ""
	m.scriptCanceling = false
	m.scriptCanceled = false
	m.logOverlay = false
	m.terminalView = false
	m.logScroll = 0
	m.logCopyStatus = ""
	m.helpOverlay = false
	m.updateConfirm = true
	m.updateChoice = 0
	m.updateStopConfirm = false
	m.updateStopChoice = 0
	m.updatePreflight = false
	m.dedicatedAction = dedicated
	m.updateCanceled = false
	return m, nil
}

func (m model) beginGenericAction(spec actionflow.Spec, dedicated bool) (model, tea.Cmd) {
	currentActionSpec = spec
	m, command := m.beginUpdateConfirmation(dedicated)
	m.action = actionGeneric
	if spec.Rings == 1 {
		m.updateConfirm = false
		m.startImmediately = true
	}
	return m, command
}

func (m model) handleUpdateConfirmationKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "left", "h", "up", "k", "shift+tab":
		m.updateChoice = 0
	case "right", "l", "down", "j", "tab":
		m.updateChoice = 1
	case "esc", "ctrl+c", "ctrl+z":
		return m.cancelUpdate()
	case "enter":
		if m.updateChoice == 1 {
			return m.cancelUpdate()
		}
		m.updateConfirm = false
		return m.startRootAction(m.action)
	}
	return m, nil
}

func (m model) handleUpdateStopConfirmationKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "left", "h", "up", "k", "shift+tab":
		m.updateStopChoice = 0
	case "right", "l", "down", "j", "tab":
		m.updateStopChoice = 1
	case "esc":
		m.updateStopConfirm = false
	case "enter":
		m.updateStopConfirm = false
		if m.updateStopChoice == 0 {
			return m, nil
		}
		if m.scriptRunning && m.scriptCancel != nil && !m.scriptCanceling {
			m.scriptCanceling = true
			m.scriptStatus = rootActionCancelingStatus(m.action)
			m.scriptTarget = max(m.scriptTarget, 0.98)
			m.scriptCancel()
		}
	}
	return m, nil
}

func (m model) cancelUpdate() (model, tea.Cmd) {
	clearRunes(m.sudoPassword)
	m.sudoPassword = nil
	m.sudoPrompt = false
	m.sudoChecking = false
	m.updatePreflight = false
	m.updateConfirm = false
	m.updateStopConfirm = false
	m.terminalView = false
	m.helpOverlay = false
	m.updateCanceled = true
	if m.dedicatedAction {
		return m, tea.Quit
	}
	m.loading = false
	return m, nil
}

func (m model) leaveRootAction() (model, tea.Cmd) {
	m.terminalView = false
	m.helpOverlay = false
	if m.dedicatedAction {
		return m, tea.Quit
	}
	m.loading = false
	return m, nil
}

func (m model) startRootAction(action actionMode) (model, tea.Cmd) {
	script, err := findRootScript(action)
	requirements := requirementsForAction(action)
	m.loading = true
	m.action = action
	m.loadStart = m.frame
	m.scriptRunning = false
	m.scriptDone = false
	m.scriptErr = nil
	m.scriptPath = script
	m.sudoChecking = !requirements.Preflight && requirements.Authorization
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
	m.terminalView = false
	m.logScroll = 0
	m.logCopyStatus = ""
	m.helpOverlay = false
	m.updateConfirm = false
	m.updateStopConfirm = false
	m.updateStopChoice = 0
	m.updatePreflight = requirements.Preflight
	m.updateCanceled = false

	if err != nil {
		m.sudoChecking = false
		m.updatePreflight = false
		m.scriptDone = true
		m.scriptErr = err
		return m, nil
	}

	if requirements.Preflight {
		m.scriptStatus = "checking action readiness"
		if action == actionUpdate {
			m.scriptStatus = "checking update readiness"
		}
		return m, checkRootPreflightCmd(action, script)
	}
	if !requirements.Authorization {
		return m.startRootScriptRun(action, script)
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
	m.terminalView = false
	m.logScroll = 0
	m.logCopyStatus = ""
	m.helpOverlay = false

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
	m.terminalView = false
	m.logScroll = 0
	m.logCopyStatus = ""
	m.helpOverlay = false
	m.updateStopConfirm = false
	m.updateStopChoice = 0
	return m, runRootScriptCmd(action, script)
}

func (m model) handleSudoKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c", "ctrl+z":
		if isRootAction(m.action) {
			return m.cancelUpdate()
		}
		return m, tea.Quit
	case "esc":
		if isRootAction(m.action) {
			return m.cancelUpdate()
		}
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
	case "ctrl+u":
		clearRunes(m.sudoPassword)
		m.sudoPassword = nil
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

func checkRootPreflightCmd(action actionMode, script string) tea.Cmd {
	return func() tea.Msg {
		var err error
		switch action {
		case actionUpdate:
			err = updateflow.Preflight(script)
		case actionGeneric:
			err = actionflow.Preflight(script)
		default:
			err = fmt.Errorf("action %d has no preflight", action)
		}
		return rootPreflightDoneMsg{
			action: action,
			script: script,
			err:    err,
		}
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
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid:   true,
		Pdeathsig: syscall.SIGTERM,
	}
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

	stdout, stdoutWriter, err := os.Pipe()
	if err != nil {
		events <- scriptEvent{action: action, script: script, status: "could not capture stdout", progress: 0, done: true, err: err}
		return
	}
	stderr, stderrWriter, err := os.Pipe()
	if err != nil {
		_ = stdout.Close()
		_ = stdoutWriter.Close()
		events <- scriptEvent{action: action, script: script, status: "could not capture stderr", progress: 0, done: true, err: err}
		return
	}
	cmd.Stdout = stdoutWriter
	cmd.Stderr = stderrWriter

	if err := cmd.Start(); err != nil {
		_ = stdout.Close()
		_ = stdoutWriter.Close()
		_ = stderr.Close()
		_ = stderrWriter.Close()
		events <- scriptEvent{action: action, script: script, status: "could not start script", progress: 0, done: true, err: err}
		return
	}

	outputDone := make(chan error, 2)
	scan := func(r *os.File) {
		defer r.Close()
		scanner := bufio.NewScanner(r)
		buf := make([]byte, 0, 64*1024)
		scanner.Buffer(buf, 1024*1024)
		var outputErr error
		for scanner.Scan() {
			line := scanner.Text()
			if logFile != nil {
				if _, err := fmt.Fprintln(logFile, line); err != nil && outputErr == nil {
					outputErr = fmt.Errorf("could not write command output: %w", err)
				}
			}
			status, progress := scriptProgressFromLine(action, line)
			events <- scriptEvent{action: action, script: script, line: line, status: status, progress: progress}
		}
		if err := scanner.Err(); err != nil && outputErr == nil {
			outputErr = fmt.Errorf("could not read command output: %w", err)
		}
		outputDone <- outputErr
	}
	go scan(stdout)
	go scan(stderr)

	err = cmd.Wait()
	_ = stdoutWriter.Close()
	_ = stderrWriter.Close()
	var outputFailure error
	for range 2 {
		if outputErr := <-outputDone; outputFailure == nil && outputErr != nil {
			outputFailure = outputErr
		}
	}
	if outputFailure != nil {
		err = outputFailure
	}

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
		return "", func() {}, fmt.Errorf("%s is not a regular file", script)
	}

	data, err := os.ReadFile(script)
	if err != nil {
		return "", func() {}, err
	}

	runtimeBase := strings.TrimSpace(os.Getenv("XDG_RUNTIME_DIR"))
	if runtimeBase == "" {
		runtimeBase = os.TempDir()
	}
	runtimeDir, err := os.MkdirTemp(runtimeBase, "qvos-tui-run-")
	if err != nil {
		return "", func() {}, err
	}
	cleanup := func() { _ = os.RemoveAll(runtimeDir) }

	tmp, err := os.CreateTemp(runtimeDir, ".qvos-run-*.sh")
	if err != nil {
		cleanup()
		return "", func() {}, err
	}
	tmpPath := tmp.Name()

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
	case actionUpdate:
		return updateflow.ProgressFromLine(clean)
	case actionGeneric:
		return actionflow.ProgressFromLine(clean, currentActionSpec)
	default:
		return "", -1
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
	line = stripANSI(line)

	frames := strings.Split(line, "\r")
	line = ""
	for index := len(frames) - 1; index >= 0; index-- {
		if strings.TrimSpace(frames[index]) != "" {
			line = frames[index]
			break
		}
	}

	var clean []rune
	for _, character := range line {
		switch character {
		case '\t':
			clean = append(clean, ' ', ' ')
		case '\b':
			if len(clean) > 0 {
				clean = clean[:len(clean)-1]
			}
		default:
			if !unicode.IsControl(character) {
				clean = append(clean, character)
			}
		}
	}

	line = strings.TrimSpace(string(clean))
	const maxLogLineRunes = 1024
	runes := []rune(line)
	if len(runes) > maxLogLineRunes {
		line = string(runes[:maxLogLineRunes-1]) + "…"
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

func (m model) renderRootActionFor(mode layoutMode) string {
	if m.updateStopConfirm {
		return m.renderUpdateStopConfirmationFor(mode)
	}
	if m.updateConfirm {
		return m.renderUpdateConfirmationFor(mode)
	}
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

func (m model) renderUpdateStopConfirmationFor(mode layoutMode) string {
	titleText := updateflow.StopPromptTitle
	noticeText := updateflow.StopPromptNotice
	keepAction := updateflow.KeepUpdatingAction
	stopAction := updateflow.StopUpdateAction
	if m.action == actionGeneric {
		titleText = currentActionSpec.StopPromptTitle()
		noticeText = currentActionSpec.StopPromptNotice()
		keepAction = currentActionSpec.KeepRunningAction()
		stopAction = currentActionSpec.StopAction()
	}

	title := centerCanvas(sWhite.Render(titleText))
	notice := centerCanvas(sMid.Render(noticeText))
	actions := centerCanvas(lipgloss.JoinHorizontal(
		lipgloss.Center,
		renderConfirmationAction(keepAction, m.updateStopChoice == 0),
		"   ",
		renderConfirmationAction(stopAction, m.updateStopChoice == 1),
	))

	content := strings.Join([]string{title, "", notice, "", actions}, "\n")
	return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
}

func (m model) renderUpdateConfirmationFor(mode layoutMode) string {
	if m.action == actionGeneric {
		return m.renderGenericActionConfirmationFor(mode)
	}

	title := centerCanvas(sWhite.Render(updateflow.Title))
	summary := centerCanvas(sGray.Render(updateflow.Summary))
	actions := centerCanvas(lipgloss.JoinHorizontal(
		lipgloss.Center,
		renderConfirmationAction(updateflow.PrimaryAction, m.updateChoice == 0),
		"   ",
		renderConfirmationAction(updateflow.CancelAction, m.updateChoice == 1),
	))

	if mode == layoutMobile {
		content := strings.Join([]string{title, "", actions}, "\n")
		return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
	}

	if mode == layoutTablet {
		content := strings.Join([]string{title, "", summary, "", actions}, "\n")
		return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
	}

	notice := centerCanvas(sMid.Render(updateflow.PowerNotice))
	history := centerCanvas(sDim.Render(updateflow.SourceHistoryLabel))
	content := strings.Join([]string{
		title,
		"",
		summary,
		notice,
		"",
		actions,
		"",
		history,
		"",
	}, "\n")
	return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
}

func (m model) renderGenericActionConfirmationFor(mode layoutMode) string {
	title := centerCanvas(sWhite.Render(currentActionSpec.Heading()))
	summary := centerCanvas(sGray.Render(trimDisplay(currentActionSpec.Summary, max(1, canvasW))))
	actions := centerCanvas(lipgloss.JoinHorizontal(
		lipgloss.Center,
		renderConfirmationAction(currentActionSpec.PrimaryAction(), m.updateChoice == 0),
		"   ",
		renderConfirmationAction(actionflow.CancelAction, m.updateChoice == 1),
	))

	if mode == layoutMobile {
		content := strings.Join([]string{title, "", actions}, "\n")
		return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
	}

	content := strings.Join([]string{title, "", summary, "", actions}, "\n")
	return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
}

func renderConfirmationAction(label string, selected bool) string {
	if selected {
		return sRed.Render("● ") + sWhite.Render(label)
	}
	return sDim.Render("  ") + sGray.Render(label)
}

func (m model) renderSudoPromptFor(mode layoutMode) string {
	status := "sudo password required"
	if m.sudoErr != nil {
		status = shortError(m.sudoErr)
	}
	return renderAuthorizationScreen(authorizationScreen{
		Title:       rootActionName(m.action),
		Status:      status,
		StatusError: m.sudoErr != nil,
		Password:    m.sudoPassword,
		Hints:       m.rootPersistentHints(),
	}, mode)
}

func (m model) renderRootProgressFor(mode layoutMode) string {
	if isOneRingAction(m.action) {
		return m.renderOneRingInformationFor(mode)
	}
	phase := m.loadPhase()
	progress := m.loadProgress()
	if m.scriptCanceled {
		return m.renderRootCanceledFor(mode)
	}
	if phase == loadOK && m.action == actionBuild && !m.scriptCanceled {
		return m.renderBuildFinishedFor(mode)
	}
	var title, status string
	switch phase {
	case loadOK:
		title = rootActionPastTense(m.action)
		status = rootActionCompleteStatus(m.action)
	case loadErr:
		title = rootActionName(m.action) + " FAILED"
		status = shortError(m.scriptErr)
	default:
		title = rootActionActiveTitle(m.action)
		if m.updatePreflight {
			status = "checking action readiness"
			if m.action == actionUpdate {
				status = "checking update readiness"
			}
		} else if m.sudoChecking {
			status = "authorizing sudo"
		} else if m.scriptCanceling {
			status = rootActionCancelingStatus(m.action)
		} else if m.scriptStatus != "" {
			status = m.scriptStatus
		} else {
			status = rootActionRunningStatus(m.action)
		}
	}
	if status == "" {
		status = "script failed"
	}
	return renderProgressScreen(progressScreen{
		Title:    title,
		Status:   status,
		Phase:    phase,
		Progress: progress,
		Bar:      requirementsForAction(m.action).ProgressBar,
		Hints:    m.rootPersistentHints(),
	}, mode)
}

func (m model) renderOneRingInformationFor(mode layoutMode) string {
	lines := m.scriptLogLines
	empty := currentActionSpec.RunningStatus()
	isError := m.scriptErr != nil
	switch {
	case isError:
		lines = []string{shortError(m.scriptErr)}
		empty = "action failed"
	case m.scriptDone && len(lines) == 0:
		empty = currentActionSpec.CompleteStatus()
	case m.updatePreflight:
		empty = "checking " + currentActionSpec.Title
	case m.sudoChecking:
		empty = "authorizing sudo"
	case m.scriptStatus != "":
		empty = m.scriptStatus
	}

	visibleRows := max(3, rootLogPanelHeight(mode, m.height))
	return renderInformationScreen(informationScreen{
		Title:       currentActionSpec.Title,
		Lines:       lines,
		Empty:       empty,
		Error:       isError,
		Width:       canvasW,
		VisibleRows: visibleRows,
		Scroll:      m.logScroll,
		Hints:       m.rootPersistentHints(),
	})
}

func (m model) oneRingInformationLines() ([]string, int) {
	width := fitContentWidth(m.width)
	mode := layoutFor(m.width, m.height)
	if isSideComposition(m.width, m.height, m.fullscreen) {
		width, _ = sideColumnWidths(m.width)
		mode = layoutMobile
		if width >= progressBarWidth {
			mode = layoutTablet
		}
	}
	contentWidth := max(1, width-2)
	visibleRows := max(3, rootLogPanelHeight(mode, m.height))
	lines := m.scriptLogLines
	if m.scriptErr != nil {
		lines = []string{shortError(m.scriptErr)}
	}
	return formatInformationLines(
		currentActionSpec.Title,
		lines,
		contentWidth,
		m.scriptErr != nil,
	), visibleRows
}

func (m model) renderRootCanceledFor(mode layoutMode) string {
	title := rootActionName(m.action) + " CANCELED"
	if mode != layoutDesktop {
		content := strings.Join([]string{
			centerCanvas(sWhite.Render(title)),
			centerCanvas(sGray.Render(rootActionCanceledStatus(m.action))),
		}, "\n")
		return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
	}

	ctr := func(s string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s)
	}
	content := strings.Join([]string{
		ctr(sWhite.Render(title)),
		"",
		ctr(sGray.Render(rootActionCanceledStatus(m.action))),
		"",
	}, "\n")
	return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
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

	if mode == layoutMobile {
		return appendTUIHints(
			centerCanvas(sWhite.Render("BUILD FINISHED")),
			canvasW,
			m.rootPersistentHints()...,
		)
	}
	if mode == layoutTablet {
		content := strings.Join([]string{
			centerCanvas(sWhite.Render("BUILD FINISHED")),
			centerCanvas(sGray.Render(trimDisplay(releaseName, canvasW))),
		}, "\n")
		return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
	}

	labelWidth := 8
	nameWidth := max(12, canvasW-labelWidth-2)
	dirWidth := max(12, canvasW-labelWidth-2)
	nameLine := sGray.Render("release ") + sWhite.Render(trimDisplay(releaseName, nameWidth))
	dirLine := sGray.Render("folder  ") + sMid.Render(trimDisplay(releaseDir, dirWidth))
	ctr := func(s string) string {
		return lipgloss.PlaceHorizontal(canvasW, lipgloss.Center, s)
	}

	content := strings.Join([]string{
		ctr(sWhite.Render("BUILD FINISHED")),
		"",
		ctr(nameLine),
		ctr(dirLine),
		"",
	}, "\n")
	return appendTUIHints(content, canvasW, m.rootPersistentHints()...)
}

func rootLogPanelHeight(mode layoutMode, terminalHeight int) int {
	height := 18
	if mode == layoutTablet {
		height = 16
	}
	if mode == layoutMobile {
		height = 7
	}
	if terminalHeight > 0 {
		heightLimit := terminalHeight - 4
		if mode == layoutDesktop {
			heightLimit = terminalHeight - 12
		}
		if heightLimit < 3 {
			heightLimit = 3
		}
		if height > heightLimit {
			height = heightLimit
		}
	}
	return height
}

func (m model) logViewportRows() int {
	if m.terminalView {
		return terminalOutputContentHeight(m.height)
	}
	mode := layoutFor(m.width, m.height)
	if isSideComposition(m.width, m.height, m.fullscreen) {
		mode = layoutTablet
	}
	return max(1, rootLogPanelHeight(mode, m.height)-2)
}

func (m model) renderRootLogOverlayFor(mode layoutMode) string {
	width := canvasW
	if width < 1 {
		width = 1
	}
	if width > logSideRightMax {
		width = logSideRightMax
	}

	height := rootLogPanelHeight(mode, m.height)
	contentHeight := max(1, height-2)
	return renderLogPanel(logPanelScreen{
		Lines:       m.scriptLogLines,
		Width:       width,
		Height:      height,
		VisibleRows: contentHeight,
		Scroll:      m.logScroll,
		Empty:       "waiting for logs",
		Border:      true,
	})
}

func rootActionName(action actionMode) string {
	switch action {
	case actionUpdate:
		return "UPDATE"
	case actionGeneric:
		return currentActionSpec.Heading()
	default:
		return "BUILD"
	}
}

func rootActionPastTense(action actionMode) string {
	switch action {
	case actionBuild:
		return "BUILT"
	case actionUpdate:
		return "UPDATED"
	case actionGeneric:
		return currentActionSpec.PastTense()
	default:
		return "READY"
	}
}

func rootActionActiveTitle(action actionMode) string {
	switch action {
	case actionBuild:
		return "BUILDING"
	case actionUpdate:
		return "UPDATING"
	case actionGeneric:
		return currentActionSpec.ActiveTitle()
	default:
		return "RUNNING"
	}
}

func rootActionRunningStatus(action actionMode) string {
	switch action {
	case actionBuild:
		return "ISO build running in background"
	case actionUpdate:
		return updateflow.RunningStatus
	case actionGeneric:
		return currentActionSpec.RunningStatus()
	default:
		return "script running in background"
	}
}

func rootActionCompleteStatus(action actionMode) string {
	switch action {
	case actionBuild:
		return "ISO build complete"
	case actionUpdate:
		return updateflow.CompleteStatus
	case actionGeneric:
		return currentActionSpec.CompleteStatus()
	default:
		return "complete"
	}
}

func rootActionCancelingStatus(action actionMode) string {
	switch action {
	case actionBuild:
		return "cleaning build stage"
	case actionUpdate:
		return updateflow.CancelingStatus
	case actionGeneric:
		return currentActionSpec.CancelingStatus()
	default:
		return "stopping action"
	}
}

func rootActionCanceledStatus(action actionMode) string {
	switch action {
	case actionBuild:
		return "cleanup complete - good to go"
	case actionUpdate:
		return updateflow.CanceledStatus
	case actionGeneric:
		return currentActionSpec.CanceledStatus()
	default:
		return "action stopped"
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

// Canvas sizing is shared by each responsive view while Bubble Tea renders
// models sequentially on its event loop.
var (
	canvasW = 64
	canvasH = 32
)

const (
	maxCanvasW = 64

	fullCanvasReserveRows = 12
	logCanvasReserveRows  = 31
	modelQualityMinW      = 40
	iconCanvasScale       = 0.82
)

func fitSideIconCanvas(termW, termH int) (int, int, bool) {
	_, rightWidth := sideColumnWidths(termW)
	width, height := fitIconCanvasReserved(rightWidth+4, termH, modelQualityMinW, 4)
	return width, height, width >= modelQualityMinW && height >= modelQualityMinW/2
}

func fitCenteredIconCanvas(termW, termH, reserveRows int) (int, int, bool) {
	width, height := fitIconCanvasReserved(termW, termH, modelQualityMinW, reserveRows)
	return width, height, width >= modelQualityMinW && height >= modelQualityMinW/2
}

func fitCenterStageCanvas(termW, termH, reserveRows int) (int, int, bool) {
	return fitCenteredIconCanvas(termW, termH, reserveRows)
}

func fitIconCanvasReserved(termW, termH int, minW int, reserveRows int) (int, int) {
	return fitIconCanvasReservedWithin(termW, termH, minW, maxCanvasW, reserveRows, iconCanvasScale)
}

func fitIconCanvasReservedWithin(termW, termH, minW, maxW, reserveRows int, scale float64) (int, int) {
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
	if maxW < minW {
		maxW = minW
	}

	w := maxW
	if w > availW {
		w = availW
	}
	if w > availH*2 {
		w = availH * 2
	}

	w = int(math.Round(float64(w) * scale))
	if w < minW {
		w = minW
	}
	if w > maxW {
		w = maxW
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
	if h > maxW/2 {
		h = maxW / 2
	}
	if h > availH {
		h = availH
	}
	return w, h
}

func fitContentWidth(termW int) int {
	width := termW - 4
	if width < 1 {
		return 1
	}
	if width > maxCanvasW {
		return maxCanvasW
	}
	return width
}

func fitLogContentWidth(termW int) int {
	width := termW - 4
	if width < 1 {
		return 1
	}
	if width > logSideRightMax {
		return logSideRightMax
	}
	return width
}

const shadeRamp = " .,:;-+*oO#%@"

type cellStyle uint8

const (
	cellDim cellStyle = iota
	cellGray
	cellMid
	cellBright
	cellWhite
	cellRed
	cellHot
	cellDeepRed
	cellStyleCount
)

var renderedRamp = func() [cellStyleCount][len(shadeRamp)]string {
	styles := [...]lipgloss.Style{
		sDim,
		sGray,
		sMid,
		sBright,
		sWhite,
		sRed,
		sHot,
		sDeepRed,
	}
	var rendered [cellStyleCount][len(shadeRamp)]string
	for style := cellStyle(0); style < cellStyleCount; style++ {
		for shade := 1; shade < len(shadeRamp); shade++ {
			rendered[style][shade] = styles[style].Render(string(shadeRamp[shade]))
		}
	}
	return rendered
}()

var maxRenderedCellBytes = func() int {
	maxBytes := 1
	for style := cellStyle(0); style < cellStyleCount; style++ {
		for shade := 1; shade < len(shadeRamp); shade++ {
			if size := len(renderedRamp[style][shade]); size > maxBytes {
				maxBytes = size
			}
		}
	}
	return maxBytes
}()

type cell struct {
	shade uint8
	style cellStyle
}

type angleSample struct {
	angle  float64
	cosine float64
	sine   float64
}

func periodicAngleSamples(count int) []angleSample {
	samples := make([]angleSample, count)
	for index := range samples {
		angle := float64(index) / float64(count) * 2 * math.Pi
		samples[index] = angleSample{
			angle:  angle,
			cosine: math.Cos(angle),
			sine:   math.Sin(angle),
		}
	}
	return samples
}

func inclusiveAngleSamples(count int, start, span float64) []angleSample {
	samples := make([]angleSample, count)
	for index := range samples {
		angle := start
		if count > 1 {
			angle += float64(index) / float64(count-1) * span
		}
		samples[index] = angleSample{
			angle:  angle,
			cosine: math.Cos(angle),
			sine:   math.Sin(angle),
		}
	}
	return samples
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
func (sc *scene) phongGray(nrx, nry, nrz float64) (uint8, cellStyle) {
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

	shade := shadeForBrightness(brightness)

	var style cellStyle
	switch {
	case brightness > 0.93:
		style = cellWhite
	case brightness > 0.70:
		style = cellBright
	case brightness > 0.48:
		style = cellMid
	case brightness > 0.26:
		style = cellGray
	default:
		style = cellDim
	}
	return shade, style
}

func shadeForBrightness(brightness float64) uint8 {
	shade := int(brightness * float64(len(shadeRamp)-1))
	if shade < 0 {
		return 0
	}
	if shade >= len(shadeRamp) {
		return uint8(len(shadeRamp) - 1)
	}
	return uint8(shade)
}

// plotGray = project → phongGray → commit for one world point+normal.
func (sc *scene) plotGray(wx, wy, wz, nx, ny, nz float64) {
	idx, nrx, nry, nrz, ok := sc.project(wx, wy, wz, nx, ny, nz)
	if !ok {
		return
	}
	shade, style := sc.phongGray(nrx, nry, nrz)
	sc.grid[idx] = cell{shade: shade, style: style}
}

// String renders the grid from cached ANSI tokens. A frame has thousands of
// styled cells, but only a small fixed set of shade/style combinations.
func (sc *scene) String() string {
	var sb strings.Builder
	sb.Grow(canvasH * (canvasW*maxRenderedCellBytes + 1))
	for y := 0; y < canvasH; y++ {
		for x := 0; x < canvasW; x++ {
			c := sc.grid[y*canvasW+x]
			if c.shade == 0 {
				sb.WriteRune(' ')
			} else {
				sb.WriteString(renderedRamp[c.style][c.shade])
			}
		}
		if y < canvasH-1 {
			sb.WriteRune('\n')
		}
	}
	return sb.String()
}

// -- CORE: bloom — animated displaced sphere --

const (
	bloomUN  = 240
	bloomVN  = 72
	bloomShn = 18.0
)

var (
	bloomThetaSamples = periodicAngleSamples(bloomUN)
	bloomPhiSamples   = inclusiveAngleSamples(bloomVN, -math.Pi/2, math.Pi)
)

func renderModelRole(role modelRole, frame int) string {
	switch role {
	case modelThreeRings:
		return renderKnot(frame)
	case modelTwoRings:
		return renderHopf(frame)
	case modelOneRing:
		return renderTorus(frame)
	default:
		return renderBloom(frame)
	}
}

func renderBloom(frame int) string {
	motion := animationFrame(frame)
	t := motion * 0.018
	sc := newScene(sceneCfg{
		aY:  motion * 0.011,
		aX:  motion * 0.005,
		fit: 1.34,
		shn: bloomShn,
		lx:  -0.45, ly: -0.55, lz: 0.71,
	})

	pulseRaw := math.Sin(t * 2.4)
	pulse := 0.35 + 0.65*pulseRaw*pulseRaw

	for _, thetaSample := range bloomThetaSamples {
		theta := thetaSample.angle
		cth, sth := thetaSample.cosine, thetaSample.sine

		for _, phiSample := range bloomPhiSamples {
			phi := phiSample.angle
			cph, sph := phiSample.cosine, phiSample.sine

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

			shade := shadeForBrightness(brightness)

			var style cellStyle
			switch {
			case heat > 0.70:
				style = cellHot
			case heat > 0.40:
				style = cellRed
			case thin > 0.55:
				style = cellRed
			case thin > 0.25:
				style = cellDeepRed
			case brightness > 0.93:
				style = cellWhite
			case brightness > 0.70:
				style = cellBright
			case brightness > 0.48:
				style = cellMid
			case brightness > 0.26:
				style = cellGray
			default:
				style = cellDim
			}
			sc.grid[idx] = cell{shade: shade, style: style}
		}
	}
	return sc.String()
}

// -- one ring: torus --

const (
	torusR   = 1.00
	torusRr  = 0.32
	torusUN  = 256
	torusVN  = 72
	torusShn = 22.0
)

var (
	torusUSamples = periodicAngleSamples(torusUN)
	torusVSamples = periodicAngleSamples(torusVN)
)

func renderTorus(frame int) string {
	motion := animationFrame(frame)
	sc := newScene(sceneCfg{
		aY:  motion * 0.010,
		aX:  motion * 0.013,
		fit: torusR + torusRr,
		shn: torusShn,
		lx:  0.50, ly: -0.55, lz: 0.67,
	})

	for _, u := range torusUSamples {
		cu, su := u.cosine, u.sine
		for _, v := range torusVSamples {
			cv, sv := v.cosine, v.sine

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

// -- three rings: trefoil knot tubular surface --

const (
	knotCurveN = 520
	knotRingN  = 34
	knotR      = 0.42
	knotTube   = 0.36
	knotShn    = 18.0
)

var knotRingSamples = periodicAngleSamples(knotRingN)

func knotPos(t float64) (x, y, z float64) {
	r := 2 + math.Cos(3*t)
	return knotR * r * math.Cos(2*t),
		knotR * r * math.Sin(2*t),
		knotR * math.Sin(3*t)
}

func renderKnot(frame int) string {
	motion := animationFrame(frame)
	sc := newScene(sceneCfg{
		aY:  motion * 0.011,
		aX:  motion * 0.008,
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

		for _, ring := range knotRingSamples {
			ct, st := ring.cosine, ring.sine

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

// -- two rings: Hopf link (two interlocked rings) --

const (
	hopfUN     = 200
	hopfVN     = 52
	hopfR      = 0.60
	hopfRr     = 0.25
	hopfShn    = 22.0
	hopfOffset = 0.30
)

var (
	hopfUSamples = periodicAngleSamples(hopfUN)
	hopfVSamples = periodicAngleSamples(hopfVN)
)

func renderHopf(frame int) string {
	motion := animationFrame(frame)
	sc := newScene(sceneCfg{
		aY:  motion * 0.010,
		aX:  motion * 0.012,
		fit: 1.20,
		shn: hopfShn,
		lx:  -0.48, ly: -0.52, lz: 0.71,
	})

	// Ring A: XY plane at (-offset, 0, 0); hole along +Z.
	for _, u := range hopfUSamples {
		cu, su := u.cosine, u.sine
		for _, v := range hopfVSamples {
			cv, sv := v.cosine, v.sine
			sc.plotGray(
				-hopfOffset+(hopfR+hopfRr*cv)*cu,
				(hopfR+hopfRr*cv)*su,
				hopfRr*sv,
				cv*cu, cv*su, sv,
			)
		}
	}
	// Ring B: XZ plane at (+offset, 0, 0); hole along +Y — links Ring A.
	for _, u := range hopfUSamples {
		cu, su := u.cosine, u.sine
		for _, v := range hopfVSamples {
			cv, sv := v.cosine, v.sine
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
	if sourcePath := omarchySourcePath(); sourcePath != "" {
		candidates = append(candidates, filepath.Join(sourcePath, "qv", "tui", scriptName))
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

func findBuildScript() (string, error) {
	return findRootScript(actionBuild)
}

func rootScriptSpec(action actionMode) (scriptName string, envName string, err error) {
	switch action {
	case actionBuild:
		return "bin/qvos-build", "QVOS_BUILD_SCRIPT", nil
	case actionUpdate:
		return updateflow.ScriptPath, updateflow.ScriptEnvironment, nil
	case actionGeneric:
		return actionflow.ScriptPath, actionflow.ScriptEnvironment, nil
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
	if !info.Mode().IsRegular() {
		return fmt.Errorf("%s is not a regular file", path)
	}
	return nil
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
	return trimDisplay(text, 42)
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

func stopActiveScript(m model) {
	if !m.scriptRunning || m.scriptCancel == nil {
		return
	}

	m.scriptCancel()
	if m.scriptEvents == nil {
		return
	}

	timer := time.NewTimer(35 * time.Second)
	defer timer.Stop()
	for {
		select {
		case event, ok := <-m.scriptEvents:
			if !ok || event.done {
				return
			}
		case <-timer.C:
			return
		}
	}
}

func dedicatedUpdateExitCode(m model) int {
	if m.updateCanceled || m.scriptCanceled {
		return 130
	}
	if m.scriptErr != nil {
		return 1
	}
	return 0
}

func runDedicatedUpdate() int {
	initial, _ := (model{}).beginUpdateConfirmation(true)
	result, err := newTUIProgram(initial).Run()
	final, ok := result.(model)
	interrupted := ok && final.scriptRunning
	if interrupted {
		stopActiveScript(final)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	if !ok {
		fmt.Fprintln(os.Stderr, "qvOS Update returned an unexpected TUI model")
		return 1
	}
	if interrupted {
		return 130
	}
	return dedicatedUpdateExitCode(final)
}

func runDedicatedAction() int {
	spec, err := actionflow.FromEnvironment()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	initial, _ := (model{}).beginGenericAction(spec, true)
	result, err := newTUIProgram(initial).Run()
	final, ok := result.(model)
	interrupted := ok && final.scriptRunning
	if interrupted {
		stopActiveScript(final)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if !ok {
		fmt.Fprintln(os.Stderr, "qvOS action returned an unexpected TUI model")
		return 1
	}
	if interrupted {
		return 130
	}
	return dedicatedUpdateExitCode(final)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--source-hash" {
		fmt.Println(buildSourceHash)
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "--update" {
		os.Exit(runDedicatedUpdate())
	}
	if len(os.Args) > 1 && os.Args[1] == "--action" {
		os.Exit(runDedicatedAction())
	}
	if len(os.Args) > 1 && os.Args[1] == "--prototype" {
		if err := runPrototype(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
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

	if err := validateHubCatalog(sections); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	p := newTUIProgram(model{})
	result, err := p.Run()
	if final, ok := result.(model); ok {
		stopActiveScript(final)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
