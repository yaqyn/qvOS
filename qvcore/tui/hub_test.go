package main

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func TestHubInformationReusesReadOnlyFlowAndReturnsToItsTab(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	for _, entry := range []struct {
		tab, cursor int
		text        string
	}{
		{0, 1, "No verified ISO"},
		{1, 0, "Abdulrahman M. Yaqyn"},
		{1, 1, "Arch Linux"},
	} {
		for _, size := range []struct{ width, height int }{{140, 40}, {80, 28}, {40, 20}} {
			m, command := (model{tab: entry.tab, cursor: entry.cursor, width: size.width, height: size.height}).activateMenuItem()
			if command != nil || !m.loading || !m.scriptDone || m.scriptRunning || m.startConfirm || m.sudoPrompt || m.updatePreflight || m.scriptPath != "" {
				t.Fatal("hub information started a transaction or child command")
			}
			if !m.hubInformation || !isInformationAction(m.action) || m.activeModelRole() != modelOneRing {
				t.Fatal("hub information did not reuse the one-ring information flow")
			}
			if !strings.Contains(strings.Join(m.scriptLogLines, " "), entry.text) {
				t.Fatalf("missing truthful page copy: %#v", m.scriptLogLines)
			}
			content := m.View().Content
			assertViewFits(t, content, size.width, size.height)
			for _, forbidden := range []string{"Preparing", "100%", "Auth Required", "Stop Build"} {
				if strings.Contains(stripANSI(content), forbidden) {
					t.Fatalf("information showed transaction copy %q", forbidden)
				}
			}
			for _, key := range []rune{tea.KeyEscape, tea.KeyEnter} {
				next, command := m.Update(tea.KeyPressMsg{Code: key})
				returned := next.(model)
				if command != nil || returned.loading || returned.tab != entry.tab || returned.cursor != entry.cursor {
					t.Fatal("Return lost the selected tab or item")
				}
			}
		}
	}
}

func TestPublicParagraphLayoutDoesNotLeakIntoSystemActions(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	m, _ := (model{tab: 1}).activateMenuItem()
	for _, action := range []actionMode{actionUpdate, actionBuild, actionGeneric} {
		next := m
		next.resetRootActionState(action, "")
		if next.hubInformation {
			t.Fatal("public paragraph layout leaked into a system action")
		}
	}
}

func TestPublicHubModelRoles(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	if (model{tab: 0}).activeModelRole() != modelCore {
		t.Fatal("System lost its glowing CORE")
	}
	if (model{tab: 1}).activeModelRole() != modelThreeRings {
		t.Fatal("About must show three rings")
	}
	for _, cursor := range []int{0, 1} {
		m, _ := (model{tab: 1, cursor: cursor}).activateMenuItem()
		if m.activeModelRole() != modelOneRing {
			t.Fatal("Developer and Project must show one ring")
		}
		m, _ = m.leaveRootAction()
		if m.activeModelRole() != modelThreeRings {
			t.Fatal("Return must restore the About tab's three rings")
		}
	}
}

func TestDeveloperArticleStartsAtBeginningAcrossResizes(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	m, _ := (model{tab: 1, width: 140, height: 40}).activateMenuItem()
	for _, size := range []tea.WindowSizeMsg{{Width: 40, Height: 20}, {Width: 80, Height: 28}, {Width: 140, Height: 40}} {
		next, _ := m.Update(size)
		m = next.(model)
		lines, rows := m.informationLines()
		visible, _ := visibleTUILogLines(lines, rows, m.logScroll, "")
		if len(visible) == 0 || stripANSI(visible[0]) != stripANSI(lines[0]) {
			t.Fatal("Developer article opened or resized to its end")
		}
		assertViewFits(t, m.View().Content, size.Width, size.Height)
	}
}
