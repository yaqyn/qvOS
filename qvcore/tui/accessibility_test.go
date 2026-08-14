package main

import (
	"errors"
	"fmt"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	actionflow "github.com/yaqyn/qvOS/action"
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
	closedRow, closedColumn := textPosition(content, "UPDATING")

	m.logOverlay = true
	content = stripANSI(m.View().Content)
	if !strings.Contains(content, "ctrl+c/z stop options") {
		t.Fatalf("open log view lost the primary action: %q", content)
	}
	if !strings.Contains(content, "f1 help") {
		t.Fatalf("open log view moved or hid Help from the stable action pane: %q", content)
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
	openRow, openColumn := textPosition(content, "UPDATING")
	if openRow != closedRow || openColumn != closedColumn {
		t.Fatalf(
			"opening side logs moved progress from %d:%d to %d:%d",
			closedRow,
			closedColumn,
			openRow,
			openColumn,
		)
	}
}

func TestStopConfirmationTemporarilyReplacesTheSideLog(t *testing.T) {
	m := model{
		width:             140,
		height:            31,
		loading:           true,
		action:            actionUpdate,
		scriptRunning:     true,
		scriptProgress:    0.38,
		scriptTarget:      0.68,
		scriptLogLines:    []string{"downloading package metadata"},
		logOverlay:        true,
		updateStopConfirm: true,
	}

	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"STOP UPDATE?",
		"Update keeps running until you confirm",
		"Keep Updating",
		"Stop Update",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("full-view stop confirmation is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{
		"downloading package metadata",
		"ctrl+v",
		"qvOS",
		"38%",
		"UPDATING",
		"f1",
	} {
		if strings.Contains(content, hidden) {
			t.Fatalf("full-view stop confirmation retained %q: %q", hidden, content)
		}
	}

	next, command := m.Update(tea.KeyPressMsg{Code: tea.KeyF1})
	m = next.(model)
	if command != nil || m.helpOverlay || !m.updateStopConfirm {
		t.Fatal("Help replaced the active stop decision")
	}
}

func TestEmptyRunningLogsUsePreparingInsteadOfWaitingCopy(t *testing.T) {
	tests := []struct {
		name string
		view tea.View
	}{
		{
			name: "action terminal",
			view: (model{
				width: 120, height: 42, loading: true, action: actionUpdate,
				scriptRunning: true, terminalView: true, frame: preparingFrameStep * 2,
			}).View(),
		},
		{
			name: "prototype terminal",
			view: (prototypeSessionModel{
				width: 120, height: 42, running: true, terminalView: true,
				frame: preparingFrameStep * 2,
			}).View(),
		},
		{
			name: "ISO logs",
			view: (isoProgressModel{
				width: 120, height: 42, logOverlay: true,
				frame: preparingFrameStep * 2,
			}).View(),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			content := stripANSI(test.view.Content)
			if !strings.Contains(content, "Preparing..") {
				t.Fatalf("empty running log is missing Preparing animation: %q", content)
			}
			if strings.Contains(strings.ToLower(content), "waiting for") {
				t.Fatalf("empty running log retained waiting copy: %q", content)
			}
		})
	}
}

func TestFullscreenLogsReplaceModelsWithoutMovingProgress(t *testing.T) {
	const (
		width  = 160
		height = 50
	)

	tests := []struct {
		name       string
		title      string
		logLine    string
		closedView tea.View
		openView   tea.View
	}{
		{
			name:    "action",
			title:   "UPDATING",
			logLine: "fullscreen action log",
			closedView: (model{
				width: width, height: height, fullscreen: true, loading: true,
				action: actionUpdate, scriptRunning: true, scriptProgress: 0.38,
				scriptTarget: 0.38, scriptStatus: "updating qvOS",
			}).View(),
			openView: (model{
				width: width, height: height, fullscreen: true, loading: true,
				action: actionUpdate, scriptRunning: true, scriptProgress: 0.38,
				scriptTarget: 0.38, scriptStatus: "updating qvOS",
				scriptLogLines: []string{"fullscreen action log"}, logOverlay: true,
			}).View(),
		},
		{
			name:    "prototype",
			title:   "RUN SCRIPT",
			logLine: "fullscreen prototype log",
			closedView: (prototypeSessionModel{
				width: width, height: height, fullscreen: true, running: true,
				profile: prototypeProfileFor(prototypeScript), progress: 0.38,
			}).View(),
			openView: (prototypeSessionModel{
				width: width, height: height, fullscreen: true, running: true,
				profile: prototypeProfileFor(prototypeScript), progress: 0.38,
				logLines: []string{"fullscreen prototype log"}, logOverlay: true,
			}).View(),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			closed := stripANSI(test.closedView.Content)
			open := stripANSI(test.openView.Content)
			closedRow, closedColumn := textPosition(closed, test.title)
			openRow, openColumn := textPosition(open, test.title)
			if closedRow < 0 || openRow < 0 {
				t.Fatalf("progress title %q is missing", test.title)
			}
			if openRow != closedRow || openColumn != closedColumn {
				t.Fatalf(
					"opening fullscreen logs moved %q from %d:%d to %d:%d",
					test.title,
					closedRow,
					closedColumn,
					openRow,
					openColumn,
				)
			}
			logRow, _ := textPosition(open, test.logLine)
			if logRow < 0 {
				t.Fatalf("fullscreen log did not replace the model: %q", open)
			}
			if logRow >= openRow {
				t.Fatalf("fullscreen log rendered below progress instead of in the model slot")
			}
			assertViewFits(t, test.openView.Content, width, height)
		})
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

	installer := isoInstallerModel{step: isoStepAccount, accountFocus: isoAccountPassword}
	nextInstaller, _ := installer.Update(tea.KeyPressMsg{Code: '?', Text: "?"})
	installer = nextInstaller.(isoInstallerModel)
	if installer.helpOverlay || string(installer.password) != "?" {
		t.Fatalf("ISO password question mark = %q, help = %t", string(installer.password), installer.helpOverlay)
	}
	nextInstaller, _ = installer.Update(tea.KeyPressMsg{Code: tea.KeyF1})
	if !nextInstaller.(isoInstallerModel).helpOverlay {
		t.Fatal("F1 did not open help from the ISO password field")
	}
}

func TestAuthorizationInputReplacesTheRailWithAnAlwaysCenteredMask(t *testing.T) {
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
			empty := stripANSI(renderPasswordField(nil, test.mode))
			if strings.Count(empty, "─") != test.width {
				t.Fatalf("empty authorization rail = %q", empty)
			}

			for count := 1; count <= 3; count++ {
				password := []rune(strings.Repeat("x", count))
				field := renderPasswordField(password, test.mode)
				content := stripANSI(field)
				if strings.Contains(content, "x") {
					t.Fatal("authorization field rendered the password as plaintext")
				}
				if strings.Contains(content, "─") {
					t.Fatalf("typed authorization retained the empty rail: %q", content)
				}
				if strings.Count(content, "•") != count {
					t.Fatalf("authorization mask count = %q", content)
				}
				if got := lipgloss.Width(field); got != count {
					t.Fatalf("authorization mask width = %d, want %d", got, count)
				}
			}

			field := stripANSI(renderPasswordField([]rune("secret"), test.mode))
			for _, retired := range []string{"▐", "▌", "▏"} {
				if strings.Contains(field, retired) {
					t.Fatalf("authorization field restored retired decoration %q: %q", retired, field)
				}
			}
		})
	}

	previousCanvasWidth := canvasW
	canvasW = 30
	t.Cleanup(func() {
		canvasW = previousCanvasWidth
	})
	for _, test := range tests {
		t.Run(test.name+" centered", func(t *testing.T) {
			for _, count := range []int{1, 2, 3, test.width, test.width + 5} {
				content := stripANSI(renderAuthorizationScreen(authorizationScreen{
					Summary:  "Update qvOS",
					Password: []rune(strings.Repeat("x", count)),
				}, test.mode))
				found := false
				visibleCount := min(count, test.width)
				for _, line := range strings.Split(content, "\n") {
					if !strings.Contains(line, "•") {
						continue
					}
					found = true
					if got, want := strings.Index(line, "•"), (canvasW-visibleCount)/2; got != want {
						t.Fatalf(
							"%d-character input starts at %d, want centered column %d: %q",
							count,
							got,
							want,
							line,
						)
					}
				}
				if !found {
					t.Fatalf("%d-character mask is missing: %q", count, content)
				}
			}
		})
	}
}

func TestAuthorizationUsesGenericTitleAndSpacedUnlabeledSummary(t *testing.T) {
	previousCanvasWidth := canvasW
	canvasW = 48
	t.Cleanup(func() {
		canvasW = previousCanvasWidth
	})

	for _, mode := range []layoutMode{layoutDesktop, layoutTablet, layoutMobile} {
		t.Run(fmt.Sprint(mode), func(t *testing.T) {
			content := stripANSI(renderAuthorizationScreen(authorizationScreen{
				Summary:  "Update qvOS and system packages",
				Password: []rune("secret"),
			}, mode))
			lines := strings.Split(content, "\n")
			titleRow := -1
			fieldRow := -1
			summaryRow := -1
			for index, line := range lines {
				switch {
				case strings.Contains(line, "Auth Required"):
					titleRow = index
				case strings.Contains(line, "••••••"):
					fieldRow = index
				case strings.Contains(line, "Update qvOS and system packages"):
					summaryRow = index
				}
			}
			if titleRow < 0 || fieldRow != titleRow+2 || summaryRow != fieldRow+2 {
				t.Fatalf("authorization spacing is incorrect: %q", content)
			}
			for _, redundant := range []string{
				"qvOS Update",
				"Details:",
				"AUTHORIZATION",
				"sudo password required",
				"Begin",
				"Cancel",
			} {
				if strings.Contains(content, redundant) {
					t.Fatalf("authorization retained redundant copy %q: %q", redundant, content)
				}
			}
			for _, retired := range []string{"▐", "▌"} {
				if strings.Contains(content, retired) {
					t.Fatalf("authorization view restored retired bracket %q: %q", retired, content)
				}
			}
		})
	}

	m := model{
		width:      140,
		height:     31,
		loading:    true,
		action:     actionUpdate,
		sudoPrompt: true,
	}
	view := m.View()
	assertViewFits(t, view.Content, m.width, m.height)
}

func TestAuthorizationWrapsLongSummariesWithoutTruncationOrOrphans(t *testing.T) {
	previousCanvasWidth := canvasW
	canvasW = 48
	t.Cleanup(func() {
		canvasW = previousCanvasWidth
	})

	for _, test := range []struct {
		name    string
		summary string
		want    []string
	}{
		{
			name:    "fingerprint",
			summary: "Remove fingerprint authentication and its packages",
			want:    []string{"Remove fingerprint authentication and", "its packages"},
		},
		{
			name:    "FIDO2",
			summary: "Remove FIDO2 authentication and its packages",
			want:    []string{"Remove FIDO2 authentication and", "its packages"},
		},
	} {
		for _, mode := range []layoutMode{layoutDesktop, layoutTablet, layoutMobile} {
			t.Run(test.name+" "+fmt.Sprint(mode), func(t *testing.T) {
				content := stripANSI(renderAuthorizationScreen(authorizationScreen{
					Summary: test.summary,
				}, mode))
				if strings.Contains(content, "…") {
					t.Fatalf("authorization summary was truncated: %q", content)
				}
				for _, line := range test.want {
					if !strings.Contains(content, line) {
						t.Fatalf("authorization summary is missing wrapped line %q: %q", line, content)
					}
				}
			})
		}
	}

	previousSpec := currentActionSpec
	t.Cleanup(func() {
		currentActionSpec = previousSpec
	})
	currentActionSpec = actionflow.Spec{
		Summary:      "Remove fingerprint authentication and its packages",
		RequiresSudo: true,
	}
	m := model{
		height:     30,
		loading:    true,
		action:     actionGeneric,
		sudoPrompt: true,
	}
	if got, want := m.reducedMiddleRows(layoutTablet), 6; got != want {
		t.Fatalf("wrapped authorization rows = %d, want %d", got, want)
	}
}

func TestAuthorizationKeepsActionIdentityWithTheModelAcrossConsumers(t *testing.T) {
	previousCanvasWidth, previousCanvasHeight := canvasW, canvasH
	canvasW, canvasH = 48, 20
	t.Cleanup(func() {
		canvasW, canvasH = previousCanvasWidth, previousCanvasHeight
	})

	update := model{
		width:      72,
		height:     30,
		loading:    true,
		action:     actionUpdate,
		sudoPrompt: true,
	}
	for name, test := range map[string]struct {
		rendered string
		model    string
	}{
		"centered desktop": {update.renderDesktopBody("MODEL"), "MODEL"},
		"centered tablet":  {update.renderReducedBody(layoutTablet, "MODEL"), "MODEL"},
		"side":             {update.renderSideBody(140, 31), ""},
	} {
		t.Run(name, func(t *testing.T) {
			content := stripANSI(test.rendered)
			for _, expected := range []string{"qvOS", "UPDATE", "Auth Required", test.model} {
				if expected == "" {
					continue
				}
				if !strings.Contains(content, expected) {
					t.Fatalf("authorization identity is missing %q: %q", expected, content)
				}
			}
			if strings.Contains(content, "· · · · ·") {
				t.Fatalf("active authorization retained the anonymous hub mark: %q", content)
			}
		})
	}

	prototype := prototypeSessionModel{
		profile: prototypeProfileFor(prototypeSudo),
	}
	content := stripANSI(prototype.renderBody(layoutDesktop, "MODEL"))
	for _, expected := range []string{"MODEL", "qvOS", "PROTOTYPE / SYSTEM", "Auth Required"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("prototype authorization identity is missing %q: %q", expected, content)
		}
	}
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
			if !strings.Contains(content, "Auth Required") ||
				!strings.Contains(content, "password required") {
				t.Fatalf("mobile authorization hid its error: %q", content)
			}
			if strings.Contains(content, "Details:") {
				t.Fatalf("mobile authorization restored the summary label: %q", content)
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
		"start confirmation": (model{
			width: width, height: height,
			loading: true, action: actionBuild, startConfirm: true,
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

func TestBootSurfacesKeepOnlyTheRequestedPersistentHint(t *testing.T) {
	for _, step := range []isoStep{
		isoStepRegional,
		isoStepAccount,
		isoStepDisk,
	} {
		content := stripANSI((isoInstallerModel{step: step, width: 90, height: 30}).View().Content)
		for _, hidden := range []string{"ctrl+c", "ctrl+z", "f1 help"} {
			if strings.Contains(strings.ToLower(content), hidden) {
				t.Fatalf("ISO step %d retained persistent %q copy: %q", step, hidden, content)
			}
		}
	}
	styledProgress := (isoProgressModel{
		width: 140, height: 31, status: "installing qvOS", progress: 0.4,
	}).View().Content
	progress := stripANSI(styledProgress)
	for _, hidden := range []string{"INSTALLING QVOS", "v log", "ctrl+v terminal"} {
		if strings.Contains(progress, hidden) {
			t.Fatalf("ISO progress retained %q clutter: %q", hidden, progress)
		}
	}
	if !strings.Contains(styledProgress, sDim.Render("Estimated 4:00  -  ? Help")) {
		t.Fatalf("ISO progress is missing its dim estimate and Help footer: %q", styledProgress)
	}

	finale := stripANSI((isoFinishedModel{width: 90, height: 28}).View().Content)
	for _, hidden := range []string{"help", "enter", "INSTALLED", "REBOOT NOW"} {
		if strings.Contains(finale, hidden) {
			t.Fatalf("ISO finale retained %q clutter: %q", hidden, finale)
		}
	}
	for _, expected := range []string{"Finished", "Reboot"} {
		if !strings.Contains(finale, expected) {
			t.Fatalf("ISO finale is missing %q: %q", expected, finale)
		}
	}
}

func TestISOProgressReplacesTheRailWithOneSimpleLogView(t *testing.T) {
	m := newISOProgressModel("/tmp/qvos-output-only-progress", true)
	m.width, m.height = 140, 31
	m.logLines = []string{"real installer output"}
	initial := stripANSI(m.View().Content)
	for _, expected := range []string{"preparing installation", "0%", "Estimated 4:00", "? Help"} {
		if !strings.Contains(initial, expected) {
			t.Fatalf("progress is missing %q: %q", expected, initial)
		}
	}

	next, command := m.Update(tea.KeyPressMsg{Code: 'v', Text: "v"})
	m = next.(isoProgressModel)
	if command != nil || !m.logOverlay {
		t.Fatalf("v did not replace progress with logs: %#v", m)
	}
	logs := stripANSI(m.View().Content)
	for _, expected := range []string{"real installer output", "Estimated 4:00", "? Help"} {
		if !strings.Contains(logs, expected) {
			t.Fatalf("simple log view is missing %q: %q", expected, logs)
		}
	}
	for _, hidden := range []string{"preparing installation", "0%", "TERMINAL", "ctrl+v", tuiRailGlyph} {
		if strings.Contains(logs, hidden) {
			t.Fatalf("simple log view retained %q: %q", hidden, logs)
		}
	}

	next, command = m.Update(tea.KeyPressMsg{Code: 'v', Mod: tea.ModCtrl})
	m = next.(isoProgressModel)
	if command != nil || !m.logOverlay {
		t.Fatalf("Ctrl+V changed the boot log view: %#v", m)
	}

	for _, hint := range m.helpHints() {
		text := strings.ToLower(hint.Key + " " + hint.Action)
		if strings.Contains(text, "terminal") || strings.Contains(text, "ctrl+v") {
			t.Fatalf("ISO logs retained an obsolete control: %#v", hint)
		}
	}

	next, command = m.Update(tea.KeyPressMsg{Code: 'v', Text: "v"})
	m = next.(isoProgressModel)
	if command != nil || m.logOverlay {
		t.Fatalf("v did not return to progress: %#v", m)
	}

	helpModel := newISOProgressModel("/tmp/qvos-output-only-progress", true)
	next, command = helpModel.Update(tea.KeyPressMsg{Code: '?', Text: "?"})
	if command != nil || !next.(isoProgressModel).helpOverlay {
		t.Fatal("ISO progress Help shortcut stopped working")
	}
}

func TestLogOutputScrollsAndReturnsToFollowingTheNewestLine(t *testing.T) {
	var lines []string
	for index := 0; index < 30; index++ {
		lines = append(lines, fmt.Sprintf("log line %02d", index))
	}
	m := model{
		width:           140,
		height:          31,
		loading:         true,
		action:          actionUpdate,
		scriptRunning:   true,
		scriptLogLines:  lines,
		scriptLogCursor: len(lines),
		logOverlay:      true,
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
		action:         actionUpdate,
		line:           "log line 30",
		output:         true,
		commit:         true,
		terminalUpdate: true,
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

func TestPrototypeFullTerminalOffersFullLogCopy(t *testing.T) {
	prototype := prototypeSessionModel{
		terminalView: true,
		logLines:     []string{"prototype output"},
	}
	nextPrototype, prototypeCommand := prototype.Update(tea.KeyPressMsg{Code: 'y'})
	if prototypeCommand == nil || nextPrototype.(prototypeSessionModel).logCopyStatus != "copying full log" {
		t.Fatal("prototype terminal did not start full-log copy")
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
		{"start confirmation", (model{startConfirm: true}).rootPersistentHints(), "←→"},
		{"sudo", (model{sudoPrompt: true}).rootPersistentHints(), "enter"},
		{"empty selection", (model{selectionActive: true}).rootPersistentHints(), "enter / esc"},
		{"running update", (model{action: actionUpdate}).rootPersistentHints(), "ctrl+c/z"},
		{"failed action", (model{scriptErr: fmt.Errorf("failed")}).rootPersistentHints(), "r"},
		{"completed action", (model{scriptDone: true}).rootPersistentHints(), "enter"},
		{"terminal output", tuiTerminalPersistentHints(), "ctrl+v"},
		{"prototype hub", (prototypeHubModel{}).persistentHints(), "↑↓"},
		{"prototype sudo", (prototypeSessionModel{
			profile: prototypeProfileFor(prototypeSudo),
		}).persistentHints(), "enter"},
		{"prototype running", (prototypeSessionModel{}).persistentHints(), "esc"},
		{"prototype failure", (prototypeSessionModel{failed: true}).persistentHints(), "r"},
		{"prototype complete", (prototypeSessionModel{done: true}).persistentHints(), "enter"},
		{"prototype terminal", tuiTerminalPersistentHints(), "ctrl+v"},
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

func TestCompletedResultLogKeysKeepTheResultAvailable(t *testing.T) {
	m := model{
		width:          140,
		height:         31,
		loading:        true,
		action:         actionUpdate,
		scriptDone:     true,
		scriptLogLines: []string{"completed owner output"},
	}
	if content := stripANSI(m.View().Content); strings.Contains(content, "v view logs") {
		t.Fatalf("completed result exposes the known log shortcut persistently: %q", content)
	}

	next, command := m.Update(tea.KeyPressMsg{Code: 'v', Text: "v"})
	if command != nil {
		t.Fatal("v launched a command from the completed result")
	}
	m = next.(model)
	if !m.logOverlay || !m.scriptDone {
		t.Fatal("v did not retain the completed result with its log panel open")
	}
	for _, expected := range []string{"completed owner output", "enter return"} {
		if content := stripANSI(m.View().Content); !strings.Contains(content, expected) {
			t.Fatalf("completed log view is missing %q: %q", expected, content)
		}
	}
	if content := stripANSI(m.View().Content); strings.Contains(content, "v close logs") {
		t.Fatalf("completed log view exposes the known log shortcut persistently: %q", content)
	}

	next, command = m.Update(tea.KeyPressMsg{Code: 'v', Mod: tea.ModCtrl})
	if command != nil {
		t.Fatal("Ctrl+V launched a command from the completed result")
	}
	m = next.(model)
	if !m.terminalView || !m.scriptDone {
		t.Fatal("Ctrl+V did not retain the completed result in full terminal output")
	}
}

func TestISOFinaleRejectsProgressOnlyTerminalShortcuts(t *testing.T) {
	for _, size := range []struct {
		name          string
		width, height int
	}{
		{name: "desktop", width: 140, height: 31},
		{name: "tablet", width: 90, height: 28},
		{name: "mobile", width: 58, height: 24},
	} {
		t.Run(size.name, func(t *testing.T) {
			m := isoFinishedModel{
				width:  size.width,
				height: size.height,
			}

			before := m.View().Content
			assertViewFits(t, m.View().Content, size.width, size.height)
			next, _ := m.Update(tea.KeyPressMsg{Code: tea.KeyF1})
			m = next.(isoFinishedModel)
			if help := stripANSI(m.View().Content); strings.Contains(help, "terminal") || strings.Contains(help, "log") {
				t.Fatalf("ISO finale Help exposes progress-only controls: %q", help)
			}
			next, _ = m.Update(tea.KeyPressMsg{Code: tea.KeyF1})
			m = next.(isoFinishedModel)

			for _, key := range []tea.KeyPressMsg{
				{Code: 'v', Text: "v"},
				{Code: 'v', Mod: tea.ModCtrl},
			} {
				next, command := m.Update(key)
				if command != nil {
					t.Fatal("terminal shortcut launched a command from the ISO finale")
				}
				m = next.(isoFinishedModel)
				if got := m.View().Content; got != before {
					t.Fatalf("terminal shortcut changed the ISO finale: %q", stripANSI(got))
				}
			}
		})
	}
}

func TestISOFinaleUsesAHiddenRebootTimerThatStopsOnInteraction(t *testing.T) {
	automatic := newISOFinishedModel()
	next, command := automatic.Update(isoFinishedRebootMsg{})
	automatic = next.(isoFinishedModel)
	if command == nil || !automatic.allowQuit || automatic.timerStopped {
		t.Fatalf("ISO finale did not complete its untouched reboot timer: %#v", automatic)
	}

	paused := newISOFinishedModel()
	next, command = paused.Update(tea.KeyPressMsg{Code: 'v', Text: "v"})
	paused = next.(isoFinishedModel)
	if command != nil || !paused.timerStopped || paused.allowQuit {
		t.Fatalf("ISO finale interaction did not stop its timer: %#v", paused)
	}
	next, command = paused.Update(isoFinishedRebootMsg{})
	paused = next.(isoFinishedModel)
	if command != nil || paused.allowQuit {
		t.Fatalf("stopped ISO finale timer still rebooted: %#v", paused)
	}

	content := stripANSI((isoFinishedModel{width: 90, height: 28}).View().Content)
	for _, expected := range []string{"Finished", "Reboot"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("ISO finale is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"Welcome to qvOS", "5", "seconds", "timer"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("ISO finale exposed %q: %q", hidden, content)
		}
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

func TestHelpAndTerminalOutputUseTheSharedThinRail(t *testing.T) {
	help := renderTUIHelp(100, "Help", []tuiHint{{Key: "enter", Action: "continue"}})
	helpRail := renderTUIRail(66, sDim)
	if !strings.Contains(help, helpRail) || strings.Contains(help, "━") {
		t.Fatalf("Help retained a separate or heavy separator: %q", help)
	}

	terminal := renderTUITerminalOutput(
		100,
		30,
		"Update",
		[]string{"output"},
		0,
		"",
		"No output",
		[]tuiHint{{Key: "ctrl+v", Action: "return"}},
	)
	terminalRail := renderTUIRail(terminalOutputContentWidth(100), sDim)
	if strings.Count(terminal, terminalRail) != 2 || strings.Contains(terminal, "━") {
		t.Fatalf("terminal output retained separate or heavy separators: %q", terminal)
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

	if hints := (model{updateStopConfirm: true}).rootPersistentHints(); len(hints) != 1 ||
		hints[0] != (tuiHint{Key: "ctrl+c/z", Action: "again stop"}) {
		t.Fatalf("stop modal hints = %#v, want repeated-key stop control", hints)
	}
}

func textPosition(content, text string) (int, int) {
	for row, line := range strings.Split(content, "\n") {
		if column := strings.Index(line, text); column >= 0 {
			return row, column
		}
	}
	return -1, -1
}
