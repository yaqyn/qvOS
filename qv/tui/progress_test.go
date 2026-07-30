package main

import (
	"strings"
	"testing"

	"charm.land/lipgloss/v2"
)

func TestSharedProgressScreenKeepsEveryDomainReadableWhenCompact(t *testing.T) {
	previousWidth := canvasW
	canvasW = 30
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	for _, title := range []string{"UPDATING", "INSTALLING", "SCRIPT"} {
		t.Run(title, func(t *testing.T) {
			rendered := stripANSI(renderProgressScreen(progressScreen{
				Title:    title,
				Status:   "shared milestone",
				Phase:    loadRun,
				Progress: 0.68,
				Bar:      true,
			}, layoutTablet))
			for _, expected := range []string{title, "·", "68%"} {
				if !strings.Contains(rendered, expected) {
					t.Fatalf("compact progress is missing %q: %q", expected, rendered)
				}
			}
			for _, hidden := range []string{"shared milestone", "━", "─"} {
				if strings.Contains(rendered, hidden) {
					t.Fatalf("compact progress should omit %q: %q", hidden, rendered)
				}
			}
			for index, line := range strings.Split(rendered, "\n") {
				if width := lipgloss.Width(line); width > canvasW {
					t.Fatalf("compact line %d width = %d, want <= %d", index, width, canvasW)
				}
			}
		})
	}
}

func TestSharedCompactProgressTrimsLongDomainTitles(t *testing.T) {
	previousWidth := canvasW
	canvasW = 24
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	rendered := renderProgressScreen(progressScreen{
		Title:    "INSTALLING A VERY LONG DOMAIN TITLE",
		Phase:    loadRun,
		Progress: 0.68,
	}, layoutMobile)
	for index, line := range strings.Split(rendered, "\n") {
		if width := lipgloss.Width(line); width > canvasW {
			t.Fatalf("compact line %d width = %d, want <= %d", index, width, canvasW)
		}
	}
}

func TestSharedProgressScreenKeepsMilestoneAndBarWhenTheyFit(t *testing.T) {
	previousWidth := canvasW
	canvasW = 40
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	rendered := stripANSI(renderProgressScreen(progressScreen{
		Title:    "INSTALLING",
		Status:   "applying qvOS baseline",
		Phase:    loadRun,
		Progress: 0.68,
		Bar:      true,
	}, layoutTablet))
	for _, expected := range []string{
		"INSTALLING",
		"applying qvOS baseline",
		"68%",
		"━━━━━━━━━━━━━━━━━━━━━━━",
		"──────────",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("full progress is missing %q: %q", expected, rendered)
		}
	}
}

func TestSharedCompactResultsKeepSemanticDomainTitles(t *testing.T) {
	previousWidth := canvasW
	canvasW = 30
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	tests := []struct {
		name   string
		title  string
		phase  loadPhase
		hidden []string
	}{
		{"update success", "UPDATED", loadOK, []string{"100%", "DONE"}},
		{"software success", "INSTALLED", loadOK, []string{"100%", "DONE"}},
		{"update failure", "UPDATE FAILED", loadErr, []string{"ERR", "100%"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			rendered := stripANSI(renderProgressScreen(progressScreen{
				Title:    test.title,
				Status:   "compact result detail",
				Phase:    test.phase,
				Progress: 1,
				Bar:      true,
			}, layoutMobile))
			if !strings.Contains(rendered, test.title) {
				t.Fatalf("compact result is missing %q: %q", test.title, rendered)
			}
			for _, hidden := range test.hidden {
				if strings.Contains(rendered, hidden) {
					t.Fatalf("compact result should omit %q: %q", hidden, rendered)
				}
			}
		})
	}
}
