package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	actionflow "github.com/yaqyn/qvOS/action"
)

func TestHubCatalogContainsOnlyRealStableActions(t *testing.T) {
	if len(sections) != 2 {
		t.Fatalf("hub section count = %d, want 2", len(sections))
	}
	if sections[0].name != "SYSTEM" {
		t.Fatalf("hub section = %q, want SYSTEM", sections[0].name)
	}

	got := sections[0].items
	want := []item{
		{id: "00", title: "BUILD", desc: "Build qvOS ISO", action: hubActionBuild},
		{id: "01", title: "DOWNLOAD", desc: "Latest verified ISO", action: hubActionDownload},
	}

	if len(got) != len(want) {
		t.Fatalf("hub action count = %d, want %d", len(got), len(want))
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("hub action %d = %#v, want %#v", index, got[index], want[index])
		}
	}
	if err := validateHubCatalog(sections); err != nil {
		t.Fatalf("hub catalog validation: %v", err)
	}
}

func TestHubCatalogRejectsIncompleteOrDuplicateActions(t *testing.T) {
	tests := []struct {
		name    string
		catalog []section
	}{
		{
			name: "missing action key",
			catalog: []section{{
				name:  "TEST",
				items: []item{{id: "00", title: "ACTION", desc: "Description"}},
			}},
		},
		{
			name: "duplicate action key",
			catalog: []section{{
				name: "TEST",
				items: []item{
					{id: "00", title: "ONE", desc: "First", action: hubActionUpdate},
					{id: "01", title: "TWO", desc: "Second", action: hubActionUpdate},
				},
			}},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if err := validateHubCatalog(test.catalog); err == nil {
				t.Fatal("invalid hub catalog passed validation")
			}
		})
	}
}

func TestUpdateActionUsesTheQvOSMaintenanceOwner(t *testing.T) {
	script, environment, err := rootScriptSpec(actionUpdate)
	if err != nil {
		t.Fatalf("update action spec: %v", err)
	}
	if script != "update/run" {
		t.Fatalf("update script = %q", script)
	}
	if environment != "QVOS_UPDATE_SCRIPT" {
		t.Fatalf("update environment = %q", environment)
	}

	status, progress := scriptProgressFromLine(actionUpdate, "Update qvOS source")
	if status != "updating qvOS source" || progress <= 0 {
		t.Fatalf("source update progress = %q, %f", status, progress)
	}

	status, progress = scriptProgressFromLine(actionUpdate, "Update system packages")
	if status != "updating system packages" || progress <= 0 {
		t.Fatalf("update progress = %q, %f", status, progress)
	}

	status, progress = scriptProgressFromLine(actionUpdate, "qvOS update is complete.")
	if status != "update complete" || progress != 1 {
		t.Fatalf("update completion = %q, %f", status, progress)
	}

	status, progress = scriptProgressFromLine(actionUpdate, "downloading package")
	if status != "" || progress >= 0 {
		t.Fatalf("unknown output fabricated progress = %q, %f", status, progress)
	}
}

func TestPrivilegedGenericActionProceedsDirectlyToSudo(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	script := filepath.Join(t.TempDir(), "privileged-action")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nexit 0\n"), 0o700); err != nil {
		t.Fatalf("write privileged action: %v", err)
	}
	t.Setenv(actionflow.ScriptEnvironment, script)

	spec := actionflow.Spec{
		Slug:         "rust",
		Operation:    "install",
		Title:        "Rust",
		Summary:      "Install a supported development environment",
		RequiresSudo: true,
	}

	m, command := (model{width: 120, height: 50}).beginGenericAction(spec, true)
	if command == nil || m.startConfirm || !m.startImmediately ||
		m.action != actionGeneric {
		t.Fatal("privileged software action retained a duplicate start confirmation")
	}
	if role := m.activeModelRole(); role != modelTwoRings {
		t.Fatalf("software action model role = %d, want two rings", role)
	}
	if content := stripANSI(m.View().Content); !strings.Contains(content, "Preparing") {
		t.Fatalf("direct action did not open on Preparing: %q", content)
	}

	next, command := m.Update(startImmediateActionMsg{})
	m = next.(model)
	if command == nil || !m.updatePreflight || m.sudoChecking || m.scriptRunning {
		t.Fatal("privileged software action did not proceed directly to preflight")
	}
	if content := stripANSI(m.View().Content); !strings.Contains(content, "Preparing") ||
		strings.Contains(content, "checking action readiness") {
		t.Fatalf("preflight transition is not stable Preparing copy: %q", content)
	}

	next, command = m.Update(rootPreflightDoneMsg{
		action: actionGeneric,
		script: m.scriptPath,
	})
	m = next.(model)
	if command != nil || !m.sudoPrompt || m.sudoChecking || m.scriptRunning {
		t.Fatal("privileged software preflight did not proceed directly to sudo")
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"Auth Required",
		"Install a supported",
		"development environment",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("software authorization is missing %q: %q", expected, content)
		}
	}
	for _, redundant := range []string{"Install Rust", "Details:", "Cancel"} {
		if strings.Contains(content, redundant) {
			t.Fatalf("software authorization retained redundant copy %q: %q", redundant, content)
		}
	}

	scriptName, environment, err := rootScriptSpec(actionGeneric)
	if err != nil {
		t.Fatalf("software action script spec: %v", err)
	}
	if scriptName != actionflow.ScriptPath || environment != actionflow.ScriptEnvironment {
		t.Fatalf("software action script = %q / %q", scriptName, environment)
	}
}

func TestUnprivilegedGenericMutationRetainsStartConfirmation(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	spec := actionflow.Spec{
		Slug:      "xbox-cloud",
		Operation: "install",
		Title:     "Xbox Cloud",
		Summary:   "Install the Xbox Cloud Gaming launcher",
		Rings:     2,
	}

	m, command := (model{width: 120, height: 50}).beginGenericAction(spec, true)
	if command != nil || !m.startConfirm || m.startImmediately {
		t.Fatal("unprivileged software mutation lost its meaningful confirmation")
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"INSTALL XBOX CLOUD",
		"Install the Xbox Cloud Gaming launcher",
		"Install",
		"Cancel",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("software confirmation is missing %q: %q", expected, content)
		}
	}
	if hints := fmt.Sprint(m.helpHints()); !strings.Contains(hints, "cancel before starting") {
		t.Fatalf("software confirmation help is incorrect: %q", hints)
	}
}

func TestSearchableSelectionRunsBeforeTheUnprivilegedStartGate(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	script := filepath.Join(t.TempDir(), "selectable-action")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nexit 0\n"), 0o700); err != nil {
		t.Fatalf("write selectable action: %v", err)
	}
	t.Setenv(actionflow.ScriptEnvironment, script)

	spec := actionflow.Spec{
		Slug:           "theme-remove",
		Operation:      "task",
		Title:          "Extra Theme",
		Summary:        "Choose and remove a user-installed theme",
		Rings:          2,
		Primary:        "Remove",
		Active:         "Removing",
		Complete:       "Removed",
		SelectionMode:  "single",
		SelectionTitle: "Select Extra Theme",
	}
	m, command := (model{width: 120, height: 42}).beginGenericAction(spec, true)
	if command == nil || m.startConfirm || !m.startImmediately {
		t.Fatal("selectable action confirmed before collecting its selection")
	}

	next, command := m.Update(startImmediateActionMsg{})
	m = next.(model)
	if command == nil || !m.updatePreflight {
		t.Fatal("selectable action did not run its read-only preflight")
	}
	next, command = m.Update(rootPreflightDoneMsg{
		action: actionGeneric,
		script: m.scriptPath,
	})
	m = next.(model)
	if command == nil || !m.selectionLoading || m.selectionActive {
		t.Fatal("selectable action did not load choices after preflight")
	}
	next, _ = m.Update(actionOptionsLoadedMsg{
		action:  actionGeneric,
		script:  m.scriptPath,
		choices: []string{"Catppuccin", "Tokyo Night"},
	})
	m = next.(model)
	if !m.selectionActive {
		t.Fatal("selectable action did not open its selection screen")
	}

	for _, r := range "tokyo" {
		next, _ = m.Update(tea.KeyPressMsg{Code: r, Text: string(r)})
		m = next.(model)
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{"SELECT EXTRA THEME", "tokyo", "Tokyo Night"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("searchable selection is missing %q: %q", expected, content)
		}
	}
	if strings.Contains(content, "Catppuccin") {
		t.Fatalf("searchable selection retained a non-match: %q", content)
	}

	next, command = m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if command != nil || m.selectionActive || !m.startConfirm ||
		len(m.actionSelections) != 1 || m.actionSelections[0] != "Tokyo Night" {
		t.Fatalf("selection did not feed the one start gate: %#v", m.actionSelections)
	}
}

func TestActionSelectionIsTheOnlyStartGateAndBranchesToSudo(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Slug:             "font-cascadia-mono",
		Operation:        "task",
		Title:            "Cascadia Mono",
		Summary:          "Apply Cascadia Mono across qvOS",
		Rings:            2,
		Primary:          "Apply",
		Active:           "Applying",
		Complete:         "Applied",
		SelectionMode:    "action",
		SelectionTitle:   "Cascadia Mono",
		SummarySelection: "Uninstall",
		SelectionSummary: "Remove Cascadia Mono from the system",
		SelectionSudo:    true,
	}

	apply := model{
		width:            120,
		height:           42,
		loading:          true,
		action:           actionGeneric,
		scriptPath:       filepath.Join(t.TempDir(), "font-action"),
		selectionActive:  true,
		selectionChoices: []string{"Apply Now", "Uninstall"},
	}
	content := stripANSI(apply.renderActionSelectionFor(layoutDesktop))
	for _, expected := range []string{"CASCADIA MONO", "Apply Now", "Uninstall"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("font action choice is missing %q: %q", expected, content)
		}
	}
	if strings.Contains(content, "search") {
		t.Fatalf("two-action choice retained a search field: %q", content)
	}

	next, command := apply.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	apply = next.(model)
	if command == nil || apply.startConfirm || apply.sudoPrompt || !apply.scriptRunning {
		t.Fatal("Apply Now did not start immediately from the TUI choice")
	}

	currentActionSpec = actionflow.Spec{
		Slug:             "font-cascadia-mono",
		Operation:        "task",
		Title:            "Cascadia Mono",
		Summary:          "Apply Cascadia Mono across qvOS",
		Rings:            2,
		Primary:          "Apply",
		Active:           "Applying",
		Complete:         "Applied",
		SelectionMode:    "action",
		SelectionTitle:   "Cascadia Mono",
		SummarySelection: "Uninstall",
		SelectionSummary: "Remove Cascadia Mono from the system",
		SelectionSudo:    true,
	}
	uninstall := model{
		loading:          true,
		action:           actionGeneric,
		scriptPath:       filepath.Join(t.TempDir(), "font-action"),
		selectionActive:  true,
		selectionChoices: []string{"Apply Now", "Uninstall"},
		selectionCursor:  1,
	}
	next, command = uninstall.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	uninstall = next.(model)
	if command != nil || uninstall.startConfirm || !uninstall.sudoPrompt ||
		currentActionSpec.Operation != "uninstall" ||
		currentActionSpec.RollbackProtocol != "" ||
		currentActionSpec.Summary != "Remove Cascadia Mono from the system" {
		t.Fatal("Uninstall did not move directly from the TUI choice to sudo")
	}
	next, command = uninstall.Update(sudoAuthDoneMsg{
		action: actionGeneric,
		script: uninstall.scriptPath,
	})
	uninstall = next.(model)
	if command == nil || uninstall.selectionLoading || !uninstall.scriptRunning {
		t.Fatal("authorized Uninstall reopened choices instead of starting")
	}
}

func TestPrivilegedScopeChoicePrecedesAuthorization(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Slug:             "steam",
		Operation:        "uninstall",
		Title:            "Steam",
		Summary:          "Remove Steam while keeping game libraries, settings, and caches",
		RequiresSudo:     true,
		Rings:            2,
		SelectionMode:    "action",
		SelectionTitle:   "Remove Steam",
		SummarySelection: "Remove Local Game Libraries",
		SelectionSummary: "Remove Steam, local game libraries, settings, and caches",
		SelectionSudo:    true,
	}

	preflight := model{
		loading:    true,
		action:     actionGeneric,
		scriptPath: filepath.Join(t.TempDir(), "steam-action"),
	}
	next, command := preflight.Update(rootPreflightDoneMsg{
		action: actionGeneric,
		script: preflight.scriptPath,
	})
	preflight = next.(model)
	if command == nil || !preflight.selectionLoading || preflight.sudoPrompt {
		t.Fatal("privileged scope requested authorization before its required choice")
	}

	keep := model{
		loading:          true,
		action:           actionGeneric,
		scriptPath:       preflight.scriptPath,
		selectionActive:  true,
		selectionChoices: []string{"Keep Game Libraries", "Remove Local Game Libraries"},
	}
	next, command = keep.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	keep = next.(model)
	if command != nil || !keep.sudoPrompt ||
		currentActionSpec.Summary != "Remove Steam while keeping game libraries, settings, and caches" {
		t.Fatal("safe Steam scope did not move directly to matching authorization")
	}

	currentActionSpec.SelectionMode = "action"
	currentActionSpec.SelectionTitle = "Remove Steam"
	currentActionSpec.SummarySelection = "Remove Local Game Libraries"
	currentActionSpec.SelectionSummary = "Remove Steam, local game libraries, settings, and caches"
	currentActionSpec.SelectionSudo = true
	remove := model{
		loading:          true,
		action:           actionGeneric,
		scriptPath:       preflight.scriptPath,
		selectionActive:  true,
		selectionChoices: []string{"Keep Game Libraries", "Remove Local Game Libraries"},
		selectionCursor:  1,
	}
	next, command = remove.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	remove = next.(model)
	if command != nil || !remove.sudoPrompt ||
		currentActionSpec.Summary != "Remove Steam, local game libraries, settings, and caches" {
		t.Fatal("destructive Steam scope did not move to matching authorization")
	}
}

func TestActiveFontShowsStatusAndOnlyUninstallAtEveryLayout(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Slug:             "font-cascadia-mono",
		Operation:        "task",
		Title:            "Cascadia Mono",
		Summary:          "Cascadia Mono is already applied across qvOS",
		Rings:            2,
		Primary:          "Apply",
		Active:           "Applying",
		Complete:         "Applied",
		SelectionMode:    "action",
		SelectionTitle:   "Cascadia Mono · Already Applied",
		SummarySelection: "Uninstall",
		SelectionSummary: "Remove Cascadia Mono from the system",
		SelectionSudo:    true,
	}

	for _, mode := range []layoutMode{layoutDesktop, layoutTablet, layoutMobile} {
		font := model{
			width:            120,
			height:           42,
			loading:          true,
			action:           actionGeneric,
			scriptPath:       filepath.Join(t.TempDir(), "font-action"),
			selectionActive:  true,
			selectionChoices: []string{"Uninstall"},
		}
		content := stripANSI(font.renderActionSelectionFor(mode))
		for _, expected := range []string{"CASCADIA MONO · ALREADY APPLIED", "Uninstall"} {
			if !strings.Contains(content, expected) {
				t.Fatalf("active font %d is missing %q: %q", mode, expected, content)
			}
		}
		if strings.Contains(content, "Apply Now") || strings.Contains(content, "search") {
			t.Fatalf("active font %d retained an inapplicable control: %q", mode, content)
		}
	}

	font := model{
		loading:          true,
		action:           actionGeneric,
		scriptPath:       filepath.Join(t.TempDir(), "font-action"),
		selectionActive:  true,
		selectionChoices: []string{"Uninstall"},
	}
	next, command := font.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	font = next.(model)
	if command != nil || font.startConfirm || !font.sudoPrompt ||
		currentActionSpec.Operation != "uninstall" {
		t.Fatal("active font Uninstall did not move directly to sudo")
	}
}

func TestMultiSelectionSupportsSearchAndExplicitToggles(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Operation:      "task",
		Title:          "Web App",
		SelectionMode:  "multi",
		SelectionTitle: "Select Web Apps",
	}
	m := model{
		loading:          true,
		action:           actionGeneric,
		selectionActive:  true,
		selectionChoices: []string{"Calendar", "Docs", "Mail"},
	}

	next, _ := m.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyDown})
	m = next.(model)
	next, _ = m.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyTab})
	m = next.(model)
	if len(m.actionSelections) != 1 || m.actionSelections[0] != "Docs" {
		t.Fatalf("multi-selection toggle = %#v", m.actionSelections)
	}
	content := stripANSI(m.renderActionSelectionFor(layoutDesktop))
	if !strings.Contains(content, "✓ Docs") {
		t.Fatalf("multi-selection did not render its selected item: %q", content)
	}

	next, _ = m.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyDown})
	m = next.(model)
	next, command := m.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if command != nil || m.selectionActive || !m.startConfirm ||
		len(m.actionSelections) != 1 || m.actionSelections[0] != "Docs" {
		t.Fatalf("Enter added the highlighted row to the toggled selection: %#v", m.actionSelections)
	}

	direct := model{
		loading:          true,
		action:           actionGeneric,
		selectionActive:  true,
		selectionChoices: []string{"Calendar", "Docs", "Mail"},
		selectionCursor:  2,
	}
	next, command = direct.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	direct = next.(model)
	if command != nil || direct.selectionActive || !direct.startConfirm ||
		len(direct.actionSelections) != 1 || direct.actionSelections[0] != "Mail" {
		t.Fatalf("direct Enter did not use the current row: %#v", direct.actionSelections)
	}
}

func TestLandscapeSelectionUsesTheAvailablePanel(t *testing.T) {
	previous := currentActionSpec
	previousWidth, previousHeight := canvasW, canvasH
	t.Cleanup(func() {
		currentActionSpec = previous
		canvasW, canvasH = previousWidth, previousHeight
	})
	currentActionSpec = actionflow.Spec{
		Operation:      "task",
		Title:          "Extra Theme",
		SelectionMode:  "single",
		SelectionTitle: "Select Extra Theme",
	}

	var choices []string
	for index := 1; index <= 10; index++ {
		choices = append(choices, fmt.Sprintf("Placeholder Theme %02d", index))
	}
	m := model{
		width:            120,
		height:           42,
		loading:          true,
		action:           actionGeneric,
		dedicatedAction:  true,
		selectionActive:  true,
		selectionChoices: choices,
	}
	view := m.View()
	content := stripANSI(view.Content)

	if strings.Contains(content, "Placeholder Theme…") {
		t.Fatalf("landscape selection truncated labels despite available width: %q", content)
	}
	if !strings.Contains(content, "• Placeholder Theme 01") || strings.Contains(content, "●") {
		t.Fatalf("landscape selection is missing its compact cursor: %q", content)
	}
	if got, want := (model{selectionChoices: choices}).actionSelectionLabelWidth(2), lipgloss.Width(choices[0]); got != want {
		t.Fatalf("selection label column width = %d, want content width %d", got, want)
	}
	if got := (model{}).actionSelectionRowLimit(layoutDesktop); got != actionSelectionMaxRows {
		t.Fatalf("desktop selection row limit = %d, want %d", got, actionSelectionMaxRows)
	}
	for _, choice := range choices[:actionSelectionMaxRows] {
		if !strings.Contains(content, choice) {
			t.Fatalf("landscape selection is missing %q: %q", choice, content)
		}
	}
	for _, choice := range choices[actionSelectionMaxRows:] {
		if strings.Contains(content, choice) {
			t.Fatalf("landscape selection exceeded its six-row viewport with %q: %q", choice, content)
		}
	}

	titleColumn, searchColumn, choiceColumn := -1, -1, -1
	for _, line := range strings.Split(content, "\n") {
		if strings.Contains(line, "SELECT EXTRA THEME") {
			titleColumn = lipgloss.Width(line[:strings.Index(line, "SELECT EXTRA THEME")])
		}
		if strings.Contains(line, "search") {
			searchColumn = lipgloss.Width(line[:strings.Index(line, "search")])
		}
		if strings.Contains(line, choices[0]) {
			choiceColumn = lipgloss.Width(line[:strings.Index(line, choices[0])])
		}
	}
	titleCenter := titleColumn*2 + lipgloss.Width("SELECT EXTRA THEME")
	searchCenter := searchColumn*2 + lipgloss.Width("search")
	if titleColumn < 0 || searchColumn < 0 || titleCenter != searchCenter {
		t.Fatalf("search center %d does not align with title center %d", searchCenter, titleCenter)
	}

	typed := m
	typed.selectionFilter = []rune("10")
	typedContent := stripANSI(typed.View().Content)
	typedColumn := -1
	for _, line := range strings.Split(typedContent, "\n") {
		if strings.Contains(line, "10") {
			typedColumn = lipgloss.Width(line[:strings.Index(line, "10")])
			break
		}
	}
	if typedColumn < 0 || choiceColumn < 0 || typedColumn != choiceColumn {
		t.Fatalf("typed search column %d does not align with choice column %d", typedColumn, choiceColumn)
	}

	spaced := m
	for _, character := range "placeholder theme" {
		next, _ := spaced.handleActionSelectionKey(tea.KeyPressMsg{
			Code: character,
			Text: string(character),
		})
		spaced = next.(model)
	}
	if got := string(spaced.selectionFilter); got != "placeholder theme" {
		t.Fatalf("selection search dropped its space: %q", got)
	}
	if got := len(spaced.filteredActionChoices()); got != len(choices) {
		t.Fatalf("space-aware selection search returned %d choices, want %d", got, len(choices))
	}

	lineIndex := func(value, needle string) int {
		for index, line := range strings.Split(value, "\n") {
			if strings.Contains(line, needle) {
				return index
			}
		}
		return -1
	}
	titleRow := lineIndex(content, "SELECT EXTRA THEME")
	hintsRow := lineIndex(content, "enter select")
	for _, filter := range []string{"10", "missing"} {
		filtered := m
		filtered.selectionFilter = []rune(filter)
		filteredContent := stripANSI(filtered.View().Content)
		if got := lineIndex(filteredContent, "SELECT EXTRA THEME"); got != titleRow {
			t.Fatalf("filter %q moved title row from %d to %d", filter, titleRow, got)
		}
		if got := lineIndex(filteredContent, "enter select"); got != hintsRow {
			t.Fatalf("filter %q moved hints row from %d to %d", filter, hintsRow, got)
		}
	}
	assertViewFits(t, view.Content, 120, 42)
}

func TestEmptySelectionInventoryReturnsQuietly(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Operation:      "task",
		Title:          "Extra Theme",
		SelectionMode:  "single",
		SelectionTitle: "Select Extra Theme",
		SelectionEmpty: "No extra themes are installed.",
	}

	choices, err := parseActionOptions("")
	if err != nil || len(choices) != 0 {
		t.Fatalf("empty action choices = %#v, %v", choices, err)
	}

	m := model{
		width:           120,
		height:          42,
		loading:         true,
		action:          actionGeneric,
		dedicatedAction: true,
		selectionActive: true,
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"SELECT EXTRA THEME",
		"No extra themes are installed.",
		"enter / esc return",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("empty selection is missing %q: %q", expected, content)
		}
	}
	for _, unwanted := range []string{"FAILED", "100%", "search"} {
		if strings.Contains(content, unwanted) {
			t.Fatalf("empty selection retained %q: %q", unwanted, content)
		}
	}

	next, command := m.handleActionSelectionKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if command == nil || !m.startCanceled {
		t.Fatal("empty selection did not return cleanly")
	}
}

func TestRootScriptPassesOnlyTheSelectedOwnerArguments(t *testing.T) {
	script := filepath.Join(t.TempDir(), "selected-action")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nprintf '%s\\n' \"$QVOS_ACTION_SELECTIONS\"\n"), 0o700); err != nil {
		t.Fatalf("write selected action: %v", err)
	}

	m := model{
		actionSelections: []string{"Docs", "Mail"},
		selectionActive:  true,
		selectionChoices: []string{"Docs", "Mail"},
		selectionFilter:  []rune("mail"),
		rebootPrompt:     true,
		rebootReasons:    []string{"old result"},
	}
	m, command := m.startRootScriptRun(actionGeneric, script)
	if command == nil {
		t.Fatal("selected action did not start")
	}
	if m.selectionActive || len(m.selectionChoices) != 0 ||
		len(m.selectionFilter) != 0 || len(m.actionSelections) != 0 ||
		m.rebootPrompt || len(m.rebootReasons) != 0 || m.rebootChoice != 1 {
		t.Fatal("selected action retained transient state after launch")
	}

	started, ok := command().(scriptStartedMsg)
	if !ok {
		t.Fatal("selected action did not return a script start message")
	}
	var lines []string
	for event := range started.events {
		if event.line != "" {
			lines = append(lines, event.line)
		}
		if event.done && event.err != nil {
			t.Fatalf("selected action failed: %v", event.err)
		}
	}
	if strings.Join(lines, "\n") != "Docs\nMail" {
		t.Fatalf("selected owner arguments = %q", lines)
	}
}

func TestRebootRequirementReplacesCompletionWithNowOrLaterChoice(t *testing.T) {
	m := model{
		width:           120,
		height:          42,
		loading:         true,
		action:          actionUpdate,
		scriptRunning:   true,
		scriptPath:      "/tmp/update",
		dedicatedAction: true,
	}
	next, _ := m.Update(scriptEventMsg{event: scriptEvent{
		action:         actionUpdate,
		script:         "/tmp/update",
		line:           "updated Linux kernel package",
		output:         true,
		commit:         true,
		terminalUpdate: true,
	}})
	m = next.(model)
	next, _ = m.Update(scriptEventMsg{event: scriptEvent{
		action:         actionUpdate,
		script:         "/tmp/update",
		line:           "qvOS action: reboot required: Linux kernel updated",
		output:         true,
		commit:         true,
		terminalUpdate: true,
	}})
	m = next.(model)
	if len(m.scriptLogLines) != 1 || len(m.rebootReasons) != 1 {
		t.Fatalf("reboot marker leaked into logs: %#v / %#v", m.scriptLogLines, m.rebootReasons)
	}
	next, _ = m.Update(scriptEventMsg{event: scriptEvent{
		action:   actionUpdate,
		script:   "/tmp/update",
		progress: 1,
		done:     true,
	}})
	m = next.(model)
	if !m.rebootPrompt || m.rebootChoice != 1 {
		t.Fatal("successful reboot-required action did not default safely to Later")
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"REBOOT REQUIRED",
		"Linux kernel updated",
		"Reboot Now",
		"Later",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("reboot choice is missing %q: %q", expected, content)
		}
	}
	if strings.Contains(content, "v view logs") {
		t.Fatalf("reboot result exposes the known log shortcut persistently: %q", content)
	}
	next, command := m.Update(tea.KeyPressMsg{Code: 'v', Text: "v"})
	if command != nil {
		t.Fatal("v launched a command from the reboot result")
	}
	m = next.(model)
	if !m.logOverlay || !strings.Contains(stripANSI(m.View().Content), "updated Linux kernel package") {
		t.Fatal("reboot result did not retain its captured logs")
	}
	next, _ = m.Update(tea.KeyPressMsg{Code: 'v', Text: "v"})
	m = next.(model)
	next, command = m.handleRebootChoiceKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if command == nil || m.rebootPrompt || m.startCanceled {
		t.Fatal("Later did not close the completed dedicated action cleanly")
	}
}

func TestActionProtocolMilestonesNeverEnterVisibleLogs(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Operation: "install",
		Title:     "Dictation",
	}
	m := model{
		width:         120,
		height:        42,
		loading:       true,
		action:        actionGeneric,
		scriptRunning: true,
		scriptPath:    "/tmp/dictation",
	}

	for _, line := range []string{
		"qvOS action: preparing",
		"qvOS action: applying",
		"Downloading Dictation model",
		"qvOS action: verifying",
		"qvOS action: complete",
	} {
		status, progress := scriptProgressFromLine(actionGeneric, line)
		next, _ := m.Update(scriptEventMsg{event: scriptEvent{
			action:         actionGeneric,
			script:         m.scriptPath,
			line:           line,
			output:         true,
			commit:         true,
			terminalUpdate: true,
			status:         status,
			progress:       progress,
		}})
		m = next.(model)
	}

	if got := strings.Join(m.scriptLogLines, "\n"); got != "Downloading Dictation model" {
		t.Fatalf("visible action log retained protocol noise: %q", got)
	}
	if m.scriptStatus != currentActionSpec.CompleteStatus() || m.scriptTarget != 1 {
		t.Fatalf("hidden milestones stopped driving progress: %q / %f", m.scriptStatus, m.scriptTarget)
	}
	terminal := stripANSI(renderTUITerminalOutput(
		m.width,
		m.height,
		"Dictation",
		m.scriptLogLines,
		0,
		"",
		m.logEmptyStatus(),
		tuiTerminalPersistentHints(),
	))
	for _, hidden := range []string{"qvOS action: preparing", "qvOS action: applying"} {
		if strings.Contains(terminal, hidden) {
			t.Fatalf("terminal output retained protocol line %q: %q", hidden, terminal)
		}
	}
	if !strings.Contains(terminal, "Downloading Dictation model") {
		t.Fatalf("terminal output lost real owner output: %q", terminal)
	}
}

func TestOneRingActionStartsDirectlyAndMakesOwnerOutputPrimary(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })

	script := filepath.Join(t.TempDir(), "information-action")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nprintf 'Mode: Long_Life\\nCharge limit: 60%%\\n'\n"), 0o700); err != nil {
		t.Fatalf("write information action: %v", err)
	}
	t.Setenv(actionflow.ScriptEnvironment, script)

	spec := actionflow.Spec{
		Slug:         "battery-status",
		Operation:    "task",
		Title:        "Battery Protection",
		Summary:      "Show the current charging-protection state",
		RequiresSudo: false,
		Rings:        1,
		Information:  true,
		Primary:      "Inspect",
		Active:       "Inspecting",
		Complete:     "Inspected",
	}
	m, command := (model{width: 120, height: 50}).beginGenericAction(spec, true)
	if command == nil || m.startConfirm || !m.startImmediately {
		t.Fatal("one-ring information action retained a confirmation step")
	}

	next, command := m.Update(startImmediateActionMsg{})
	m = next.(model)
	if command == nil || m.startConfirm || !m.updatePreflight ||
		m.sudoChecking || m.scriptRunning || m.startImmediately {
		t.Fatal("one-ring information action did not begin with direct preflight")
	}

	m.updatePreflight = false
	m.scriptDone = true
	m.scriptLogLines = []string{"Mode: Long_Life", "Charge limit: 60%"}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"BATTERY PROTECTION",
		"MODE",
		"Long Life",
		"CHARGE LIMIT",
		"60%",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("one-ring information is missing %q: %q", expected, content)
		}
	}
	for _, forbidden := range []string{"INSPECTED", "100%", "Inspect", "Cancel"} {
		if strings.Contains(content, forbidden) {
			t.Fatalf("one-ring information retained transaction copy %q: %q", forbidden, content)
		}
	}
	hints := fmt.Sprint(m.helpHints())
	if strings.Contains(hints, "toggle the qvOS log panel") ||
		strings.Contains(hints, "terminal output") {
		t.Fatalf("one-ring information hid output behind log controls: %q", hints)
	}
}

func TestPrivilegedOneRingInformationUsesSudoWithoutConfirmation(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	script := filepath.Join(t.TempDir(), "privileged-information")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nexit 0\n"), 0o700); err != nil {
		t.Fatalf("write privileged information action: %v", err)
	}
	t.Setenv(actionflow.ScriptEnvironment, script)

	spec := actionflow.Spec{
		Slug:         "hardware-status",
		Operation:    "task",
		Title:        "Hardware Status",
		Summary:      "Read protected hardware status",
		RequiresSudo: true,
		Rings:        1,
		Information:  true,
		Primary:      "Inspect",
		Active:       "Inspecting",
		Complete:     "Inspected",
	}
	m, command := (model{}).beginGenericAction(spec, true)
	if command == nil || m.startConfirm || !m.startImmediately {
		t.Fatal("privileged information did not start directly")
	}
	next, command := m.Update(startImmediateActionMsg{})
	m = next.(model)
	if command == nil || !m.updatePreflight {
		t.Fatal("privileged information did not schedule preflight")
	}
	next, command = m.Update(rootPreflightDoneMsg{
		action: actionGeneric,
		script: m.scriptPath,
	})
	m = next.(model)
	if command != nil || !m.sudoPrompt || m.startConfirm {
		t.Fatal("privileged information did not proceed from preflight to sudo")
	}
}

func TestOneRingMutationStillUsesItsRequiredStartGate(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })

	unprivileged := actionflow.Spec{
		Slug:        "restart-waybar",
		Operation:   "task",
		Title:       "Waybar",
		Summary:     "Restart the Waybar user service",
		Rings:       1,
		Primary:     "Restart",
		Active:      "Restarting",
		Complete:    "Restarted",
		Information: false,
	}
	m, command := (model{}).beginGenericAction(unprivileged, true)
	if command != nil || !m.startConfirm || m.startImmediately {
		t.Fatal("unprivileged one-ring mutation skipped its confirmation")
	}
	if !requirementsForAction(actionGeneric).ProgressBar {
		t.Fatal("one-ring mutation lost its transaction progress")
	}

	privileged := unprivileged
	privileged.Slug = "restart-trackpad"
	privileged.Title = "Trackpad"
	privileged.Summary = "Reset supported trackpad kernel drivers"
	privileged.RequiresSudo = true
	m, command = (model{}).beginGenericAction(privileged, true)
	if command == nil || m.startConfirm || !m.startImmediately {
		t.Fatal("privileged one-ring mutation did not use sudo as its only gate")
	}
}

func TestPreparingLabelCyclesWithoutTransientStatusCopy(t *testing.T) {
	tests := []struct {
		frame int
		want  string
	}{
		{0, "Preparing"},
		{preparingFrameStep, "Preparing."},
		{preparingFrameStep * 2, "Preparing.."},
		{preparingFrameStep * 3, "Preparing..."},
		{preparingFrameStep * 4, "Preparing"},
	}
	for _, test := range tests {
		if got := preparingLabel(test.frame); got != test.want {
			t.Fatalf("preparingLabel(%d) = %q, want %q", test.frame, got, test.want)
		}
	}

	m := model{
		width:           120,
		height:          42,
		loading:         true,
		action:          actionUpdate,
		updatePreflight: true,
		frame:           preparingFrameStep * 3,
	}
	content := stripANSI(m.View().Content)
	if !strings.Contains(content, "Preparing...") {
		t.Fatalf("preparation state is missing its stable animation: %q", content)
	}
	for _, transient := range []string{"checking update readiness", "authorizing sudo", "starting update"} {
		if strings.Contains(content, transient) {
			t.Fatalf("preparation state leaked transient copy %q: %q", transient, content)
		}
	}
}

func TestGenericInstallStopRequiresExplicitConfirmation(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Operation: "install",
		Title:     "Helix",
	}

	canceled := false
	m := model{
		width:         120,
		height:        42,
		loading:       true,
		action:        actionGeneric,
		scriptRunning: true,
		scriptCancel:  func() { canceled = true },
	}
	next, _ := m.Update(tea.KeyPressMsg{Code: 'c', Mod: tea.ModCtrl})
	m = next.(model)
	if canceled || m.scriptCanceling || !m.updateStopConfirm {
		t.Fatal("software interruption bypassed the safe stop confirmation")
	}

	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"STOP INSTALL?",
		"Helix keeps running until you confirm",
		"Keep Installing",
		"Stop Install",
		"ctrl+c/z again stop",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("software stop confirmation is missing %q: %q", expected, content)
		}
	}
}

func TestGenericNonInstallMutationsIgnoreStopKeys(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })

	for _, operation := range []string{"task", "uninstall"} {
		t.Run(operation, func(t *testing.T) {
			currentActionSpec = actionflow.Spec{
				Operation: operation,
				Title:     "Quick Action",
			}
			for _, size := range []struct {
				name          string
				width, height int
			}{
				{"desktop", 120, 42},
				{"tablet", 72, 30},
				{"mobile", 44, 18},
			} {
				t.Run(size.name, func(t *testing.T) {
					for _, key := range []rune{'c', 'z'} {
						canceled := false
						m := model{
							width:         size.width,
							height:        size.height,
							loading:       true,
							action:        actionGeneric,
							scriptRunning: true,
							scriptCancel:  func() { canceled = true },
						}
						next, command := m.Update(tea.KeyPressMsg{Code: key, Mod: tea.ModCtrl})
						m = next.(model)
						if command != nil || canceled || m.scriptCanceling || m.updateStopConfirm {
							t.Fatalf("ctrl+%c changed running %s state", key, operation)
						}
						for _, logOverlay := range []bool{false, true} {
							m.logOverlay = logOverlay
							content := stripANSI(m.View().Content)
							if strings.Contains(content, "ctrl+c/z") || strings.Contains(content, "STOP ") {
								t.Fatalf("running %s exposed Stop controls: %q", operation, content)
							}
						}
						if help := stripANSI(renderTUIHelp(100, "controls", m.helpHints())); strings.Contains(help, "ctrl+c") || strings.Contains(help, "ctrl+z") {
							t.Fatalf("running %s Help exposed Stop controls: %q", operation, help)
						}
						m.terminalView = true
						next, command = m.Update(tea.KeyPressMsg{Code: key, Mod: tea.ModCtrl})
						m = next.(model)
						if command != nil || !m.terminalView || canceled {
							t.Fatalf("ctrl+%c changed full output for %s", key, operation)
						}
					}
				})
			}
		})
	}
}

func TestISOBuilderStopConfirmationUsesBuildCopy(t *testing.T) {
	m := model{
		width:             120,
		height:            42,
		loading:           true,
		action:            actionBuild,
		scriptRunning:     true,
		updateStopConfirm: true,
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"STOP BUILD?",
		"ISO Build keeps running until you confirm",
		"Keep Building",
		"Stop Build",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("ISO Build stop confirmation is missing %q: %q", expected, content)
		}
	}
}

func TestUpdateSkipsDuplicateConfirmationAndBeginsWithPreflight(t *testing.T) {
	m, command := (model{}).beginRootAction(actionUpdate, false)
	if command == nil || !m.loading || m.startConfirm || !m.startImmediately {
		t.Fatal("Update retained a duplicate Begin confirmation")
	}

	next, command := m.Update(startImmediateActionMsg{})
	m = next.(model)
	if command == nil {
		t.Fatal("Update did not schedule its read-only preflight")
	}
	if m.startConfirm || !m.updatePreflight || m.sudoChecking ||
		m.scriptRunning || m.startImmediately {
		t.Fatalf(
			"direct state = confirm:%t preflight:%t sudo:%t",
			m.startConfirm,
			m.updatePreflight,
			m.sudoChecking,
		)
	}
}

func TestISOBuilderRequiresTheUnprivilegedMutationConfirmation(t *testing.T) {
	m, command := (model{
		width: 120, height: 42, fullscreen: true, tab: 0, cursor: 0,
	}).activateMenuItem()
	if command != nil || !m.startConfirm || m.startImmediately ||
		m.action != actionBuild {
		t.Fatal("ISO Build skipped its unprivileged mutation confirmation")
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"BUILD QVOS ISO",
		"Create a bootable qvOS installation image",
		"Build",
		"Cancel",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("ISO Build confirmation is missing %q: %q", expected, content)
		}
	}
}

func TestUnprivilegedStartConfirmationCanCancelBeforeWork(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	spec := actionflow.Spec{
		Slug:      "xbox-cloud",
		Operation: "uninstall",
		Title:     "Xbox Cloud",
		Summary:   "Remove the Xbox Cloud Gaming launcher",
		Rings:     2,
	}
	m, _ := (model{}).beginGenericAction(spec, true)
	m.startChoice = 1
	next, command := m.handleStartConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)

	if command == nil {
		t.Fatal("dedicated cancellation did not exit the TUI")
	}
	if !m.startCanceled {
		t.Fatal("dedicated cancellation lost exit status")
	}
	if m.updatePreflight || m.sudoChecking || m.scriptRunning {
		t.Fatal("canceled action started preflight, sudo, or mutation")
	}
}

func TestRunningUpdateInterruptionKeysOpenStopConfirmation(t *testing.T) {
	for _, code := range []rune{'c', 'z'} {
		t.Run(string(code), func(t *testing.T) {
			canceled := false
			m := model{
				loading:       true,
				action:        actionUpdate,
				scriptRunning: true,
				scriptCancel:  func() { canceled = true },
			}

			next, _ := m.Update(tea.KeyPressMsg{Code: code, Mod: tea.ModCtrl})
			m = next.(model)
			if canceled || m.scriptCanceling {
				t.Fatal("interruption key stopped the running Update before confirmation")
			}
			if !m.updateStopConfirm || m.updateStopChoice != 0 {
				t.Fatal("interruption key did not open the safe default stop confirmation")
			}

			next, _ = m.Update(tea.KeyPressMsg{Code: code, Mod: tea.ModCtrl})
			m = next.(model)
			if !canceled || !m.scriptCanceling || m.updateStopConfirm || m.updateStopChoice != 1 {
				t.Fatal("repeated interruption key did not confirm Stop")
			}
		})
	}
}

func TestRunningUpdateOnlyStopsAfterExplicitConfirmation(t *testing.T) {
	canceled := false
	m := model{
		loading:           true,
		action:            actionUpdate,
		scriptRunning:     true,
		scriptCancel:      func() { canceled = true },
		scriptProgress:    0.38,
		scriptTarget:      0.68,
		updateStopConfirm: true,
	}

	next, _ := m.handleUpdateStopConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if canceled || m.scriptCanceling || m.updateStopConfirm {
		t.Fatal("default Keep Updating choice did not return safely to progress")
	}

	m.updateStopConfirm = true
	next, _ = m.handleUpdateStopConfirmationKey(tea.KeyPressMsg{Code: tea.KeyRight})
	m = next.(model)
	next, _ = m.handleUpdateStopConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if !canceled || !m.scriptCanceling || m.updateStopConfirm {
		t.Fatal("explicit Stop Update confirmation did not start controlled cancellation")
	}
	if m.scriptStatus != "stopping update" {
		t.Fatalf("cancellation status = %q", m.scriptStatus)
	}
	if m.scriptProgress != 0.38 || m.scriptTarget != 0.38 {
		t.Fatalf(
			"cancellation changed progress to %0.2f/%0.2f, want frozen 0.38/0.38",
			m.scriptProgress,
			m.scriptTarget,
		)
	}

	next, _ = m.Update(tickMsg{})
	m = next.(model)
	if m.scriptProgress != 0.38 {
		t.Fatalf("cancellation tick advanced progress to %0.2f", m.scriptProgress)
	}

	next, _ = m.Update(scriptEventMsg{event: scriptEvent{
		action:   actionUpdate,
		progress: 1,
		done:     true,
		err:      errScriptCanceled,
	}})
	m = next.(model)
	if m.scriptProgress != 0.38 || m.scriptTarget != 0.38 {
		t.Fatalf(
			"canceled completion changed progress to %0.2f/%0.2f",
			m.scriptProgress,
			m.scriptTarget,
		)
	}
}

func TestUpdateStopConfirmationRequiresAnExplicitChoice(t *testing.T) {
	canceled := false
	m := model{
		loading:           true,
		action:            actionUpdate,
		scriptRunning:     true,
		scriptCancel:      func() { canceled = true },
		updateStopConfirm: true,
		updateStopChoice:  1,
	}

	next, _ := m.handleUpdateStopConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEscape})
	m = next.(model)
	if canceled || m.scriptCanceling || !m.updateStopConfirm {
		t.Fatal("Escape dismissed the stop confirmation without a choice")
	}
}

func TestCompletedUpdateClosesStopConfirmation(t *testing.T) {
	m := model{
		loading:           true,
		action:            actionUpdate,
		scriptRunning:     true,
		scriptPath:        "/tmp/update",
		updateStopConfirm: true,
	}

	next, _ := m.Update(scriptEventMsg{event: scriptEvent{
		action:   actionUpdate,
		script:   "/tmp/update",
		progress: 1,
		done:     true,
	}})
	m = next.(model)
	if m.updateStopConfirm || !m.scriptDone {
		t.Fatal("completed Update left the stop confirmation open")
	}
}

func TestCompletedInstallWaitsForTheOpenStopDecision(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Slug:      "elixir",
		Operation: "install",
		Title:     "Elixir",
		Primary:   "Install",
		Active:    "Installing",
		Complete:  "Installed",
	}

	completedEvent := func(
		rollback func() (cancelCleanup, cancelProbe),
		finish func(),
	) scriptEvent {
		return scriptEvent{
			action:   actionGeneric,
			script:   "/tmp/elixir",
			progress: 1,
			done:     true,
			rollback: rollback,
			finish:   finish,
		}
	}

	t.Run("keep", func(t *testing.T) {
		rollbackCalled := false
		finishCalled := false
		m := model{
			loading:           true,
			action:            actionGeneric,
			scriptRunning:     true,
			scriptPath:        "/tmp/elixir",
			updateStopConfirm: true,
		}
		next, _ := m.Update(scriptEventMsg{event: completedEvent(
			func() (cancelCleanup, cancelProbe) {
				rollbackCalled = true
				return cancelCleanupMiseRestored, cancelProbeTargetNotDetected
			},
			func() { finishCalled = true },
		)})
		m = next.(model)
		if !m.updateStopConfirm || m.pendingStopEvent == nil || m.scriptDone {
			t.Fatal("completed install did not remain behind the open Stop decision")
		}

		next, command := m.handleUpdateStopConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
		m = next.(model)
		if command != nil || rollbackCalled || !finishCalled || !m.scriptDone || m.scriptCanceled {
			t.Fatal("Keep Installing did not accept the completed install cleanly")
		}
	})

	t.Run("stop", func(t *testing.T) {
		rollbackCalled := false
		finishCalled := false
		m := model{
			loading:           true,
			action:            actionGeneric,
			scriptRunning:     true,
			scriptPath:        "/tmp/elixir",
			updateStopConfirm: true,
		}
		next, _ := m.Update(scriptEventMsg{event: completedEvent(
			func() (cancelCleanup, cancelProbe) {
				rollbackCalled = true
				return cancelCleanupMiseRestored, cancelProbeTargetNotDetected
			},
			func() { finishCalled = true },
		)})
		m = next.(model)

		next, command := m.handleUpdateStopConfirmationKey(tea.KeyPressMsg{
			Code: 'c',
			Mod:  tea.ModCtrl,
		})
		m = next.(model)
		if command == nil || !m.scriptCanceling || m.updateStopConfirm {
			t.Fatal("Stop did not begin rollback for the completed install")
		}
		next, _ = m.Update(command())
		m = next.(model)
		if !rollbackCalled || !finishCalled || !m.scriptDone || !m.scriptCanceled ||
			m.scriptCleanup != cancelCleanupMiseRestored ||
			m.scriptCancelProbe != cancelProbeTargetNotDetected {
			t.Fatal("completed install was not rolled back to a clean stopped result")
		}
	})
}

func TestFullRollbackIsLimitedToCapturedInstalls(t *testing.T) {
	for _, test := range []struct {
		name      string
		action    actionMode
		operation string
		want      bool
	}{
		{"software install", actionGeneric, "install", true},
		{"software uninstall", actionGeneric, "uninstall", false},
		{"mutation task", actionGeneric, "task", false},
		{"system update", actionUpdate, "install", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := usesInstallRollback(test.action, test.operation); got != test.want {
				t.Fatalf("install rollback classification = %t, want %t", got, test.want)
			}
		})
	}
}

func TestOwnerRollbackIsLimitedToDeclaredInstalls(t *testing.T) {
	for _, test := range []struct {
		name      string
		action    actionMode
		operation string
		protocol  string
		want      bool
	}{
		{"declared install", actionGeneric, "install", "owner-state-v1", true},
		{"declared mutation task", actionGeneric, "task", "owner-state-v1", false},
		{"undeclared install", actionGeneric, "install", "", false},
		{"system update", actionUpdate, "install", "owner-state-v1", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := usesActionOwnerRollback(test.action, test.operation, test.protocol); got != test.want {
				t.Fatalf("owner rollback classification = %t, want %t", got, test.want)
			}
		})
	}
}

func TestCanceledInstallRunsOnlyItsDeclaredOwnerRollback(t *testing.T) {
	statePath := filepath.Join(t.TempDir(), "rollback-state")
	script := filepath.Join(t.TempDir(), "action")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
[[ ${1:-} == "--rollback" ]] || exit 2
printf 'restored\n' >"$QVOS_ACTION_ROLLBACK_STATE"
`), 0o755); err != nil {
		t.Fatal(err)
	}
	env := append(os.Environ(), "QVOS_ACTION_ROLLBACK_STATE="+statePath)
	cleanup := cleanupCanceledActionOwner(script, env, filepath.Dir(script))
	if cleanup != cancelCleanupOwnerRestored {
		t.Fatalf("owner rollback cleanup = %v", cleanup)
	}
	if contents, err := os.ReadFile(statePath); err != nil || string(contents) != "restored\n" {
		t.Fatalf("owner rollback state = %q, %v", contents, err)
	}

	if cleanup := cleanupCanceledActionOwner("/missing/action", env, filepath.Dir(script)); cleanup != cancelCleanupOwnerRetained {
		t.Fatalf("failed owner rollback cleanup = %v", cleanup)
	}
}

func TestCompletedOwnerRollbackRetainsCapturedStateUntilStopDecision(t *testing.T) {
	runtimeDir := t.TempDir()
	resultPath := filepath.Join(t.TempDir(), "rollback-result")
	script := filepath.Join(t.TempDir(), "action")
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	t.Setenv("QVOS_TEST_ROLLBACK_RESULT", resultPath)
	if err := os.WriteFile(script, []byte(`#!/bin/bash
case ${1:-} in
--rollback)
  [[ -f $QVOS_ACTION_ROLLBACK_STATE/sealed ]] || exit 1
  printf 'restored\n' >"$QVOS_TEST_ROLLBACK_RESULT"
  ;;
--cancel-status)
  printf 'target-not-detected\n'
  ;;
"")
  install -d -- "$QVOS_ACTION_ROLLBACK_STATE"
  printf 'sealed\n' >"$QVOS_ACTION_ROLLBACK_STATE/sealed"
  ;;
*)
  exit 2
  ;;
esac
`), 0o755); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(
		context.Background(),
		actionGeneric,
		script,
		nil,
		"owner-state-v1",
		events,
	)
	var completed scriptEvent
	for event := range events {
		if event.done {
			completed = event
		}
	}
	if completed.err != nil || completed.rollback == nil {
		t.Fatalf("completed owner has rollback = %t, err = %v", completed.rollback != nil, completed.err)
	}
	runs, err := filepath.Glob(filepath.Join(runtimeDir, "qvos-tui-run-*"))
	if err != nil || len(runs) != 1 {
		t.Fatalf("retained captured run directories = %v, err = %v", runs, err)
	}
	if err := os.Remove(script); err != nil {
		t.Fatal(err)
	}

	cleanup, probe := completed.rollback()
	if cleanup != cancelCleanupOwnerRestored || probe != cancelProbeTargetNotDetected {
		t.Fatalf("completed owner Stop = cleanup %v, probe %v", cleanup, probe)
	}
	if contents, err := os.ReadFile(resultPath); err != nil || string(contents) != "restored\n" {
		t.Fatalf("completed owner rollback result = %q, err = %v", contents, err)
	}
	runs, err = filepath.Glob(filepath.Join(runtimeDir, "qvos-tui-run-*"))
	if err != nil || len(runs) != 0 {
		t.Fatalf("captured run directories after Stop = %v, err = %v", runs, err)
	}
}

func TestCompletedOwnerRollbackReleasesCapturedStateAfterKeepDecision(t *testing.T) {
	runtimeDir := t.TempDir()
	script := filepath.Join(t.TempDir(), "action")
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
case ${1:-} in
--rollback)
  exit 1
  ;;
"")
  install -d -- "$QVOS_ACTION_ROLLBACK_STATE"
  printf 'sealed\n' >"$QVOS_ACTION_ROLLBACK_STATE/sealed"
  ;;
*)
  exit 2
  ;;
esac
`), 0o755); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(
		context.Background(),
		actionGeneric,
		script,
		nil,
		"owner-state-v1",
		events,
	)
	var completed scriptEvent
	for event := range events {
		if event.done {
			completed = event
		}
	}
	if completed.err != nil || completed.rollback == nil || completed.finish == nil {
		t.Fatalf(
			"completed owner has rollback = %t, finish = %t, err = %v",
			completed.rollback != nil,
			completed.finish != nil,
			completed.err,
		)
	}
	runs, err := filepath.Glob(filepath.Join(runtimeDir, "qvos-tui-run-*"))
	if err != nil || len(runs) != 1 {
		t.Fatalf("retained captured run directories = %v, err = %v", runs, err)
	}

	completed.finish()
	runs, err = filepath.Glob(filepath.Join(runtimeDir, "qvos-tui-run-*"))
	if err != nil || len(runs) != 0 {
		t.Fatalf("captured run directories after Keep = %v, err = %v", runs, err)
	}
}

func TestExternalClosureRollsBackAnInstallThatJustCompleted(t *testing.T) {
	rollbackCalled := false
	finishCalled := false
	events := make(chan scriptEvent, 1)
	events <- scriptEvent{
		done: true,
		rollback: func() (cancelCleanup, cancelProbe) {
			rollbackCalled = true
			return cancelCleanupMiseRestored, cancelProbeTargetNotDetected
		},
		finish: func() { finishCalled = true },
	}
	close(events)

	stopActiveScript(model{
		scriptRunning: true,
		scriptCancel:  func() {},
		scriptEvents:  events,
	})
	if !rollbackCalled || !finishCalled {
		t.Fatalf("external closure rollback = %t, finish = %t", rollbackCalled, finishCalled)
	}
}

func TestStoppedUpdateRendersAResultInsteadOfCompletionProgress(t *testing.T) {
	sizes := []struct {
		name          string
		width, height int
	}{
		{"desktop", 120, 42},
		{"tablet", 72, 30},
		{"mobile", 44, 18},
	}

	for _, size := range sizes {
		t.Run(size.name, func(t *testing.T) {
			view := (model{
				width:          size.width,
				height:         size.height,
				loading:        true,
				action:         actionUpdate,
				scriptDone:     true,
				scriptCanceled: true,
			}).View()
			content := stripANSI(view.Content)
			if !strings.Contains(content, "UPDATE STOPPED") {
				t.Fatalf("stopped result is missing: %q", content)
			}
			if strings.Contains(content, "100%") ||
				strings.Contains(content, "UPDATED") ||
				strings.Contains(content, "update complete") {
				t.Fatalf("canceled result still claims completion: %q", content)
			}
		})
	}
}

func TestStoppedGenericActionReportsItsVerifiedFinalState(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Operation: "install",
		Title:     "NordVPN",
	}

	tests := []struct {
		name     string
		probe    cancelProbe
		expected []string
	}{
		{
			"target reached",
			cancelProbeTargetReached,
			[]string{
				"STOPPED WITH CHANGES",
				"NordVPN installed before Stop completed",
				"some changes could not be safely restored",
			},
		},
		{
			"target not detected",
			cancelProbeTargetNotDetected,
			[]string{"STOPPED", "no completed result was detected"},
		},
		{
			"unknown",
			cancelProbeUnknown,
			[]string{"STOPPED", "final state could not be verified"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			content := stripANSI((model{
				width:             120,
				height:            42,
				loading:           true,
				action:            actionGeneric,
				scriptDone:        true,
				scriptCanceled:    true,
				scriptCancelProbe: test.probe,
			}).renderRootCanceledFor(layoutDesktop))
			normalized := strings.Join(strings.Fields(content), " ")
			for _, expected := range test.expected {
				if !strings.Contains(normalized, expected) {
					t.Fatalf("stopped result is missing %q: %q", expected, content)
				}
			}
			for _, hidden := range []string{"100%", "INSTALLED", "CANCELED"} {
				if strings.Contains(content, hidden) {
					t.Fatalf("stopped result retained %q: %q", hidden, content)
				}
			}
		})
	}
}

func TestStoppedActionReportsPackageLockCleanup(t *testing.T) {
	tests := []struct {
		name     string
		cleanup  cancelCleanup
		expected string
	}{
		{
			"removed",
			cancelCleanupPacmanLockRemoved,
			"Canceled Pacman lock removed",
		},
		{
			"retained",
			cancelCleanupPacmanLockRetained,
			"Pacman lock remains; inspect it before another install",
		},
		{
			"partials removed",
			cancelCleanupPacmanPartialsRemoved,
			"Canceled package partials removed",
		},
		{
			"partials retained",
			cancelCleanupPacmanPartialsRetained,
			"Unverified package partials remain; inspect the package cache",
		},
		{
			"packages removed",
			cancelCleanupPacmanPackagesRemoved,
			"Packages added by this attempt removed",
		},
		{
			"package state retained",
			cancelCleanupPacmanPackagesRetained,
			"Package state could not be fully restored; inspect Software",
		},
		{
			"package cache removed",
			cancelCleanupPacmanCacheRemoved,
			"Package cache created by this attempt removed",
		},
		{
			"package cache retained",
			cancelCleanupPacmanCacheRetained,
			"Package cache could not be fully restored; inspect the cache",
		},
		{
			"AUR cache removed",
			cancelCleanupAURRemoved,
			"AUR build cache from this attempt removed",
		},
		{
			"AUR cache retained",
			cancelCleanupAURRetained,
			"AUR build cache could not be fully restored; inspect the cache",
		},
		{
			"mise restored",
			cancelCleanupMiseRestored,
			"Mise changes from this attempt removed",
		},
		{
			"mise retained",
			cancelCleanupMiseRetained,
			"Unverified mise changes remain; inspect the runtime directories",
		},
		{
			"owner restored",
			cancelCleanupOwnerRestored,
			"Installer settings restored",
		},
		{
			"owner retained",
			cancelCleanupOwnerRetained,
			"Installer settings could not be fully restored; inspect its configuration",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			content := stripANSI((model{
				width:          120,
				height:         42,
				loading:        true,
				action:         actionUpdate,
				scriptDone:     true,
				scriptCanceled: true,
				scriptCleanup:  test.cleanup,
			}).renderRootCanceledFor(layoutDesktop))
			normalized := strings.Join(strings.Fields(content), " ")
			if !strings.Contains(normalized, test.expected) {
				t.Fatalf("cleanup result is missing %q: %q", test.expected, content)
			}
		})
	}
}

func TestStoppedActionCleanupContinuesAsOneParagraph(t *testing.T) {
	previousSpec := currentActionSpec
	previousWidth := canvasW
	t.Cleanup(func() {
		currentActionSpec = previousSpec
		canvasW = previousWidth
	})
	currentActionSpec = actionflow.Spec{
		Operation: "install",
		Title:     "Firefox",
	}
	canvasW = 48

	content := stripANSI((model{
		width:             120,
		height:            42,
		loading:           true,
		action:            actionGeneric,
		scriptDone:        true,
		scriptCanceled:    true,
		scriptCancelProbe: cancelProbeTargetNotDetected,
		scriptCleanup:     cancelCleanupPacmanCacheRemoved,
	}).renderRootCanceledFor(layoutDesktop))
	if !strings.Contains(content, "result was detected. Package cache created by") {
		t.Fatalf("cleanup result did not continue as one paragraph: %q", content)
	}
}

func TestStoppedInformationDoesNotRenderAFalseReport(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Operation:   "task",
		Title:       "Battery Protection",
		Information: true,
	}

	content := stripANSI((model{
		width:          120,
		height:         42,
		loading:        true,
		action:         actionGeneric,
		scriptDone:     true,
		scriptCanceled: true,
	}).renderRootProgressFor(layoutDesktop))
	normalized := strings.Join(strings.Fields(content), " ")
	if !strings.Contains(normalized, "STOPPED") ||
		!strings.Contains(normalized, "information command stopped") {
		t.Fatalf("stopped information rendered a false report: %q", content)
	}
}

func TestBootISOInterruptionKeysRemainGuarded(t *testing.T) {
	for _, code := range []rune{'c', 'z'} {
		t.Run(string(code), func(t *testing.T) {
			initial := isoInstallerModel{step: isoStepWriting, preview: true}
			next, command := initial.handleISOKey(
				tea.KeyPressMsg{Code: code, Mod: tea.ModCtrl},
			)
			model := next.(isoInstallerModel)
			if command != nil || !model.shutdownPrompt || model.step != isoStepWriting {
				t.Fatal("boot ISO interruption key bypassed the guarded shutdown flow")
			}

			next, command = model.handleISOKey(
				tea.KeyPressMsg{Code: code, Mod: tea.ModCtrl},
			)
			model = next.(isoInstallerModel)
			if command == nil || model.shutdownChoice != indexChoiceValue(isoShutdownChoices(), "shutdown") {
				t.Fatal("repeated boot ISO interruption key did not confirm shutdown")
			}
		})
	}
}

func TestBootISOShutdownPromptRequiresAnExplicitChoice(t *testing.T) {
	m := isoInstallerModel{
		width:          140,
		height:         31,
		step:           isoStepWriting,
		shutdownPrompt: true,
		shutdownChoice: 0,
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"CANCEL INSTALLATION?",
		"Resume",
		"Shutdown",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("ISO shutdown modal is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"qvOS", "writing installer config", "%", "f1", "ctrl+c/z", "again stop"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("ISO shutdown modal retained %q: %q", hidden, content)
		}
	}

	next, command := m.Update(tea.KeyPressMsg{Code: tea.KeyEscape})
	m = next.(isoInstallerModel)
	if command != nil || !m.shutdownPrompt {
		t.Fatal("Escape dismissed the ISO shutdown prompt without a choice")
	}

	next, command = m.Update(tea.KeyPressMsg{Code: tea.KeyF1})
	m = next.(isoInstallerModel)
	if command != nil || m.helpOverlay || !m.shutdownPrompt {
		t.Fatal("Help replaced the active ISO shutdown decision")
	}
}

func TestOutputOnlyISOProgressAllowsOnlyReadOnlyViewKeys(t *testing.T) {
	m := newISOProgressModel("/tmp/qvos-output-only-progress", true)
	next, command := m.Update(tea.KeyPressMsg{Code: 'v', Text: "v"})
	m = next.(isoProgressModel)
	if command != nil {
		t.Fatal("output-only ISO progress started a command from keyboard input")
	}
	if !m.noInput || !m.logOverlay {
		t.Fatalf("output-only progress did not open its read-only logs: %#v", m)
	}

	next, command = m.Update(tea.KeyPressMsg{Code: 'v', Mod: tea.ModCtrl})
	m = next.(isoProgressModel)
	if command != nil || !m.noInput || !m.logOverlay {
		t.Fatalf("output-only progress accepted the removed Ctrl+V route: %#v", m)
	}
}

func TestDedicatedActionReturnsCancellationStatusAfterStopping(t *testing.T) {
	if status := dedicatedActionExitCode(model{scriptCanceled: true}); status != 130 {
		t.Fatalf("stopped update status = %d", status)
	}
	if status := dedicatedActionExitCode(model{startCanceled: true}); status != 130 {
		t.Fatalf("preflight cancellation status = %d", status)
	}
	if status := dedicatedActionExitCode(model{scriptErr: errors.New("failed")}); status != 1 {
		t.Fatalf("failed update status = %d", status)
	}
}

func TestRunnableSnapshotsStayOutsideTheSourceCheckout(t *testing.T) {
	runtimeDir := t.TempDir()
	sourceDir := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	script := filepath.Join(sourceDir, "update")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	snapshot, cleanup, err := snapshotRunnableScript(script)
	if err != nil {
		t.Fatal(err)
	}
	snapshotDir := filepath.Dir(snapshot)
	if filepath.Dir(snapshotDir) != runtimeDir {
		t.Fatalf("snapshot directory = %q, runtime directory = %q", snapshotDir, runtimeDir)
	}
	if strings.HasPrefix(snapshot, sourceDir+string(filepath.Separator)) {
		t.Fatalf("snapshot dirtied source directory: %s", snapshot)
	}
	cleanup()
	if _, err := os.Stat(snapshotDir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("snapshot cleanup error = %v", err)
	}
}

func TestRootActionScriptsMustBeRegularFiles(t *testing.T) {
	if err := validateRootScript("/dev/null"); err == nil {
		t.Fatal("character device passed root action script validation")
	}

	directory := t.TempDir()
	target := filepath.Join(directory, "target")
	link := filepath.Join(directory, "link")
	if err := os.WriteFile(target, []byte("#!/bin/bash\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if err := validateRootScript(link); err == nil {
		t.Fatal("symlink passed root action script validation")
	}
	if _, cleanup, err := snapshotRunnableScript(link); err == nil {
		cleanup()
		t.Fatal("symlink passed runnable snapshot validation")
	}
}

func TestCancellationStopsRunningAndSuspendedProcessGroups(t *testing.T) {
	tests := map[string]string{
		"running": `#!/bin/bash
trap 'exit 0' INT TERM
echo "pid:$$"
echo ready
while true; do sleep 1; done
`,
		"suspended": `#!/bin/bash
echo "pid:$$"
echo ready
kill -STOP $$
`,
		"ignores interruption": `#!/bin/bash
trap '' INT TERM
echo "pid:$$"
echo ready
while true; do sleep 1; done
`,
	}

	for name, contents := range tests {
		t.Run(name, func(t *testing.T) {
			t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
			script := filepath.Join(t.TempDir(), "update")
			if err := os.WriteFile(script, []byte(contents), 0o755); err != nil {
				t.Fatal(err)
			}

			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			events := make(chan scriptEvent, 32)
			go runRootScriptStream(ctx, actionUpdate, script, nil, "", events)

			processID := 0
			timer := time.NewTimer(10 * time.Second)
			defer timer.Stop()
			for {
				select {
				case event, ok := <-events:
					if !ok {
						t.Fatal("update event stream closed without a result")
					}
					if strings.HasPrefix(event.line, "pid:") {
						processID, _ = strconv.Atoi(strings.TrimPrefix(event.line, "pid:"))
					}
					if event.line == "ready" {
						cancel()
					}
					if event.done {
						if !errors.Is(event.err, errScriptCanceled) {
							t.Fatalf("cancellation error = %v", event.err)
						}
						if processID == 0 {
							t.Fatal("owned process group ID was not captured")
						}
						if processGroupHasLiveMembers(t, processID) {
							t.Fatal("owned process group retained a live member after cancellation")
						}
						return
					}
				case <-timer.C:
					t.Fatal("owned process group did not stop")
				}
			}
		})
	}
}

func TestCancellationUsesInterruptBeforeForcedTermination(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "update")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
trap 'echo interrupted; exit 130' INT
echo ready
while true; do sleep 1; done
`), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan scriptEvent, 32)
	go runRootScriptStream(ctx, actionUpdate, script, nil, "", events)

	interrupted := false
	for event := range events {
		if event.line == "ready" {
			cancel()
		}
		interrupted = interrupted || event.line == "interrupted"
		if event.done && !errors.Is(event.err, errScriptCanceled) {
			t.Fatalf("cancellation error = %v", event.err)
		}
	}
	if !interrupted {
		t.Fatal("cancellation forced termination before the owner handled SIGINT")
	}
}

func TestCanceledActionRemovesOnlyItsOwnSafePacmanLock(t *testing.T) {
	previousPath := pacmanDBLockPath
	previousUID := pacmanDBLockOwnerUID
	previousStatus := packageManagerStatus
	previousRemove := removePacmanDBLockFile
	t.Cleanup(func() {
		pacmanDBLockPath = previousPath
		pacmanDBLockOwnerUID = previousUID
		packageManagerStatus = previousStatus
		removePacmanDBLockFile = previousRemove
	})

	pacmanDBLockPath = filepath.Join(t.TempDir(), "db.lck")
	pacmanDBLockOwnerUID = uint32(os.Getuid())
	packageManagerStatus = func() (bool, bool) { return false, true }
	removePacmanDBLockFile = os.Remove

	writeLock := func(contents string) {
		t.Helper()
		if err := os.WriteFile(pacmanDBLockPath, []byte(contents), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	writeLock("")
	trustedPacman := managerEvidence{owned: true, reliable: true}
	if result := cleanupCanceledPacmanLock(false, trustedPacman); result != cancelCleanupPacmanLockRemoved {
		t.Fatalf("owned lock cleanup = %v", result)
	}
	if _, err := os.Stat(pacmanDBLockPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("owned canceled lock remains: %v", err)
	}

	writeLock("")
	if result := cleanupCanceledPacmanLock(true, trustedPacman); result != cancelCleanupNone {
		t.Fatalf("pre-existing lock cleanup = %v", result)
	}
	if _, err := os.Stat(pacmanDBLockPath); err != nil {
		t.Fatalf("pre-existing lock was removed: %v", err)
	}

	if err := os.Remove(pacmanDBLockPath); err != nil {
		t.Fatal(err)
	}
	writeLock("")
	if result := cleanupCanceledPacmanLock(false, managerEvidence{reliable: true}); result != cancelCleanupPacmanLockRetained {
		t.Fatalf("unowned lock cleanup = %v", result)
	}
	if _, err := os.Stat(pacmanDBLockPath); err != nil {
		t.Fatalf("unowned lock was removed: %v", err)
	}

	packageManagerStatus = func() (bool, bool) { return true, true }
	if result := cleanupCanceledPacmanLock(false, trustedPacman); result != cancelCleanupPacmanLockRetained {
		t.Fatalf("active-manager lock cleanup = %v", result)
	}
	if _, err := os.Stat(pacmanDBLockPath); err != nil {
		t.Fatalf("active package-manager lock was removed: %v", err)
	}

	packageManagerStatus = func() (bool, bool) { return false, true }
	if err := os.WriteFile(pacmanDBLockPath, []byte("unsafe"), 0o600); err != nil {
		t.Fatal(err)
	}
	if result := cleanupCanceledPacmanLock(false, trustedPacman); result != cancelCleanupPacmanLockRetained {
		t.Fatalf("non-empty lock cleanup = %v", result)
	}
	if _, err := os.Stat(pacmanDBLockPath); err != nil {
		t.Fatalf("non-empty lock was removed: %v", err)
	}
}

func TestPackageManagerProcessScanReportsUnverifiedProcesses(t *testing.T) {
	previousProcRoot := procRoot
	t.Cleanup(func() {
		procRoot = previousProcRoot
	})

	procRoot = t.TempDir()
	processDir := filepath.Join(procRoot, "123")
	if err := os.Mkdir(processDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(processDir, "stat"), []byte("unreadable"), 0o000); err != nil {
		t.Fatal(err)
	}
	if active, reliable := packageManagerRunning(); active || reliable {
		t.Fatalf("restricted process scan = active %t, reliable %t", active, reliable)
	}
}

func TestManagerProcessScanSeparatesOwnedAndConcurrentManagers(t *testing.T) {
	previousProcRoot := procRoot
	t.Cleanup(func() { procRoot = previousProcRoot })
	procRoot = t.TempDir()

	writeProcess := func(pid, name string, parent, group int, arguments ...string) {
		t.Helper()
		processDir := filepath.Join(procRoot, pid)
		if err := os.Mkdir(processDir, 0o700); err != nil {
			t.Fatal(err)
		}
		stat := fmt.Sprintf("%s (%s) S %d %d 0 0\n", pid, name, parent, group)
		if err := os.WriteFile(filepath.Join(processDir, "stat"), []byte(stat), 0o600); err != nil {
			t.Fatal(err)
		}
		if len(arguments) > 0 {
			cmdline := strings.Join(arguments, "\x00") + "\x00"
			if err := os.WriteFile(filepath.Join(processDir, "cmdline"), []byte(cmdline), 0o600); err != nil {
				t.Fatal(err)
			}
		}
	}
	writeProcess("100", "bash", 1, 777)
	writeProcess("101", "sudo", 100, 101)
	writeProcess("102", "pacman", 101, 102)
	writeProcess("103", "mise", 1, 888)
	writeProcess("104", "pacman", 1, 999, "/usr/bin/pacman", "-Qq")
	writeProcess("105", "pacman", 1, 999, "/usr/bin/pacman", "-S", "unrelated")

	scan := scanManagerProcesses(777)
	if !scan.reliable || !scan.ownedPacman || scan.ownedMise ||
		!scan.foreignMise || !scan.foreignPacman {
		t.Fatalf("manager process scan = %+v", scan)
	}
	if active, reliable := packageManagerRunning(); !active || !reliable {
		t.Fatalf("manager activity with owned mutation = active %t, reliable %t", active, reliable)
	}

	for _, pid := range []string{"102", "105"} {
		if err := os.RemoveAll(filepath.Join(procRoot, pid)); err != nil {
			t.Fatal(err)
		}
	}
	if active, reliable := packageManagerRunning(); active || !reliable {
		t.Fatalf("read-only Pacman query = active %t, reliable %t", active, reliable)
	}
}

func TestCanceledActionRemovesOnlyNewSafePacmanPartials(t *testing.T) {
	previousUID := pacmanDBLockOwnerUID
	previousStatus := packageManagerStatus
	previousDirectories := pacmanCacheDirectories
	previousRemove := removePacmanCacheFiles
	t.Cleanup(func() {
		pacmanDBLockOwnerUID = previousUID
		packageManagerStatus = previousStatus
		pacmanCacheDirectories = previousDirectories
		removePacmanCacheFiles = previousRemove
	})

	cacheDir := t.TempDir()
	pacmanDBLockOwnerUID = uint32(os.Getuid())
	packageManagerStatus = func() (bool, bool) { return false, true }
	pacmanCacheDirectories = func() ([]string, bool) {
		return []string{cacheDir}, true
	}
	removePacmanCacheFiles = func(paths []string) error {
		for _, path := range paths {
			if err := os.Remove(path); err != nil {
				return err
			}
		}
		return nil
	}

	preexisting := filepath.Join(cacheDir, "preexisting.pkg.tar.zst.part")
	complete := filepath.Join(cacheDir, "complete.pkg.tar.zst")
	for _, path := range []string{preexisting, complete} {
		if err := os.WriteFile(path, []byte("cache"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	snapshot := snapshotPacmanPartials()
	created := filepath.Join(cacheDir, "created.pkg.tar.zst.part")
	if err := os.WriteFile(created, []byte("partial"), 0o600); err != nil {
		t.Fatal(err)
	}

	trustedPacman := managerEvidence{owned: true, reliable: true}
	cleanup := cleanupCanceledPacmanPartials(snapshot, trustedPacman)
	if !cleanup.includes(cancelCleanupPacmanPartialsRemoved) ||
		cleanup.includes(cancelCleanupPacmanPartialsRetained) {
		t.Fatalf("safe partial cleanup = %v", cleanup)
	}
	if _, err := os.Stat(created); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("new canceled partial remains: %v", err)
	}
	for _, path := range []string{preexisting, complete} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("valid cache entry was removed: %v", err)
		}
	}

	snapshot = snapshotPacmanPartials()
	unsafe := filepath.Join(cacheDir, "unsafe.pkg.tar.zst.part")
	if err := os.Symlink(complete, unsafe); err != nil {
		t.Fatal(err)
	}
	cleanup = cleanupCanceledPacmanPartials(snapshot, trustedPacman)
	if !cleanup.includes(cancelCleanupPacmanPartialsRetained) {
		t.Fatalf("unsafe partial cleanup = %v, want retained", cleanup)
	}
	if _, err := os.Lstat(unsafe); err != nil {
		t.Fatalf("unsafe partial was removed: %v", err)
	}

	if err := os.Remove(unsafe); err != nil {
		t.Fatal(err)
	}
	snapshot = snapshotPacmanPartials()
	active := filepath.Join(cacheDir, "active.pkg.tar.zst.part")
	if err := os.WriteFile(active, []byte("partial"), 0o600); err != nil {
		t.Fatal(err)
	}
	packageManagerStatus = func() (bool, bool) { return true, true }
	cleanup = cleanupCanceledPacmanPartials(snapshot, trustedPacman)
	if !cleanup.includes(cancelCleanupPacmanPartialsRetained) {
		t.Fatalf("active package-manager partial cleanup = %v, want retained", cleanup)
	}
	if _, err := os.Stat(active); err != nil {
		t.Fatalf("active package-manager partial was removed: %v", err)
	}
}

func TestCanceledPacmanProcessRemovesItsCreatedLock(t *testing.T) {
	previousPath := pacmanDBLockPath
	previousUID := pacmanDBLockOwnerUID
	previousStatus := packageManagerStatus
	previousRemove := removePacmanDBLockFile
	previousDirectories := pacmanCacheDirectories
	previousPartialRemove := removePacmanCacheFiles
	t.Cleanup(func() {
		pacmanDBLockPath = previousPath
		pacmanDBLockOwnerUID = previousUID
		packageManagerStatus = previousStatus
		removePacmanDBLockFile = previousRemove
		pacmanCacheDirectories = previousDirectories
		removePacmanCacheFiles = previousPartialRemove
	})

	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	cacheDir := t.TempDir()
	pacmanDBLockPath = filepath.Join(t.TempDir(), "db.lck")
	pacmanDBLockOwnerUID = uint32(os.Getuid())
	packageManagerStatus = func() (bool, bool) { return false, true }
	removePacmanDBLockFile = os.Remove
	pacmanCacheDirectories = func() ([]string, bool) {
		return []string{cacheDir}, true
	}
	removePacmanCacheFiles = func(paths []string) error {
		for _, path := range paths {
			if err := os.Remove(path); err != nil {
				return err
			}
		}
		return nil
	}
	t.Setenv("QVOS_TEST_PACMAN_LOCK", pacmanDBLockPath)
	partialPath := filepath.Join(cacheDir, "fixture.pkg.tar.zst.part")
	t.Setenv("QVOS_TEST_PACMAN_PARTIAL", partialPath)

	script := filepath.Join(t.TempDir(), "update")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
set -e
: >"$QVOS_TEST_PACMAN_LOCK"
: >"$QVOS_TEST_PACMAN_PARTIAL"
bash -c 'exec -a pacman sleep 30' &
echo ready
wait
`), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan scriptEvent, 32)
	go runRootScriptStream(ctx, actionUpdate, script, nil, "", events)

	cleanup := cancelCleanupNone
	for event := range events {
		if event.line == "ready" {
			cancel()
		}
		if event.done {
			if !errors.Is(event.err, errScriptCanceled) {
				t.Fatalf("cancellation error = %v", event.err)
			}
			cleanup = event.cancelCleanup
		}
	}
	if !cleanup.includes(cancelCleanupPacmanLockRemoved) ||
		!cleanup.includes(cancelCleanupPacmanPartialsRemoved) {
		t.Fatalf("canceled Pacman cleanup = %v", cleanup)
	}
	if _, err := os.Stat(pacmanDBLockPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("canceled Pacman lock remains: %v", err)
	}
	if _, err := os.Stat(partialPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("canceled Pacman partial remains: %v", err)
	}
}

func processGroupHasLiveMembers(t *testing.T, processGroup int) bool {
	t.Helper()
	output, err := exec.Command("ps", "-eo", "pgid=,stat=").Output()
	if err != nil {
		t.Fatal(err)
	}
	wanted := strconv.Itoa(processGroup)
	for _, line := range strings.Split(string(output), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 || fields[0] != wanted {
			continue
		}
		if !strings.HasPrefix(fields[1], "Z") {
			return true
		}
	}
	return false
}

func TestOwnedProcessGroupWaitsForRunningMembersAndIgnoresZombies(t *testing.T) {
	previousProcRoot := procRoot
	t.Cleanup(func() { procRoot = previousProcRoot })
	procRoot = t.TempDir()

	const processGroup = 8123
	processDir := filepath.Join(procRoot, strconv.Itoa(processGroup))
	if err := os.Mkdir(processDir, 0o700); err != nil {
		t.Fatal(err)
	}
	statPath := filepath.Join(processDir, "stat")
	if err := os.WriteFile(statPath, []byte("8123 (pacman) R 1 8123\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	removed := make(chan struct{})
	go func() {
		time.Sleep(50 * time.Millisecond)
		_ = os.RemoveAll(processDir)
		close(removed)
	}()
	started := time.Now()
	if !waitOwnedProcessGroupStopped(processGroup, time.Second) {
		t.Fatal("running process group was not observed stopping")
	}
	<-removed
	if elapsed := time.Since(started); elapsed < 40*time.Millisecond {
		t.Fatalf("process-group wait returned before the running member stopped: %s", elapsed)
	}

	if err := os.Mkdir(processDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(statPath, []byte("8123 (pacman) Z 1 8123\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if !waitOwnedProcessGroupStopped(processGroup, time.Second) {
		t.Fatal("zombie process prevented the process group from settling")
	}
}

func TestCanceledGenericActionProbesItsDeclaredResult(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "action")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
case ${1:-} in
--cancel-status)
  printf 'target-reached\n'
  exit
  ;;
esac
trap 'exit 0' TERM
printf 'ready\n'
while true; do sleep 1; done
`), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan scriptEvent, 32)
	go runRootScriptStream(ctx, actionGeneric, script, nil, "", events)

	timer := time.NewTimer(5 * time.Second)
	defer timer.Stop()
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatal("generic event stream closed without a result")
			}
			if event.line == "ready" {
				cancel()
			}
			if !event.done {
				continue
			}
			if !errors.Is(event.err, errScriptCanceled) {
				t.Fatalf("cancellation error = %v", event.err)
			}
			if event.cancelProbe != cancelProbeTargetReached {
				t.Fatalf("cancellation probe = %v", event.cancelProbe)
			}
			return
		case <-timer.C:
			t.Fatal("generic cancellation probe did not finish")
		}
	}
}

func TestCapturedOwnerReceivesTTYOutputInTheTUISession(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "owner")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
process_id=$$
process_group=$(ps -o pgid= -p $$ | tr -d ' ')
session_id=$(ps -o sid= -p $$ | tr -d ' ')
[[ $process_group == "$process_id" ]] || {
  echo "owner did not receive its own process group"
  exit 1
}
[[ $session_id != "$process_id" ]] || {
  echo "owner replaced the TUI terminal session"
  exit 1
}
[[ ! -t 0 && -t 1 && -t 2 ]] || {
  echo "owner output is not attached to its captured terminal"
  exit 1
}
echo owned
`), 0o755); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(context.Background(), actionUpdate, script, nil, "", events)

	var lines []string
	owned := false
	done := false
	for event := range events {
		if event.line != "" {
			lines = append(lines, event.line)
			owned = owned || event.line == "owned"
		}
		if event.done {
			done = true
			if event.err != nil {
				t.Fatalf("owned process group failed: %v (%q)", event.err, lines)
			}
			if !owned {
				t.Fatalf("owner process group was not verified: %q", lines)
			}
		}
	}
	if !done {
		t.Fatalf("owned process group stream closed without a result: %q", lines)
	}
}

func TestCapturedTerminalPreservesStdoutAndStderrOrder(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "owner")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
printf 'stdout one\n'
printf 'stderr two\n' >&2
printf 'stdout three\n'
`), 0o755); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(context.Background(), actionUpdate, script, nil, "", events)

	var lines []string
	for event := range events {
		if event.line != "" {
			lines = append(lines, event.line)
		}
		if event.done && event.err != nil {
			t.Fatalf("captured terminal failed: %v", event.err)
		}
	}
	if got := strings.Join(lines, "|"); got != "stdout one|stderr two|stdout three" {
		t.Fatalf("captured terminal order = %q", got)
	}
}

func TestCarriageReturnOutputStreamsBeforeTheOwnerFinishes(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "owner")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
printf 'lmstudio-bin downloading 17%%\r'
sleep 30
`), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan scriptEvent, 32)
	go runRootScriptStream(ctx, actionUpdate, script, nil, "", events)

	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	seenLiveFrame := false
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatal("terminal stream closed before its result")
			}
			if event.line == "lmstudio-bin downloading 17%" {
				if event.done || !event.redraw || !event.output {
					t.Fatalf("live terminal frame metadata = done:%t redraw:%t output:%t", event.done, event.redraw, event.output)
				}
				seenLiveFrame = true
				cancel()
			}
			if !event.done {
				continue
			}
			if !seenLiveFrame {
				t.Fatal("owner completed before its carriage-return output streamed")
			}
			if !errors.Is(event.err, errScriptCanceled) {
				t.Fatalf("cancellation result = %v", event.err)
			}
			return
		case <-timer.C:
			t.Fatal("carriage-return output waited for a newline or process completion")
		}
	}
}

func TestCapturedOwnerBlocksInteractiveGumButPreservesFormatting(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	binDir := t.TempDir()
	gum := filepath.Join(binDir, "gum")
	if err := os.WriteFile(gum, []byte(`#!/bin/bash
printf 'real-gum:%s\n' "$*"
`), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	script := filepath.Join(t.TempDir(), "owner")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
set -e
gum style "safe formatting"
gum confirm "nested prompt"
echo "prompt escaped"
`), 0o755); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(context.Background(), actionUpdate, script, nil, "", events)

	var lines []string
	var result error
	for event := range events {
		if event.line != "" {
			lines = append(lines, event.line)
		}
		if event.done {
			result = event.err
		}
	}
	output := strings.Join(lines, "\n")
	if result == nil {
		t.Fatalf("interactive Gum prompt escaped the capture guard: %q", output)
	}
	if !strings.Contains(output, "real-gum:style safe formatting") {
		t.Fatalf("noninteractive Gum formatting did not reach the real command: %q", output)
	}
	if !strings.Contains(output, "Interactive Gum prompts are unavailable") {
		t.Fatalf("interactive Gum prompt did not fail clearly: %q", output)
	}
	for _, forbidden := range []string{"real-gum:confirm", "prompt escaped"} {
		if strings.Contains(output, forbidden) {
			t.Fatalf("captured Gum guard retained %q: %q", forbidden, output)
		}
	}
}

func TestCapturedInstallSuppressesDetachedLaunches(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	binDir := t.TempDir()
	setsidLog := filepath.Join(t.TempDir(), "setsid.log")
	setsid := filepath.Join(binDir, "setsid")
	if err := os.WriteFile(setsid, []byte(`#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_SETSID_LOG"
`), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("QVOS_TEST_SETSID_LOG", setsidLog)

	script := filepath.Join(t.TempDir(), "owner")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
setsid launch-fixture
printf 'owner-complete\n'
`), 0o755); err != nil {
		t.Fatal(err)
	}

	run := func(operation string) string {
		t.Helper()
		t.Setenv("QVOS_ACTION_OPERATION", operation)
		events := make(chan scriptEvent, 32)
		go runRootScriptStream(context.Background(), actionGeneric, script, nil, "", events)
		var lines []string
		for event := range events {
			if event.line != "" {
				lines = append(lines, event.line)
			}
			if event.done {
				if event.finish != nil {
					event.finish()
				}
				if event.err != nil {
					t.Fatalf("%s captured owner failed: %v", operation, event.err)
				}
			}
		}
		return strings.Join(lines, "\n")
	}

	if output := run("install"); !strings.Contains(output, "owner-complete") {
		t.Fatalf("captured install did not finish after suppressing launch: %q", output)
	}
	if _, err := os.Stat(setsidLog); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("captured install escaped through setsid: %v", err)
	}

	if output := run("task"); !strings.Contains(output, "owner-complete") {
		t.Fatalf("captured task did not finish: %q", output)
	}
	data, err := os.ReadFile(setsidLog)
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(data)) != "launch-fixture" {
		t.Fatalf("non-install setsid delegation = %q", data)
	}
}

func TestTerminalReaderHasNoArtificialLineLimit(t *testing.T) {
	output := strings.Repeat("x", 1100000)
	longestLine := 0
	if err := readTerminalFrames(strings.NewReader(output), func(frame terminalFrame) error {
		if len(frame.line) > longestLine {
			longestLine = len(frame.line)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if longestLine != len(output) {
		t.Fatalf("longest captured line = %d, want %d", longestLine, len(output))
	}
}

func TestFastCommandOutputIsReadBeforeSuccess(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "fast-information")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nprintf 'Battery mode: Long_Life\\n'\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	for attempt := 0; attempt < 25; attempt++ {
		events := make(chan scriptEvent, 8)
		go runRootScriptStream(context.Background(), actionUpdate, script, nil, "", events)

		var outputSeen bool
		for event := range events {
			if event.line == "Battery mode: Long_Life" {
				outputSeen = true
			}
			if !event.done {
				continue
			}
			if event.err != nil {
				t.Fatalf("attempt %d fast output result = %v", attempt, event.err)
			}
			if !outputSeen {
				t.Fatalf("attempt %d completed before delivering command output", attempt)
			}
		}
	}
}

func TestUnprivilegedStartConfirmationFitsResponsiveShapes(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	spec := actionflow.Spec{
		Slug:      "xbox-cloud",
		Operation: "install",
		Title:     "Xbox Cloud",
		Summary:   "Install the Xbox Cloud Gaming launcher",
		Rings:     2,
	}
	sizes := []struct {
		name          string
		width, height int
	}{
		{"desktop", 120, 42},
		{"tablet", 72, 30},
		{"mobile", 44, 18},
		{"compact wide", 80, 20},
		{"fullscreen cinematic", 270, 61},
	}

	for _, size := range sizes {
		t.Run(size.name, func(t *testing.T) {
			m, _ := (model{width: size.width, height: size.height}).
				beginGenericAction(spec, true)
			view := m.View()
			lines := strings.Split(view.Content, "\n")
			if len(lines) > size.height {
				t.Fatalf("view height = %d, terminal height = %d", len(lines), size.height)
			}
			for index, line := range lines {
				if width := lipgloss.Width(line); width > size.width {
					t.Fatalf("line %d width = %d, terminal width = %d", index, width, size.width)
				}
			}
			content := stripANSI(view.Content)
			if !strings.Contains(content, "INSTALL XBOX CLOUD") ||
				!strings.Contains(content, "Install") ||
				!strings.Contains(content, "Cancel") {
				t.Fatalf("confirmation copy is incomplete: %q", content)
			}
		})
	}
}

func TestUpdateProgressShowsStopOptionsAtEveryResponsiveSize(t *testing.T) {
	sizes := []struct {
		name          string
		width, height int
	}{
		{"desktop", 120, 42},
		{"tablet", 72, 30},
		{"mobile", 44, 18},
	}

	for _, size := range sizes {
		t.Run(size.name, func(t *testing.T) {
			m := model{
				width:         size.width,
				height:        size.height,
				loading:       true,
				action:        actionUpdate,
				scriptRunning: true,
				scriptStatus:  "updating qvOS",
			}
			view := m.View()
			if content := stripANSI(view.Content); !strings.Contains(content, "ctrl+c/z") ||
				!strings.Contains(content, "stop options") {
				t.Fatalf("stop-options hint is missing: %q", content)
			}
			for index, line := range strings.Split(view.Content, "\n") {
				if width := lipgloss.Width(line); width > size.width {
					t.Fatalf("line %d width = %d, terminal width = %d", index, width, size.width)
				}
			}
		})
	}
}

func TestISOConfigUsesAQuietPreparationStateWithoutFakeProgress(t *testing.T) {
	previousWidth := canvasW
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	canvasW = 40
	installer := isoInstallerModel{step: isoStepWriting, frame: buildFrames / 2}
	tablet := stripANSI(installer.renderISOStep(layoutTablet))
	if !strings.Contains(tablet, "PREPARING INSTALLATION") ||
		!strings.Contains(tablet, "securing setup details") {
		t.Fatalf("tablet ISO preparation state is incomplete: %q", tablet)
	}
	if strings.Contains(tablet, "%") || strings.ContainsAny(tablet, "━─") {
		t.Fatalf("tablet ISO preparation invented progress: %q", tablet)
	}

	canvasW = 30
	mobile := stripANSI(installer.renderISOStep(layoutMobile))
	if !strings.Contains(mobile, "PREPARING INSTALLATION") {
		t.Fatalf("mobile ISO preparation is missing its title: %q", mobile)
	}
	if strings.Contains(mobile, "%") || strings.ContainsAny(mobile, "━─") {
		t.Fatalf("mobile ISO preparation invented progress: %q", mobile)
	}
}

func TestMobileUpdateProgressKeepsOperationDotAndPercent(t *testing.T) {
	view := (model{
		width:          44,
		height:         18,
		frame:          framesPerTick,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptProgress: 0.68,
		scriptTarget:   0.68,
	}).View()
	content := stripANSI(view.Content)

	for _, expected := range []string{"UPDATING", "·", "68%", "ctrl+c/z"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("mobile update progress is missing %q: %q", expected, content)
		}
	}
	if strings.Contains(content, "help") {
		t.Fatalf("mobile update progress should reserve its hint for stop options: %q", content)
	}
	if strings.ContainsAny(content, "━─") {
		t.Fatalf("mobile update progress should omit the bar: %q", content)
	}
	assertViewFits(t, view.Content, 44, 18)
}

func TestMobileUpdateCompletionKeepsUpdatedResult(t *testing.T) {
	view := (model{
		width:      44,
		height:     18,
		loading:    true,
		action:     actionUpdate,
		scriptDone: true,
	}).View()
	content := stripANSI(view.Content)

	for _, expected := range []string{"UPDATED", "enter", "return"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("mobile update completion is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"100%", "DONE", "UPDATING", "help"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("mobile update completion should omit %q: %q", hidden, content)
		}
	}
	assertViewFits(t, view.Content, 44, 18)
}

func TestWindowsCompletionEnterLaunchesAndEscapeReturns(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Slug:            "windows",
		Operation:       "install",
		Title:           "Windows",
		PostActionLabel: "launch",
		PostAction:      "owner-v1",
	}

	runtimeDir := t.TempDir()
	result := filepath.Join(runtimeDir, "post-action")
	script := filepath.Join(runtimeDir, "run")
	runner := filepath.Join(runtimeDir, "post-run")
	if err := os.WriteFile(script, []byte("#!/bin/bash\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		runner,
		[]byte("#!/bin/bash\nprintf 'qvOS action: applying\\n'\nprintf 'Windows image download visible\\n'\nprintf 'streamed\\n' >\"$QVOS_TEST_POST_ACTION\"\n"),
		0o700,
	); err != nil {
		t.Fatal(err)
	}
	t.Setenv("QVOS_TEST_POST_ACTION", result)
	t.Setenv("QVOS_ACTION_OPERATION", "install")

	completed := model{
		width:           120,
		height:          42,
		loading:         true,
		action:          actionGeneric,
		scriptDone:      true,
		scriptPath:      script,
		dedicatedAction: true,
	}
	content := stripANSI(completed.View().Content)
	if !strings.Contains(content, "enter launch") || strings.Contains(content, "enter return") {
		t.Fatalf("Windows completion controls = %q", content)
	}

	next, command := completed.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	launching := next.(model)
	if command == nil || !launching.postActionFlow || !launching.scriptRunning ||
		!launching.logOverlay || launching.scriptPath != runner {
		t.Fatalf("Enter did not start the visible Windows launch flow: %#v", launching)
	}
	for attempts := 0; attempts < 10 && len(launching.scriptLogLines) == 0; attempts++ {
		next, command = launching.Update(command())
		launching = next.(model)
		if len(launching.scriptLogLines) == 0 && command == nil {
			t.Fatal("Windows launch stream stopped before producing output")
		}
	}
	content = stripANSI(launching.View().Content)
	for _, expected := range []string{"LAUNCHING", "ctrl+c/z", "stop options"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("Windows launch flow is missing %q: %q", expected, content)
		}
	}
	if strings.Contains(content, "%") {
		t.Fatalf("Windows launch flow invented progress: %q", content)
	}
	for attempts := 0; attempts < 20 && !launching.scriptDone; attempts++ {
		next, command = launching.Update(command())
		launching = next.(model)
		if !launching.scriptDone && command == nil {
			t.Fatal("Windows launch stream stopped before completion")
		}
	}
	if !launching.scriptDone || launching.scriptErr != nil ||
		!strings.Contains(strings.Join(launching.scriptLogLines, "\n"), "download visible") {
		t.Fatalf("Windows post-success stream = %#v", launching)
	}
	if output, err := os.ReadFile(result); err != nil || string(output) != "streamed\n" {
		t.Fatalf("post-success owner invocation = %q, %v", output, err)
	}
	content = stripANSI(launching.View().Content)
	if strings.Contains(content, "100%") || !strings.Contains(content, "LAUNCHED") {
		t.Fatalf("Windows launch completion presentation = %q", content)
	}

	currentActionSpec = actionflow.Spec{
		Slug:            "windows",
		Operation:       "install",
		Title:           "Windows",
		PostActionLabel: "launch",
		PostAction:      "owner-v1",
	}
	returning := completed
	next, quit := returning.Update(tea.KeyPressMsg{Code: tea.KeyEsc})
	if quit == nil || next.(model).postActionFlow {
		t.Fatal("Escape did not return without launching Windows")
	}
}

func TestResumedPostActionKeepsItsLaunchStreamAndRetry(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Slug:             "windows",
		Operation:        "install",
		Title:            "Windows",
		Summary:          "Download Windows and start the VM",
		Primary:          "Launch",
		Active:           "Launching",
		Complete:         "Launched",
		RollbackProtocol: "owner-state-v1",
	}

	runner := filepath.Join(t.TempDir(), "post-run")
	if err := os.WriteFile(runner, []byte("#!/bin/bash\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	resumed, command := (model{
		width:           120,
		height:          42,
		loading:         true,
		dedicatedAction: true,
	}).startRootScriptRun(actionGeneric, runner)
	if command == nil || !resumed.postActionFlow || !resumed.logOverlay ||
		!resumed.scriptRunning {
		t.Fatalf("resumed post-success stream = %#v", resumed)
	}
	resumed.scriptStatus = "launching Windows"
	resumed.scriptLogLines = []string{"Downloading Windows"}
	content := stripANSI(resumed.View().Content)
	for _, expected := range []string{"LAUNCHING", "ctrl+c/z", "stop options"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("resumed launch is missing %q: %q", expected, content)
		}
	}
	if strings.Contains(content, "%") {
		t.Fatalf("resumed launch invented progress: %q", content)
	}

	resumed.scriptRunning = false
	resumed.scriptDone = true
	resumed.scriptErr = errors.New("launch interrupted")
	next, retry := resumed.Update(tea.KeyPressMsg{Code: 'r'})
	retrying := next.(model)
	if retry == nil || !retrying.postActionFlow || !retrying.logOverlay ||
		!retrying.scriptRunning || retrying.scriptPath != runner {
		t.Fatalf("resumed launch retry = %#v", retrying)
	}
}

func TestResumedPostActionWaitsForLaunchConfirmation(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	t.Setenv("QVOS_ACTION_SLUG", "windows")
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	t.Setenv("QVOS_ACTION_TITLE", "Windows")
	t.Setenv("QVOS_ACTION_SUMMARY", "Configure Windows")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "0")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_POST_LABEL", "launch")
	t.Setenv("QVOS_ACTION_POST_SUCCESS", "owner-v1")
	t.Setenv("QVOS_ACTION_POST_RESUME", "1")
	runner := filepath.Join(t.TempDir(), "post-run")
	if err := os.WriteFile(runner, []byte("#!/bin/bash\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv(actionflow.ScriptEnvironment, runner)

	spec, err := actionflow.FromEnvironment()
	if err != nil {
		t.Fatal(err)
	}
	initial, command := (model{width: 120, height: 42}).beginGenericAction(spec, true)
	if command != nil || !initial.startConfirm || initial.startImmediately ||
		initial.scriptRunning {
		t.Fatalf("resumed launch skipped its start gate: %#v", initial)
	}
	content := stripANSI(initial.View().Content)
	for _, expected := range []string{"LAUNCH WINDOWS", "Launch", "Cancel"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("resumed launch confirmation is missing %q: %q", expected, content)
		}
	}
	next, preflight := initial.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	checking := next.(model)
	if preflight == nil || checking.startConfirm || !checking.startConfirmed ||
		!checking.updatePreflight {
		t.Fatalf("first Launch press did not begin preflight: %#v", checking)
	}
	next, launch := checking.Update(preflight())
	launching := next.(model)
	if launch == nil || launching.startConfirm || !launching.startConfirmed ||
		!launching.scriptRunning {
		t.Fatalf("preflight requested a second Launch press: %#v", launching)
	}
}

func TestNarrowSideUpdateUsesCenteredCompactProgress(t *testing.T) {
	const (
		width  = 90
		height = 24
	)
	view := (model{
		width:          width,
		height:         height,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptStatus:   "updating AUR packages",
		scriptProgress: 0.68,
		scriptTarget:   0.68,
	}).View()
	content := stripANSI(view.Content)

	for _, expected := range []string{"UPDATING", "·", "68%", "ctrl+c/z"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("narrow side progress is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"updating AUR packages", "━", "─", "help"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("narrow side progress should omit %q: %q", hidden, content)
		}
	}
	assertViewFits(t, view.Content, width, height)
}

func TestCenteredLoadingKeepsBreathingRoomBelowIdentity(t *testing.T) {
	previousWidth, previousHeight := canvasW, canvasH
	canvasW, canvasH = 48, 20
	t.Cleanup(func() {
		canvasW, canvasH = previousWidth, previousHeight
	})

	m := model{
		width:          120,
		height:         42,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptProgress: 0.68,
		scriptTarget:   0.68,
	}
	lines := strings.Split(stripANSI(m.renderDesktopBody("MODEL")), "\n")
	identityRow, progressRow := -1, -1
	for index, line := range lines {
		if strings.Contains(line, "UPDATE") {
			identityRow = index
		}
		if strings.Contains(line, "UPDATING") {
			progressRow = index
		}
	}
	if identityRow < 0 || progressRow < 0 || progressRow-identityRow < 3 {
		t.Fatalf("identity and progress need two centered breathing rows: %q", lines)
	}
	if strings.Contains(strings.Join(lines, "\n"), "· · · · ·") {
		t.Fatalf("active action retained the anonymous hub mark: %q", lines)
	}
}

func TestDefaultLandscapeUpdateKeepsVisibleProgressBar(t *testing.T) {
	view := (model{
		width:          140,
		height:         31,
		loading:        true,
		action:         actionUpdate,
		scriptRunning:  true,
		scriptStatus:   "updating system packages",
		scriptProgress: 0.38,
		scriptTarget:   0.38,
	}).View()
	content := stripANSI(view.Content)

	if !strings.Contains(content, "UPDATING") ||
		!strings.Contains(content, "updating system packages") ||
		!strings.Contains(content, "38%") ||
		!strings.Contains(content, strings.Repeat(tuiRailGlyph, progressRailWidth)) ||
		strings.Contains(content, "━") {
		t.Fatalf("default landscape progress is missing its active stage or loading bar: %q", content)
	}
}

func TestConfirmationActionsUseQuietSelectionMarker(t *testing.T) {
	selected := stripANSI(renderConfirmationAction("Begin", true))
	unselected := stripANSI(renderConfirmationAction("Cancel", false))

	if selected != "● Begin" {
		t.Fatalf("selected action = %q", selected)
	}
	if strings.ContainsAny(selected+unselected, "▐▌|") {
		t.Fatalf("confirmation actions retained framed button decoration: %q / %q", selected, unselected)
	}
}

func TestUpdateStopConfirmationFitsResponsiveShapes(t *testing.T) {
	sizes := []struct {
		name          string
		width, height int
	}{
		{"desktop", 120, 42},
		{"tablet", 72, 30},
		{"mobile", 44, 18},
	}

	for _, size := range sizes {
		t.Run(size.name, func(t *testing.T) {
			m := model{
				width:             size.width,
				height:            size.height,
				loading:           true,
				action:            actionUpdate,
				scriptRunning:     true,
				updateStopConfirm: true,
			}
			view := m.View()
			content := stripANSI(view.Content)
			for _, expected := range []string{
				"STOP UPDATE?",
				"Update keeps running until you confirm",
				"Keep Updating",
				"Stop Update",
				"ctrl+c/z again stop",
			} {
				if !strings.Contains(content, expected) {
					t.Fatalf("stop confirmation is missing %q: %q", expected, content)
				}
			}
			for index, line := range strings.Split(view.Content, "\n") {
				if width := lipgloss.Width(line); width > size.width {
					t.Fatalf("line %d width = %d, terminal width = %d", index, width, size.width)
				}
			}
		})
	}
}

func TestTUIEnvironmentPreservesBrandedColor(t *testing.T) {
	t.Setenv("NO_COLOR", "1")
	t.Setenv("QVOS_TUI_ENV_TEST", "present")

	foundTestVariable := false
	for _, entry := range tuiEnvironment() {
		if strings.HasPrefix(entry, "NO_COLOR=") {
			t.Fatal("TUI environment still contains NO_COLOR")
		}
		if entry == "QVOS_TUI_ENV_TEST=present" {
			foundTestVariable = true
		}
	}
	if !foundTestVariable {
		t.Fatal("TUI environment dropped an unrelated variable")
	}
}

func TestBuildActionFindsInstalledTUIDomainOwner(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("QVOS_PATH", "")
	t.Setenv("QVOS_BUILD_SCRIPT", "")
	t.Chdir(t.TempDir())

	script := filepath.Join(home, ".local", "share", "qvos", "qvcore", "tui", "bin", "qvos-build")
	if err := os.MkdirAll(filepath.Dir(script), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(script, []byte("#!/bin/bash\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := findBuildScript()
	if err != nil {
		t.Fatalf("find build script: %v", err)
	}
	if got != script {
		t.Fatalf("build script = %q, want %q", got, script)
	}
}

func TestBuildActionIgnoresCompatibilitySourceRoot(t *testing.T) {
	home := t.TempDir()
	qvosRoot := filepath.Join(t.TempDir(), "qvos-source")
	omarchyRoot := filepath.Join(t.TempDir(), "omarchy-source")
	t.Setenv("HOME", home)
	t.Setenv("QVOS_PATH", qvosRoot)
	t.Setenv("OMARCHY_PATH", omarchyRoot)
	t.Setenv("QVOS_BUILD_SCRIPT", "")
	t.Chdir(t.TempDir())

	legacyScript := filepath.Join(omarchyRoot, "qvcore", "tui", "bin", "qvos-build")
	if err := os.MkdirAll(filepath.Dir(legacyScript), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(legacyScript, []byte("#!/bin/bash\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	if _, err := findBuildScript(); err == nil {
		t.Fatal("build script discovery accepted OMARCHY_PATH as source authority")
	}
}

func TestResponsiveLayoutUsesDesktopTabletAndMobileTiers(t *testing.T) {
	tests := []struct {
		name          string
		width, height int
		want          layoutMode
	}{
		{"desktop", desktopMinWidth, desktopMinHeight, layoutDesktop},
		{"tablet width", desktopMinWidth - 1, desktopMinHeight, layoutTablet},
		{"tablet height", desktopMinWidth, desktopMinHeight - 1, layoutTablet},
		{"mobile width", tabletMinWidth - 1, desktopMinHeight, layoutMobile},
		{"mobile height", desktopMinWidth, tabletMinHeight - 1, layoutMobile},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := layoutFor(test.width, test.height); got != test.want {
				t.Fatalf("layoutFor(%d, %d) = %v, want %v", test.width, test.height, got, test.want)
			}
		})
	}
}

func TestModelRolesStaySemanticAcrossTUISurfaces(t *testing.T) {
	tests := []struct {
		name  string
		model model
		want  modelRole
	}{
		{"hub", model{tab: 0}, modelCore},
		{"update", model{loading: true, action: actionUpdate}, modelThreeRings},
		{"build", model{loading: true, action: actionBuild}, modelThreeRings},
		{"software", model{loading: true, action: actionGeneric}, modelTwoRings},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := test.model.activeModelRole(); got != test.want {
				t.Fatalf("model role = %d, want %d", got, test.want)
			}
		})
	}
}

func TestUpdateLogPanelPreservesTheLandscapeColumnBudget(t *testing.T) {
	leftWidth, rightWidth := sideColumnWidths(140)
	if leftWidth != 48 || rightWidth != 64 {
		t.Fatalf("columns = %d/%d, want stable 48/64", leftWidth, rightWidth)
	}

	previousWidth, previousHeight := canvasW, canvasH
	canvasW, canvasH = rightWidth, 0
	t.Cleanup(func() {
		canvasW, canvasH = previousWidth, previousHeight
	})

	var logLines []string
	for index := 0; index < 20; index++ {
		logLines = append(logLines, fmt.Sprintf("update log line %02d with useful detail", index))
	}
	panel := (model{
		height:         28,
		scriptLogLines: logLines,
	}).renderRootLogOverlayFor(layoutTablet)
	if width := lipgloss.Width(panel); width != rightWidth {
		t.Fatalf("log panel width = %d, want %d", width, rightWidth)
	}
	if height := len(strings.Split(panel, "\n")); height != 17 {
		t.Fatalf("log panel and switch cue height = %d, want 17", height)
	}
	content := stripANSI(panel)
	if !strings.Contains(content, "update log line 06") ||
		!strings.Contains(content, "update log line 19") ||
		!strings.Contains(content, "ctrl+v  switch") {
		t.Fatalf("expanded log history is incomplete: %q", content)
	}
}

func TestSanitizeLogLineCollapsesTerminalRedrawControls(t *testing.T) {
	line := "\x1b[2Kstale frame\r\x1b[2K68%\tready\b!"
	got := sanitizeLogLine(line)
	if got != "68%  read!" {
		t.Fatalf("sanitized redraw line = %q, want final printable frame", got)
	}
	if strings.ContainsAny(got, "\x1b\r\t\b") {
		t.Fatalf("sanitized line retained terminal controls: %q", got)
	}
}

func TestSanitizeLogLinePreservesFullOwnerText(t *testing.T) {
	want := "  " + strings.Repeat("x", 2048) + "  "
	if got := sanitizeLogLine(want); got != want {
		t.Fatalf("sanitized owner text length = %d, want %d", len(got), len(want))
	}
}

func TestTabletCanvasHidesBeforeTheModelLooksBroken(t *testing.T) {
	if _, _, ok := fitCenteredIconCanvas(tabletMinWidth, tabletMinHeight, fullCanvasReserveRows); ok {
		t.Fatal("constrained centered canvas should hide the model")
	}
}

func TestMenuDescriptionsShareOneAlignedColumn(t *testing.T) {
	column := -1
	for sectionIndex, section := range sections {
		lines := strings.Split(stripANSI((model{tab: sectionIndex}).renderMenuRows(true)), "\n")
		if len(lines) != len(section.items) {
			t.Fatalf("%s rows = %d, want %d", section.name, len(lines), len(section.items))
		}
		for index, line := range lines {
			desc := section.items[index].desc
			got := strings.Index(line, desc)
			if got < 0 {
				t.Fatalf("%s row %d missing description %q: %q", section.name, index, desc, line)
			}
			if column < 0 {
				column = got
			} else if got != column {
				t.Fatalf("%s row %d description column = %d, want %d", section.name, index, got, column)
			}
		}
	}
}

func TestMobileMenuKeepsAlignedTitleAndDescriptionColumns(t *testing.T) {
	metrics := measureMenu(sections)
	column := -1
	for index, entry := range sections[0].items {
		line := stripANSI(renderCompactMenuRow(entry, index == 0, metrics, 40, true))
		got := strings.Index(line, entry.desc)
		if got < 0 {
			t.Fatalf("mobile row %d missing description %q: %q", index, entry.desc, line)
		}
		if column < 0 {
			column = got
		} else if got != column {
			t.Fatalf("mobile row %d description column = %d, want %d", index, got, column)
		}
	}
}

func TestMobileBodyRetainsRoomForAlignedDescriptions(t *testing.T) {
	width := fitContentWidth(60)
	if width < compactMenuRowWidth(measureMenu(prototypeSections), true) {
		t.Fatalf("mobile body width = %d, too narrow for prototype description grid", width)
	}
}

func TestSideCompositionHasCompactAndModelVariants(t *testing.T) {
	if !isSideComposition(156, 20, false) {
		t.Fatal("measured landscape terminal was not recognized")
	}
	if _, _, ok := fitSideIconCanvas(156, 20); ok {
		t.Fatal("small side composition should keep identity on the right when the quality floor cannot fit")
	}
	if width, height, ok := fitSideIconCanvas(156, 24); !ok {
		t.Fatal("side composition should preserve the 3D stage down to its quality floor")
	} else if width < modelQualityMinW || height < modelQualityMinW/2 {
		t.Fatalf("side canvas = %dx%d, below quality floor", width, height)
	}
}

func TestCompositionFollowsVisualOrientation(t *testing.T) {
	tests := []struct {
		name          string
		width, height int
		fullscreen    bool
		side          bool
	}{
		{"measured landscape", 156, 20, false, true},
		{"large floating landscape", 226, 44, false, true},
		{"measured portrait", 98, 50, false, false},
		{"measured square", 98, 40, false, false},
		{"fullscreen cinematic override", 270, 61, true, false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := isSideComposition(test.width, test.height, test.fullscreen); got != test.side {
				t.Fatalf("isSideComposition(%d, %d, %t) = %t, want %t",
					test.width, test.height, test.fullscreen, got, test.side)
			}
		})
	}
}

func TestFullscreenSizedCanvasRespectsModelSizeLimit(t *testing.T) {
	width, height, ok := fitCenterStageCanvas(270, 61, fullCanvasReserveRows)
	if !ok {
		t.Fatal("fullscreen-sized canvas did not preserve the cinematic model")
	}
	if width > maxCanvasW {
		t.Fatalf("fullscreen model width = %d, exceeds hard limit %d", width, maxCanvasW)
	}
	if height != width/2 {
		t.Fatalf("cinematic canvas = %dx%d, want 2:1 cell aspect", width, height)
	}
}

func TestCenteredLayoutHasAnIndependentModelQualityFloor(t *testing.T) {
	if width, height, ok := fitCenteredIconCanvas(48, 36, fullCanvasReserveRows); !ok {
		t.Fatal("portrait layout should preserve the centered 3D stage")
	} else if width < modelQualityMinW || height < modelQualityMinW/2 {
		t.Fatalf("centered canvas = %dx%d, below quality floor", width, height)
	}
	if _, _, ok := fitCenteredIconCanvas(39, 36, fullCanvasReserveRows); ok {
		t.Fatal("narrow portrait layout should hide the model instead of shrinking it")
	}
}

func TestViewportUsesBlackBackgroundWithoutDecorativeFrame(t *testing.T) {
	if bgTerm != "#000000" {
		t.Fatalf("background = %q, want #000000", bgTerm)
	}
	if deepRed != "#5f0000" || red != "#b00000" || hotRed != "#d00000" {
		t.Fatalf(
			"red palette = %q / %q / %q, want #5f0000 / #b00000 / #d00000",
			deepRed, red, hotRed,
		)
	}

	width, height := 100, 30
	rendered := renderViewport(width, height, "qvOS")
	backgroundFill := lipgloss.NewStyle().Background(lipgloss.Color(bgTerm)).Render(" ")
	backgroundSequence := strings.TrimSuffix(backgroundFill, " \x1b[m")
	if backgroundSequence == "" || backgroundSequence == backgroundFill ||
		!strings.Contains(rendered, backgroundSequence) {
		t.Fatal("viewport padding does not paint the qvOS black background")
	}
	view := stripANSI(rendered)
	lines := strings.Split(view, "\n")
	if len(lines) != height {
		t.Fatalf("viewport height = %d, want %d", len(lines), height)
	}
	for index, line := range lines {
		if got := lipgloss.Width(line); got != width {
			t.Fatalf("viewport line %d width = %d, want %d", index, got, width)
		}
	}
	if strings.Contains(view, "┌") || strings.Contains(view, "┐") ||
		strings.Contains(view, "└") || strings.Contains(view, "┘") {
		t.Fatal("viewport still renders the removed perimeter")
	}
}

func TestTUIInitializationClearsThePreviousProgramBeforeStartingWork(t *testing.T) {
	workRan := false
	work := func() tea.Msg {
		workRan = true
		return nil
	}

	commands := initialTUICommands(work)
	if len(commands) != 2 {
		t.Fatalf("initial command count = %d, want 2", len(commands))
	}
	if got, want := fmt.Sprintf("%T", commands[0]()), fmt.Sprintf("%T", tea.ClearScreen()); got != want {
		t.Fatalf("first initial command = %s, want %s", got, want)
	}
	if workRan {
		t.Fatal("TUI work ran before the clear command was inspected")
	}
	commands[1]()
	if !workRan {
		t.Fatal("TUI work command did not remain after the clear command")
	}
}

func TestLogsHideModelWhenMinimumCanvasCannotFit(t *testing.T) {
	if _, _, ok := fitCenteredIconCanvas(desktopMinWidth, desktopMinHeight, logCanvasReserveRows); ok {
		t.Fatal("log-constrained canvas should yield to logs")
	}
}

func TestHubViewFitsEveryResponsiveShape(t *testing.T) {
	sizes := []struct {
		name          string
		width, height int
	}{
		{"desktop", 120, 42},
		{"tablet", 72, 30},
		{"mobile", 44, 18},
		{"compact wide", 80, 20},
		{"large wide", 120, 20},
		{"fullscreen cinematic", 270, 61},
	}

	for _, size := range sizes {
		t.Run(size.name, func(t *testing.T) {
			view := (model{width: size.width, height: size.height}).View()
			lines := strings.Split(view.Content, "\n")
			if len(lines) > size.height {
				t.Fatalf("view height = %d, terminal height = %d", len(lines), size.height)
			}
			for index, line := range lines {
				if width := lipgloss.Width(line); width > size.width {
					t.Fatalf("line %d width = %d, terminal width = %d", index, width, size.width)
				}
			}
		})
	}
}

func TestAnimationUsesSharedFasterMotionRate(t *testing.T) {
	if animationSpeed <= 1 {
		t.Fatalf("animation speed = %v, want faster than original rate", animationSpeed)
	}
	if got, want := animationFrame(10), 16.0; got != want {
		t.Fatalf("animationFrame(10) = %v, want %v", got, want)
	}
}

func TestRenderedModelRampPreservesPaletteStyles(t *testing.T) {
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
	for style := cellStyle(0); style < cellStyleCount; style++ {
		if renderedRamp[style][0] != "" {
			t.Fatalf("style %d renders the empty shade", style)
		}
		for shade := 1; shade < len(shadeRamp); shade++ {
			want := styles[style].Render(string(shadeRamp[shade]))
			if got := renderedRamp[style][shade]; got != want {
				t.Fatalf("style %d shade %d = %q, want %q", style, shade, got, want)
			}
		}
	}
}

func TestPrototypeSudoSessionIsIsolatedAndMasked(t *testing.T) {
	profile := prototypeProfileFor(prototypeSudo)
	if !profile.requiresSudo {
		t.Fatal("sudo prototype does not require its fake authorization screen")
	}

	model := prototypeSessionModel{profile: profile}
	next, _ := model.handleKey(tea.KeyPressMsg{Text: "secret", Code: 's'})
	model = next.(prototypeSessionModel)
	if got := stripANSI(model.renderPanel(layoutDesktop)); strings.Contains(got, "secret") {
		t.Fatal("prototype password was rendered as plaintext")
	}

	next, _ = model.handleKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(prototypeSessionModel)
	if !model.running {
		t.Fatal("prototype session did not start after fake authorization")
	}
	if len(model.password) != 0 {
		t.Fatal("prototype password was retained after authorization")
	}
}

func TestPrototypeCatalogCoversScriptsAppsAndBootPhases(t *testing.T) {
	if len(prototypeSections) != 3 {
		t.Fatalf("prototype section count = %d, want 3", len(prototypeSections))
	}
	for index, name := range []string{"SESSIONS", "APPS", "BOOT"} {
		if prototypeSections[index].name != name {
			t.Fatalf("prototype section %d = %q, want %q", index, prototypeSections[index].name, name)
		}
		if len(prototypeSections[index].items) != 3 {
			t.Fatalf("prototype section %s item count = %d, want 3", name, len(prototypeSections[index].items))
		}
	}
}

func TestPrototypePagesShareOneAlignedDescriptionColumn(t *testing.T) {
	column := -1
	for sectionIndex, section := range prototypeSections {
		lines := strings.Split(stripANSI(renderPrototypeMenuRows(sectionIndex, 0, true)), "\n")
		for itemIndex, line := range lines {
			got := strings.Index(line, section.items[itemIndex].desc)
			if got < 0 {
				t.Fatalf("%s row %d missing description: %q", section.name, itemIndex, line)
			}
			if column < 0 {
				column = got
			} else if got != column {
				t.Fatalf("%s row %d description column = %d, want %d", section.name, itemIndex, got, column)
			}
		}
	}
}

func TestPrototypeCompactRowsKeepOneGridAcrossEveryPage(t *testing.T) {
	metrics := measureMenu(prototypeSections)
	rowWidth := -1
	descriptionColumn := -1

	for _, section := range prototypeSections {
		for itemIndex, entry := range section.items {
			row := stripANSI(renderCompactMenuRow(entry, itemIndex == 0, metrics, 48, true))
			if got := lipgloss.Width(row); rowWidth < 0 {
				rowWidth = got
			} else if got != rowWidth {
				t.Fatalf("%s row %d width = %d, want %d", section.name, itemIndex, got, rowWidth)
			}

			got := strings.Index(row, entry.desc)
			if got < 0 {
				t.Fatalf("%s row %d missing description: %q", section.name, itemIndex, row)
			}
			if descriptionColumn < 0 {
				descriptionColumn = got
			} else if got != descriptionColumn {
				t.Fatalf("%s row %d description column = %d, want %d",
					section.name, itemIndex, got, descriptionColumn)
			}
		}
	}
}
