package main

import (
	"errors"
	"strings"
	"testing"

	"charm.land/lipgloss/v2"
	actionflow "github.com/Yaqyn-qvOS/qvOS/action"
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
		result string
		hidden []string
	}{
		{"update success", "UPDATED", loadOK, "UPDATED", []string{"100%", "DONE"}},
		{"software success", "INSTALLED", loadOK, "INSTALLED", []string{"100%", "DONE"}},
		{
			"update failure",
			"UPDATE FAILED",
			loadErr,
			"UPDATE COULD NOT COMPLETE",
			[]string{"FAILED", "ERR", "100%", "━", "─"},
		},
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
			if !strings.Contains(rendered, test.result) {
				t.Fatalf("compact result is missing %q: %q", test.result, rendered)
			}
			for _, hidden := range test.hidden {
				if strings.Contains(rendered, hidden) {
					t.Fatalf("compact result should omit %q: %q", hidden, rendered)
				}
			}
		})
	}
}

func TestSuccessGuidanceIsQuietResponsiveAndSuccessOnly(t *testing.T) {
	previousWidth := canvasW
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	nextStep := "Restart Chromium, then open Settings > You and Google to sign in."
	for _, test := range []struct {
		name  string
		width int
		mode  layoutMode
	}{
		{"desktop", 58, layoutDesktop},
		{"mobile", 28, layoutMobile},
	} {
		t.Run(test.name, func(t *testing.T) {
			canvasW = test.width
			rendered := stripANSI(renderProgressScreen(progressScreen{
				Title:    "INSTALLED",
				Status:   "Chromium Account installed",
				Phase:    loadOK,
				Progress: 1,
				Bar:      true,
				NextStep: nextStep,
			}, test.mode))
			if normalized := strings.Join(strings.Fields(rendered), " "); !strings.Contains(normalized, nextStep) {
				t.Fatalf("success result is missing next-step guidance: %q", rendered)
			}
			for index, line := range strings.Split(rendered, "\n") {
				if width := lipgloss.Width(line); width > canvasW {
					t.Fatalf("success line %d width = %d, want <= %d", index, width, canvasW)
				}
			}
		})
	}

	canvasW = 58
	for _, phase := range []loadPhase{loadRun, loadErr} {
		rendered := stripANSI(renderProgressScreen(progressScreen{
			Title:    "INSTALLING",
			Status:   "owner result",
			Phase:    phase,
			Progress: 0.5,
			Bar:      true,
			NextStep: nextStep,
		}, layoutDesktop))
		if strings.Contains(rendered, "Restart Chromium") {
			t.Fatalf("%v result leaked success guidance: %q", phase, rendered)
		}
	}
}

func TestGenericCompletionUsesItsContractSuccessGuidance(t *testing.T) {
	previousWidth := canvasW
	previousSpec := currentActionSpec
	t.Cleanup(func() {
		canvasW = previousWidth
		currentActionSpec = previousSpec
	})
	canvasW = 58
	currentActionSpec = actionflow.Spec{
		Operation: "install",
		Title:     "Chromium Account",
		NextStep:  "Restart Chromium, then open Settings > You and Google to sign in.",
	}

	rendered := stripANSI((model{
		action:     actionGeneric,
		scriptDone: true,
	}).renderRootProgressFor(layoutDesktop))
	if !strings.Contains(rendered, "Restart Chromium") {
		t.Fatalf("generic completion lost its next-step contract: %q", rendered)
	}
}

func TestSharedFailureResultIsCalmCompleteAndResponsive(t *testing.T) {
	previousWidth := canvasW
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	message := "Package metadata could not be downloaded because the configured mirror is temporarily unavailable"
	tests := []struct {
		name  string
		width int
		mode  layoutMode
	}{
		{"desktop", 58, layoutDesktop},
		{"tablet", 40, layoutTablet},
		{"mobile", 28, layoutMobile},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			canvasW = test.width
			rendered := stripANSI(renderProgressScreen(progressScreen{
				Title:    "UPDATE FAILED",
				Status:   message,
				Phase:    loadErr,
				Progress: 1,
				Bar:      true,
			}, test.mode))
			normalized := strings.Join(strings.Fields(rendered), " ")
			for _, expected := range []string{
				"UPDATE COULD NOT COMPLETE",
				message,
			} {
				if !strings.Contains(normalized, expected) {
					t.Fatalf("failure result is missing %q: %q", expected, rendered)
				}
			}
			for _, hidden := range []string{"FAILED", "100%", "━", "─", "…"} {
				if strings.Contains(rendered, hidden) {
					t.Fatalf("failure result retained %q: %q", hidden, rendered)
				}
			}
			for index, line := range strings.Split(rendered, "\n") {
				if width := lipgloss.Width(line); width > canvasW {
					t.Fatalf("failure line %d width = %d, want <= %d", index, width, canvasW)
				}
			}
		})
	}
}

func TestEveryFailureSurfaceUsesTheSharedResult(t *testing.T) {
	previousWidth := canvasW
	previousSpec := currentActionSpec
	t.Cleanup(func() {
		canvasW = previousWidth
		currentActionSpec = previousSpec
	})
	canvasW = 52
	currentActionSpec = actionflow.Spec{
		Operation: "task",
		Title:     "Extra Theme",
		Primary:   "Remove",
	}
	failure := errors.New("the owner returned a complete actionable explanation")

	tests := []struct {
		name     string
		rendered string
		title    string
		message  string
	}{
		{
			"update",
			(model{
				action:    actionUpdate,
				scriptErr: failure,
			}).renderRootProgressFor(layoutDesktop),
			"UPDATE COULD NOT COMPLETE",
			failure.Error(),
		},
		{
			"build",
			(model{
				action:    actionBuild,
				scriptErr: failure,
			}).renderRootProgressFor(layoutDesktop),
			"BUILD COULD NOT COMPLETE",
			failure.Error(),
		},
		{
			"task",
			(model{
				action:    actionGeneric,
				scriptErr: failure,
			}).renderRootProgressFor(layoutDesktop),
			"REMOVE EXTRA THEME COULD NOT COMPLETE",
			failure.Error(),
		},
		{
			"information",
			renderInformationScreen(informationScreen{
				Title: "Battery Protection",
				Lines: []string{failure.Error()},
				Empty: "The action did not complete.",
				Error: true,
				Width: 52,
			}),
			"BATTERY PROTECTION COULD NOT COMPLETE",
			failure.Error(),
		},
		{
			"prototype",
			(prototypeSessionModel{
				profile: prototypeProfile{title: "BUILD"},
				failed:  true,
			}).renderPanel(layoutDesktop),
			"BUILD COULD NOT COMPLETE",
			errPrototypeFailure.Error(),
		},
		{
			"ISO setup",
			(isoInstallerModel{
				step:      isoStepError,
				errorText: failure.Error(),
			}).renderISOStep(layoutDesktop),
			"SETUP COULD NOT COMPLETE",
			failure.Error(),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			rendered := stripANSI(test.rendered)
			normalized := strings.Join(strings.Fields(rendered), " ")
			for _, expected := range []string{test.title, test.message} {
				if !strings.Contains(normalized, expected) {
					t.Fatalf("%s failure is missing %q: %q", test.name, expected, rendered)
				}
			}
			for _, hidden := range []string{"FAILED", "100%", "━", "─", "…"} {
				if strings.Contains(rendered, hidden) {
					t.Fatalf("%s failure retained %q: %q", test.name, hidden, rendered)
				}
			}
		})
	}
}
