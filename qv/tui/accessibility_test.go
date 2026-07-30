package main

import (
	"errors"
	"fmt"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

func TestUpdateControlsStayVisibleAtTheDefaultSideSize(t *testing.T) {
	m := model{
		width:          140,
		height:         31,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptProgress: 0.38,
		scriptTarget:   0.38,
		scriptStatus:   "updating qvOS",
	}

	content := stripANSI(m.View().Content)
	for _, expected := range []string{"ctrl+c/z", "stop options", "f1 help"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("default Update view is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"v logs", "ctrl+v terminal"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("default Update view exposes secondary action %q: %q", hidden, content)
		}
	}

	m.logOverlay = true
	content = stripANSI(m.View().Content)
	if !strings.Contains(content, "ctrl+c/z stop options") {
		t.Fatalf("open log view lost the primary action: %q", content)
	}
	if strings.Contains(content, "f1 help") {
		t.Fatalf("narrow log progress pane should yield Help to the primary action: %q", content)
	}
	if !strings.Contains(content, "ctrl+v  switch") {
		t.Fatalf("open log view is missing its quiet switch cue: %q", content)
	}
	if strings.Contains(content, "v close logs") {
		t.Fatalf("open log view exposes a secondary action persistently: %q", content)
	}
	if m.View().MouseMode != tea.MouseModeCellMotion {
		t.Fatal("open side log releases the mouse outside full terminal output")
	}
}

func TestTerminalOutputViewUsesTheSameRunningModel(t *testing.T) {
	m := model{
		width:          140,
		height:         31,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptLogLines: []string{"first update line", "latest update line"},
	}

	next, command := m.Update(tea.KeyPressMsg{Code: 'v', Mod: tea.ModCtrl})
	if command != nil {
		t.Fatal("Ctrl+V launched another process instead of changing the current view")
	}
	m = next.(model)
	if !m.terminalView {
		t.Fatal("Ctrl+V did not open terminal output")
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"UPDATE / TERMINAL OUTPUT",
		"first update line",
		"latest update line",
		"ctrl+v switch",
		"f1 help",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("terminal output is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"v logs", "ctrl+c/z stop options"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("terminal output exposes secondary action %q: %q", hidden, content)
		}
	}
	assertViewFits(t, m.View().Content, m.width, m.height)
	if m.View().MouseMode != tea.MouseModeNone {
		t.Fatal("terminal output captures the mouse instead of allowing terminal text selection")
	}

	next, _ = m.Update(tea.KeyPressMsg{Code: 'v'})
	m = next.(model)
	if m.terminalView || !m.logOverlay {
		t.Fatal("v did not return from terminal output with the qvOS log panel open")
	}
}

func TestHelpOverlayDocumentsContextualActions(t *testing.T) {
	m := model{
		width:         140,
		height:        31,
		loading:       true,
		action:        actionUpdate,
		scriptRunning: true,
	}

	next, _ := m.Update(tea.KeyPressMsg{Code: '?', Text: "?"})
	m = next.(model)
	if !m.helpOverlay {
		t.Fatal("Shift+? did not open contextual help")
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"UPDATE CONTROLS",
		"toggle the qvOS log panel",
		"toggle original terminal output",
		"open safe stop options",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("Update help is missing %q: %q", expected, content)
		}
	}
	assertViewFits(t, m.View().Content, m.width, m.height)

	next, _ = m.Update(tea.KeyPressMsg{Code: tea.KeyEscape})
	if next.(model).helpOverlay {
		t.Fatal("Escape did not close contextual help")
	}
}

func TestHelpShortcutsDoNotStealPasswordCharacters(t *testing.T) {
	mainModel := model{
		loading:    true,
		action:     actionUpdate,
		sudoPrompt: true,
	}
	next, _ := mainModel.Update(tea.KeyPressMsg{Code: '?', Text: "?"})
	mainModel = next.(model)
	if mainModel.helpOverlay || string(mainModel.sudoPassword) != "?" {
		t.Fatalf("sudo password question mark = %q, help = %t", string(mainModel.sudoPassword), mainModel.helpOverlay)
	}
	next, _ = mainModel.Update(tea.KeyPressMsg{Code: tea.KeyF1})
	if !next.(model).helpOverlay {
		t.Fatal("F1 did not open help from the sudo prompt")
	}

	installer := isoInstallerModel{step: isoStepPassword}
	nextInstaller, _ := installer.Update(tea.KeyPressMsg{Code: '?', Text: "?"})
	installer = nextInstaller.(isoInstallerModel)
	if installer.helpOverlay || string(installer.input) != "?" {
		t.Fatalf("ISO password question mark = %q, help = %t", string(installer.input), installer.helpOverlay)
	}
	nextInstaller, _ = installer.Update(tea.KeyPressMsg{Code: tea.KeyF1})
	if !nextInstaller.(isoInstallerModel).helpOverlay {
		t.Fatal("F1 did not open help from the ISO password field")
	}
}

func TestAuthorizationInputUsesTheSharedFramelessRail(t *testing.T) {
	tests := []struct {
		name  string
		mode  layoutMode
		width int
	}{
		{"desktop", layoutDesktop, 28},
		{"tablet", layoutTablet, 18},
		{"mobile", layoutMobile, 10},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			field := renderPasswordField([]rune("secret"), test.mode)
			content := stripANSI(field)
			if strings.Contains(content, "secret") {
				t.Fatal("authorization field rendered the password as plaintext")
			}
			for _, retired := range []string{"▐", "▌"} {
				if strings.Contains(content, retired) {
					t.Fatalf("authorization field restored retired bracket %q: %q", retired, content)
				}
			}
			if strings.Contains(content, "▏") {
				t.Fatalf("authorization field restored a decorative cursor: %q", content)
			}
			if strings.Count(content, "•") != len("secret") {
				t.Fatalf("authorization mask is missing: %q", content)
			}
			if got := lipgloss.Width(field); got != test.width {
				t.Fatalf("authorization field width = %d, want %d", got, test.width)
			}
		})
	}
}

func TestAuthorizationTitleBreathesBeforeTheField(t *testing.T) {
	m := model{
		width:      140,
		height:     31,
		loading:    true,
		action:     actionUpdate,
		sudoPrompt: true,
	}
	previousCanvasWidth := canvasW
	canvasW = 48
	content := stripANSI(m.renderSudoPromptFor(layoutTablet))
	canvasW = previousCanvasWidth
	lines := strings.Split(content, "\n")
	titleRow := -1
	for index, line := range lines {
		if strings.Contains(line, "UPDATE AUTHORIZATION") {
			titleRow = index
			break
		}
	}
	if titleRow < 0 {
		t.Fatalf("authorization title is missing: %q", content)
	}
	if titleRow+1 >= len(lines) || strings.TrimSpace(lines[titleRow+1]) != "" {
		t.Fatalf("authorization title has no breathing room: %q", content)
	}
	for _, retired := range []string{"▐", "▌"} {
		if strings.Contains(content, retired) {
			t.Fatalf("authorization view restored retired bracket %q: %q", retired, content)
		}
	}

	view := m.View()
	assertViewFits(t, view.Content, m.width, m.height)
}

func TestMobileAuthorizationShowsErrorsAcrossConsumers(t *testing.T) {
	previousCanvasWidth := canvasW
	canvasW = 30
	t.Cleanup(func() {
		canvasW = previousCanvasWidth
	})

	update := model{
		loading:    true,
		action:     actionUpdate,
		sudoPrompt: true,
		sudoErr:    errors.New("password required"),
	}
	prototype := prototypeSessionModel{
		profile:   prototypeProfileFor(prototypeSudo),
		authError: "password required",
	}
	for name, rendered := range map[string]string{
		"update":    update.renderSudoPromptFor(layoutMobile),
		"prototype": prototype.renderPanel(layoutMobile),
	} {
		t.Run(name, func(t *testing.T) {
			content := stripANSI(rendered)
			if !strings.Contains(content, "password required") {
				t.Fatalf("mobile authorization hid its error: %q", content)
			}
		})
	}
}

func TestEveryTUISurfaceExposesDiscoverableControls(t *testing.T) {
	const (
		width  = 140
		height = 31
	)
	views := map[string]tea.View{
		"hub": (model{
			width: width, height: height,
		}).View(),
		"update confirmation": (model{
			width: width, height: height,
			loading: true, action: actionUpdate, updateConfirm: true,
		}).View(),
		"sudo": (model{
			width: width, height: height,
			loading: true, action: actionUpdate, sudoPrompt: true,
		}).View(),
		"canceled": (model{
			width: width, height: height,
			loading: true, action: actionUpdate, scriptDone: true, scriptCanceled: true,
		}).View(),
		"prototype hub": (prototypeHubModel{
			width: width, height: height,
		}).View(),
		"prototype session": (prototypeSessionModel{
			width: width, height: height,
			profile: prototypeProfileFor(prototypeScript), running: true,
		}).View(),
		"ISO intro": (isoInstallerModel{
			width: width, height: height, step: isoStepIntro,
		}).View(),
		"ISO writing": (isoInstallerModel{
			width: width, height: height, step: isoStepWriting,
		}).View(),
		"ISO progress": (isoProgressModel{
			width: width, height: height, prototype: true, progress: 0.4,
		}).View(),
		"ISO finale": (isoFinishedModel{
			width: width, height: height,
		}).View(),
	}

	for name, view := range views {
		t.Run(name, func(t *testing.T) {
			content := stripANSI(view.Content)
			if !strings.Contains(content, "help") {
				t.Fatalf("%s has no visible help route: %q", name, content)
			}
			assertViewFits(t, view.Content, width, height)
		})
	}
}

func TestLogOutputScrollsAndReturnsToFollowingTheNewestLine(t *testing.T) {
	var lines []string
	for index := 0; index < 30; index++ {
		lines = append(lines, fmt.Sprintf("log line %02d", index))
	}
	m := model{
		width:          140,
		height:         31,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptLogLines: lines,
		logOverlay:     true,
	}

	content := stripANSI(m.View().Content)
	if !strings.Contains(content, "log line 29") || strings.Contains(content, "log line 00") {
		t.Fatalf("log view did not begin at the newest output: %q", content)
	}

	next, command := m.Update(tea.KeyPressMsg{Code: tea.KeyHome})
	if command != nil {
		t.Fatal("log scrolling launched a command")
	}
	m = next.(model)
	content = stripANSI(m.View().Content)
	if !strings.Contains(content, "log line 00") || !strings.Contains(content, "newer") {
		t.Fatalf("Home did not open the oldest retained output: %q", content)
	}

	next, _ = m.Update(scriptEventMsg{event: scriptEvent{
		action: actionUpdate,
		line:   "log line 30",
	}})
	m = next.(model)
	content = stripANSI(m.View().Content)
	if !strings.Contains(content, "log line 00") || strings.Contains(content, "log line 30") {
		t.Fatalf("new output moved a deliberately scrolled viewport: %q", content)
	}

	next, _ = m.Update(tea.KeyPressMsg{Code: tea.KeyEnd})
	m = next.(model)
	content = stripANSI(m.View().Content)
	if !strings.Contains(content, "log line 30") || strings.Contains(content, "newer") {
		t.Fatalf("End did not resume the newest output: %q", content)
	}
}

func TestLogHelpKeepsSelectionAndCopyInFullTerminalOutput(t *testing.T) {
	for _, size := range []struct {
		name          string
		width, height int
	}{
		{"side", 140, 31},
		{"mobile", 44, 18},
	} {
		t.Run(size.name, func(t *testing.T) {
			m := model{
				width:         size.width,
				height:        size.height,
				loading:       true,
				action:        actionUpdate,
				scriptRunning: true,
				logOverlay:    true,
			}

			next, _ := m.Update(tea.KeyPressMsg{Code: '?', Text: "?"})
			view := next.(model).View()
			content := stripANSI(view.Content)
			for _, expected := range []string{
				"scroll lines",
				"scroll pages",
				"oldest / newest",
			} {
				if !strings.Contains(content, expected) {
					t.Fatalf("log help is missing %q: %q", expected, content)
				}
			}
			for _, hidden := range []string{"copy visible text", "copy full log"} {
				if strings.Contains(content, hidden) {
					t.Fatalf("side log help exposes terminal-only action %q: %q", hidden, content)
				}
			}
			assertViewFits(t, view.Content, size.width, size.height)
		})
	}

	m := model{
		width:          140,
		height:         31,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptLogLines: []string{"captured output"},
		terminalView:   true,
	}
	next, _ := m.Update(tea.KeyPressMsg{Code: '?', Text: "?"})
	content := stripANSI(next.(model).View().Content)
	for _, expected := range []string{
		"scroll lines",
		"scroll pages",
		"oldest / newest",
		"copy visible text",
		"copy full log",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("terminal help is missing %q: %q", expected, content)
		}
	}
}

func TestCopyFullLogUsesCapturedOutputOutsideTheVisibleViewport(t *testing.T) {
	var lines []string
	for index := 0; index < 30; index++ {
		lines = append(lines, fmt.Sprintf("log line %02d", index))
	}

	text := tuiLogClipboardText(lines)
	for _, expected := range []string{"log line 00", "log line 29"} {
		if !strings.Contains(text, expected) {
			t.Fatalf("clipboard text is missing offscreen line %q: %q", expected, text)
		}
	}

	m := model{
		width:          140,
		height:         31,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptLogLines: lines,
		terminalView:   true,
	}
	next, command := m.Update(tea.KeyPressMsg{Code: 'y'})
	if command == nil {
		t.Fatal("y did not start full-log copy")
	}
	m = next.(model)
	if m.logCopyStatus != "copying full log" || !m.terminalView {
		t.Fatalf("copy state = %q, terminal = %t", m.logCopyStatus, m.terminalView)
	}

	next, command = m.Update(tuiLogCopiedMsg{})
	if command != nil {
		t.Fatal("copy result launched another command")
	}
	m = next.(model)
	if m.logCopyStatus != "full log copied" {
		t.Fatalf("copy result status = %q", m.logCopyStatus)
	}
	if content := stripANSI(m.View().Content); !strings.Contains(content, "full log copied") {
		t.Fatalf("terminal output does not confirm full-log copy: %q", content)
	}
}

func TestEveryFullTerminalSurfaceOffersFullLogCopy(t *testing.T) {
	prototype := prototypeSessionModel{
		terminalView: true,
		logLines:     []string{"prototype output"},
	}
	nextPrototype, prototypeCommand := prototype.Update(tea.KeyPressMsg{Code: 'y'})
	if prototypeCommand == nil || nextPrototype.(prototypeSessionModel).logCopyStatus != "copying full log" {
		t.Fatal("prototype terminal did not start full-log copy")
	}

	iso := isoProgressModel{
		terminalView: true,
		logLines:     []string{"ISO output"},
	}
	nextISO, isoCommand := iso.Update(tea.KeyPressMsg{Code: 'y'})
	if isoCommand == nil || nextISO.(isoProgressModel).logCopyStatus != "copying full log" {
		t.Fatal("ISO terminal did not start full-log copy")
	}
}

func TestOnlyFullTerminalOutputEnablesNativeSelection(t *testing.T) {
	tests := []struct {
		name     string
		sideView tea.View
		fullView tea.View
	}{
		{
			name: "update",
			sideView: (model{
				width: 140, height: 31, loading: true, action: actionUpdate, logOverlay: true,
			}).View(),
			fullView: (model{
				width: 140, height: 31, loading: true, action: actionUpdate, terminalView: true,
			}).View(),
		},
		{
			name: "prototype",
			sideView: (prototypeSessionModel{
				width: 140, height: 31, logOverlay: true,
			}).View(),
			fullView: (prototypeSessionModel{
				width: 140, height: 31, terminalView: true,
			}).View(),
		},
		{
			name: "ISO progress",
			sideView: (isoProgressModel{
				width: 140, height: 31, logOverlay: true,
			}).View(),
			fullView: (isoProgressModel{
				width: 140, height: 31, terminalView: true,
			}).View(),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if test.sideView.MouseMode != tea.MouseModeCellMotion {
				t.Fatal("side log releases mouse capture")
			}
			if test.fullView.MouseMode != tea.MouseModeNone {
				t.Fatal("full terminal output does not release mouse capture")
			}
		})
	}
}

func TestLogSwitchCueFitsEveryResponsiveShape(t *testing.T) {
	sizes := []struct {
		name          string
		width, height int
	}{
		{"side", 140, 31},
		{"desktop", 120, 42},
		{"tablet", 72, 30},
		{"mobile", 44, 18},
		{"fullscreen", 270, 61},
	}

	for _, size := range sizes {
		t.Run(size.name, func(t *testing.T) {
			view := (model{
				width:          size.width,
				height:         size.height,
				fullscreen:     size.name == "fullscreen",
				loading:        true,
				action:         actionUpdate,
				scriptRunning:  true,
				scriptLogLines: []string{"stable log output"},
				logOverlay:     true,
			}).View()
			if content := stripANSI(view.Content); !strings.Contains(content, "ctrl+v  switch") {
				t.Fatalf("%s log view lost its switch cue: %q", size.name, content)
			}
			assertViewFits(t, view.Content, size.width, size.height)
		})
	}
}

func TestProductionHubShowsOnlyWorkingActions(t *testing.T) {
	content := stripANSI((model{width: 140, height: 31}).View().Content)
	for _, label := range []string{"UPDATE", "BUILD"} {
		if !strings.Contains(content, label) {
			t.Fatalf("production hub lost %s: %q", label, content)
		}
	}
}

func TestPersistentHintsStayToOnePrimaryActionAndHelp(t *testing.T) {
	tests := []struct {
		name       string
		hints      []tuiHint
		primaryKey string
	}{
		{"hub", (model{}).hubPersistentHints(), "↑↓"},
		{"update confirmation", (model{updateConfirm: true}).rootPersistentHints(), "←→"},
		{"stop confirmation", (model{updateStopConfirm: true}).rootPersistentHints(), "←→"},
		{"sudo", (model{sudoPrompt: true}).rootPersistentHints(), "enter"},
		{"running update", (model{action: actionUpdate}).rootPersistentHints(), "ctrl+c/z"},
		{"failed action", (model{scriptErr: fmt.Errorf("failed")}).rootPersistentHints(), "r"},
		{"completed action", (model{scriptDone: true}).rootPersistentHints(), "enter"},
		{"terminal output", (model{}).terminalHints(), "ctrl+v"},
		{"prototype hub", (prototypeHubModel{}).persistentHints(), "↑↓"},
		{"prototype sudo", (prototypeSessionModel{
			profile: prototypeProfileFor(prototypeSudo),
		}).persistentHints(), "enter"},
		{"prototype running", (prototypeSessionModel{}).persistentHints(), "esc"},
		{"prototype failure", (prototypeSessionModel{failed: true}).persistentHints(), "r"},
		{"prototype complete", (prototypeSessionModel{done: true}).persistentHints(), "enter"},
		{"prototype terminal", (prototypeSessionModel{}).terminalHints(), "ctrl+v"},
		{"ISO intro", (isoInstallerModel{step: isoStepIntro}).persistentHints(), "enter"},
		{"ISO writing", (isoInstallerModel{step: isoStepWriting}).persistentHints(), "ctrl+c/z"},
		{"ISO list", (isoInstallerModel{step: isoStepKeyboard}).persistentHints(), "↑↓"},
		{"ISO input", (isoInstallerModel{step: isoStepPassword}).persistentHints(), "enter"},
		{"ISO choice", (isoInstallerModel{step: isoStepReview}).persistentHints(), "←→"},
		{"ISO progress", (isoProgressModel{}).persistentHints(), "v"},
		{"ISO progress complete", (isoProgressModel{
			prototype: true,
			progress:  1,
		}).persistentHints(), "enter"},
		{"ISO terminal", (isoProgressModel{}).terminalHints(), "ctrl+v"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if len(test.hints) != 2 {
				t.Fatalf("persistent hints = %#v, want one primary action and Help", test.hints)
			}
			if test.hints[0].Key != test.primaryKey || test.hints[1] != tuiHelpHint() {
				t.Fatalf(
					"persistent hints = %#v, want primary %q and consistent F1 Help",
					test.hints,
					test.primaryKey,
				)
			}
			if test.hints[1].Action != "help" {
				t.Fatalf("second hint = %#v, want Help", test.hints[1])
			}
			if test.name == "prototype running" && test.hints[0].Action != "cancel" {
				t.Fatalf("running prototype primary hint = %#v, want cancel", test.hints[0])
			}
		})
	}
}

func TestHintRendererWrapsWithoutHidingActions(t *testing.T) {
	hints := []tuiHint{
		{Key: "ctrl+c/z", Action: "stop options"},
		{Key: "v", Action: "close logs"},
		{Key: "ctrl+v", Action: "terminal"},
		tuiHelpHint(),
	}
	for _, width := range []int{24, 40, 72} {
		t.Run(fmt.Sprintf("width-%d", width), func(t *testing.T) {
			rendered := renderTUIHints(width, hints...)
			content := stripANSI(rendered)
			for _, expected := range []string{"ctrl+c/z", "v close logs", "ctrl+v terminal", "f1 help"} {
				if !strings.Contains(content, expected) {
					t.Fatalf("width %d is missing %q: %q", width, expected, content)
				}
			}
			for index, line := range strings.Split(rendered, "\n") {
				if got := lipgloss.Width(line); got > width {
					t.Fatalf("line %d width = %d, want <= %d", index, got, width)
				}
			}
		})
	}
}

func TestHelpHintUsesQuietDimGray(t *testing.T) {
	rendered := renderTUIHints(72,
		tuiHint{Key: "enter", Action: "return"},
		tuiHelpHint(),
	)
	dimHelp := sDim.Render("f1") + " " + sDim.Render("help")
	if !strings.Contains(rendered, dimHelp) {
		t.Fatalf("Help hint is not dim gray: %q", rendered)
	}
	if strings.Contains(rendered, sHot.Render("f1")) {
		t.Fatalf("Help key retained the red primary style: %q", rendered)
	}
}

func TestCompactPersistentHintsKeepOnlyThePrimaryAction(t *testing.T) {
	const width = 24
	rendered := stripANSI(centerTUIHints(width,
		tuiHint{Key: "ctrl+c/z", Action: "stop options"},
		tuiHelpHint(),
	))

	lines := strings.Split(rendered, "\n")
	if len(lines) != 1 {
		t.Fatalf("compact hint lines = %d, want 1: %q", len(lines), rendered)
	}
	if strings.Contains(rendered, "help") || !strings.Contains(rendered, "ctrl+c/z stop options") {
		t.Fatalf("compact hints did not preserve only the primary action: %q", rendered)
	}
	content := strings.TrimSpace(lines[0])
	wantLeft := (width - lipgloss.Width(content)) / 2
	if gotLeft := strings.Index(lines[0], content); gotLeft != wantLeft {
		t.Fatalf("primary hint left margin = %d, want %d: %q", gotLeft, wantLeft, lines[0])
	}
}

func TestCenteredHintsRemainEmptyWithoutActions(t *testing.T) {
	if rendered := centerTUIHints(24); rendered != "" {
		t.Fatalf("empty centered hints = %q, want no phantom padding", rendered)
	}
}

func assertViewFits(t *testing.T, content string, width int, height int) {
	t.Helper()
	lines := strings.Split(content, "\n")
	if len(lines) > height {
		t.Fatalf("view height = %d, terminal height = %d", len(lines), height)
	}
	for index, line := range lines {
		if got := lipgloss.Width(line); got > width {
			t.Fatalf("line %d width = %d, terminal width = %d", index, got, width)
		}
	}
}
