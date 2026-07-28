package main

import (
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
	for _, expected := range []string{"ctrl+c/z", "stop options", "v logs", "ctrl+v terminal", "? help"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("default Update view is missing %q: %q", expected, content)
		}
	}

	m.logOverlay = true
	content = stripANSI(m.View().Content)
	if !strings.Contains(content, "v close logs") {
		t.Fatalf("open log view does not expose its close control: %q", content)
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
		"ctrl+v qvOS view",
		"v logs",
		"ctrl+c/z stop options",
		"? help",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("terminal output is missing %q: %q", expected, content)
		}
	}
	assertViewFits(t, m.View().Content, m.width, m.height)

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
		t.Fatal("? did not open contextual help")
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

func TestFutureHubPagesDoNotLookActionable(t *testing.T) {
	for tab := 1; tab < len(sections); tab++ {
		m := model{width: 140, height: 31, tab: tab}
		content := stripANSI(m.View().Content)
		if !strings.Contains(content, "COMING LATER") {
			t.Fatalf("%s page is not labeled as unavailable: %q", sections[tab].name, content)
		}
		if strings.Contains(content, "enter open") {
			t.Fatalf("%s page advertises an inactive Enter action: %q", sections[tab].name, content)
		}

		next, command := m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
		if command != nil || next.(model).loading {
			t.Fatalf("%s page unexpectedly started an action", sections[tab].name)
		}
	}
}

func TestHintRendererWrapsWithoutHidingActions(t *testing.T) {
	hints := []tuiHint{
		{Key: "ctrl+c/z", Action: "stop options"},
		{Key: "v", Action: "close logs"},
		{Key: "ctrl+v", Action: "terminal"},
		{Key: "?", Action: "help"},
	}
	for _, width := range []int{24, 40, 72} {
		t.Run(fmt.Sprintf("width-%d", width), func(t *testing.T) {
			rendered := renderTUIHints(width, hints...)
			content := stripANSI(rendered)
			for _, expected := range []string{"ctrl+c/z", "v close logs", "ctrl+v terminal", "? help"} {
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
