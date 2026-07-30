package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	actionflow "github.com/Yaqyn-qvOS/qvOS/action"
)

func TestHubCatalogContainsOnlyRealStableActions(t *testing.T) {
	if len(sections) != 1 {
		t.Fatalf("hub section count = %d, want 1", len(sections))
	}
	if sections[0].name != "SYSTEM" {
		t.Fatalf("hub section = %q, want SYSTEM", sections[0].name)
	}

	got := sections[0].items
	want := []item{
		{id: "00", title: "UPDATE", desc: "Sync qvOS", action: hubActionUpdate},
		{id: "01", title: "BUILD", desc: "Build qvOS ISO", action: hubActionBuild},
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

	status, progress := scriptProgressFromLine(actionUpdate, "Update Omarchy")
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

func TestGenericSoftwareActionUsesOneSharedTwoRingFlow(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	spec := actionflow.Spec{
		Slug:         "rust",
		Operation:    "install",
		Title:        "Rust",
		Summary:      "Install a supported development environment",
		RequiresSudo: true,
	}

	m, command := (model{width: 120, height: 50}).beginGenericAction(spec, true)
	if command != nil || !m.updateConfirm || m.action != actionGeneric {
		t.Fatal("software action skipped the shared confirmation state")
	}
	if role := m.activeModelRole(); role != modelTwoRings {
		t.Fatalf("software action model role = %d, want two rings", role)
	}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"INSTALL RUST",
		"Install a supported development environment",
		"Install",
		"Cancel",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("software confirmation is missing %q: %q", expected, content)
		}
	}
	if hints := fmt.Sprint(m.helpHints()); !strings.Contains(hints, "cancel before starting") ||
		strings.Contains(hints, "cancel before updating") {
		t.Fatalf("software confirmation help retained Update copy: %q", hints)
	}

	next, command := m.handleUpdateConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if command == nil || !m.updatePreflight || m.sudoChecking || m.scriptRunning {
		t.Fatal("software confirmation did not schedule preflight before sudo or mutation")
	}

	script, environment, err := rootScriptSpec(actionGeneric)
	if err != nil {
		t.Fatalf("software action script spec: %v", err)
	}
	if script != actionflow.ScriptPath || environment != actionflow.ScriptEnvironment {
		t.Fatalf("software action script = %q / %q", script, environment)
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
		Primary:      "Inspect",
		Active:       "Inspecting",
		Complete:     "Inspected",
	}
	m, command := (model{width: 120, height: 50}).beginGenericAction(spec, true)
	if command != nil || m.updateConfirm || !m.startImmediately {
		t.Fatal("one-ring information action retained a confirmation step")
	}

	next, command := m.Update(startImmediateActionMsg{})
	m = next.(model)
	if command == nil || m.updateConfirm || !m.updatePreflight ||
		m.sudoChecking || m.scriptRunning || m.startImmediately {
		t.Fatal("one-ring information action did not begin with direct preflight")
	}

	m.updatePreflight = false
	m.scriptDone = true
	m.scriptLogLines = []string{"Mode: Long_Life", "Charge limit: 60%"}
	content := stripANSI(m.View().Content)
	for _, expected := range []string{
		"BATTERY PROTECTION",
		"Mode: Long_Life",
		"Charge limit: 60%",
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

func TestGenericSoftwareActionStopRequiresExplicitConfirmation(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Operation: "uninstall",
		Title:     "Steam",
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
		"STOP UNINSTALL?",
		"Steam keeps running until you confirm",
		"Keep Uninstalling",
		"Stop Uninstall",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("software stop confirmation is missing %q: %q", expected, content)
		}
	}
	if hints := fmt.Sprint(m.helpHints()); !strings.Contains(hints, "keep uninstalling") ||
		strings.Contains(hints, "keep updating") {
		t.Fatalf("software stop help retained Update copy: %q", hints)
	}
}

func TestUpdateStartsWithConfirmationBeforePreflightOrSudo(t *testing.T) {
	m, command := (model{tab: 0, cursor: 0}).activateMenuItem()
	if command != nil {
		t.Fatal("opening Update started work before confirmation")
	}
	if !m.updateConfirm || !m.loading {
		t.Fatalf("confirmation state = loading:%t confirm:%t", m.loading, m.updateConfirm)
	}
	if m.sudoChecking || m.updatePreflight || m.scriptRunning {
		t.Fatal("opening Update performed preflight, sudo, or mutation")
	}

	next, command := m.handleUpdateConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if command == nil {
		t.Fatal("confirmed Update did not schedule preflight")
	}
	if m.updateConfirm || !m.updatePreflight || m.sudoChecking {
		t.Fatalf(
			"confirmed state = confirm:%t preflight:%t sudo:%t",
			m.updateConfirm,
			m.updatePreflight,
			m.sudoChecking,
		)
	}
}

func TestUpdateCancellationNeverStartsWork(t *testing.T) {
	m, _ := (model{}).beginUpdateConfirmation(true)
	m.updateChoice = 1
	next, command := m.handleUpdateConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)

	if command == nil {
		t.Fatal("dedicated cancellation did not exit the TUI")
	}
	if !m.updateCanceled {
		t.Fatal("dedicated cancellation lost exit status")
	}
	if m.updatePreflight || m.sudoChecking || m.scriptRunning {
		t.Fatal("canceled Update started preflight, sudo, or mutation")
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
}

func TestUpdateStopConfirmationEscapeKeepsUpdateRunning(t *testing.T) {
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
	if canceled || m.scriptCanceling || m.updateStopConfirm {
		t.Fatal("Escape did not return to the running Update")
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

func TestCanceledUpdateRendersAResultInsteadOfCompletionProgress(t *testing.T) {
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
			if !strings.Contains(content, "UPDATE CANCELED") {
				t.Fatalf("canceled result is missing: %q", content)
			}
			if strings.Contains(content, "100%") ||
				strings.Contains(content, "UPDATED") ||
				strings.Contains(content, "update complete") {
				t.Fatalf("canceled result still claims completion: %q", content)
			}
		})
	}
}

func TestBootISOInterruptionKeysRemainGuarded(t *testing.T) {
	for _, code := range []rune{'c', 'z'} {
		t.Run(string(code), func(t *testing.T) {
			initial := isoInstallerModel{step: isoStepWriting}
			next, command := initial.handleISOKey(
				tea.KeyPressMsg{Code: code, Mod: tea.ModCtrl},
			)
			model := next.(isoInstallerModel)
			if command != nil || !model.shutdownPrompt || model.step != isoStepWriting {
				t.Fatal("boot ISO interruption key bypassed the guarded shutdown flow")
			}
		})
	}
}

func TestDedicatedUpdateReturnsCancellationStatusAfterStopping(t *testing.T) {
	if status := dedicatedUpdateExitCode(model{scriptCanceled: true}); status != 130 {
		t.Fatalf("stopped update status = %d", status)
	}
	if status := dedicatedUpdateExitCode(model{updateCanceled: true}); status != 130 {
		t.Fatalf("preflight cancellation status = %d", status)
	}
	if status := dedicatedUpdateExitCode(model{scriptErr: errors.New("failed")}); status != 1 {
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
}

func TestUpdateCancellationStopsTheOwnedProcessGroup(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "update")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
trap 'exit 0' INT TERM
echo ready
while true; do sleep 1; done
`), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan scriptEvent, 32)
	go runRootScriptStream(ctx, actionUpdate, script, events)

	timer := time.NewTimer(5 * time.Second)
	defer timer.Stop()
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatal("update event stream closed without a result")
			}
			if event.line == "ready" {
				cancel()
			}
			if event.done {
				if !errors.Is(event.err, errScriptCanceled) {
					t.Fatalf("cancellation error = %v", event.err)
				}
				return
			}
		case <-timer.C:
			t.Fatal("update process group did not stop")
		}
	}
}

func TestUnreadableCommandOutputCannotRenderFalseSuccess(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	script := filepath.Join(t.TempDir(), "oversized-output")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
head -c 1100000 /dev/zero | tr '\0' x
`), 0o755); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(context.Background(), actionUpdate, script, events)

	timer := time.NewTimer(5 * time.Second)
	defer timer.Stop()
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatal("output event stream closed without a result")
			}
			if !event.done {
				continue
			}
			if event.err == nil || !strings.Contains(event.err.Error(), "could not read command output") {
				t.Fatalf("oversized output result = %v, want captured read failure", event.err)
			}
			return
		case <-timer.C:
			t.Fatal("oversized command output did not finish")
		}
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
		go runRootScriptStream(context.Background(), actionUpdate, script, events)

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

func TestUpdateConfirmationFitsResponsiveShapes(t *testing.T) {
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
				beginUpdateConfirmation(true)
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
			if !strings.Contains(content, "UPDATE QVOS") ||
				!strings.Contains(content, "Begin") ||
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

func TestISOConfigUsesSharedResponsiveProgress(t *testing.T) {
	previousWidth := canvasW
	t.Cleanup(func() {
		canvasW = previousWidth
	})

	canvasW = 40
	installer := isoInstallerModel{step: isoStepWriting, frame: buildFrames / 2}
	tablet := stripANSI(installer.renderISOStep(layoutTablet))
	if !strings.Contains(tablet, "CONFIG") ||
		!strings.Contains(tablet, "writing installer config") ||
		!strings.Contains(tablet, "%") ||
		!strings.Contains(tablet, "━") ||
		!strings.Contains(tablet, "─") {
		t.Fatalf("tablet ISO progress is missing its shared loading state: %q", tablet)
	}

	canvasW = 30
	mobile := stripANSI(installer.renderISOStep(layoutMobile))
	for _, expected := range []string{"CONFIG", "·", "%"} {
		if !strings.Contains(mobile, expected) {
			t.Fatalf("mobile ISO progress is missing %q: %q", expected, mobile)
		}
	}
	if strings.ContainsAny(mobile, "━─") {
		t.Fatalf("mobile ISO progress should remain compact: %q", mobile)
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
	taglineRow, progressRow := -1, -1
	for index, line := range lines {
		if strings.Contains(line, "· · · · ·") {
			taglineRow = index
		}
		if strings.Contains(line, "UPDATING") {
			progressRow = index
		}
	}
	if taglineRow < 0 || progressRow < 0 || progressRow-taglineRow < 3 {
		t.Fatalf("identity and progress need two centered breathing rows: %q", lines)
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
		!strings.Contains(content, "━━━━━━━━━━━━━") ||
		!strings.Contains(content, "────────────────────") {
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
	t.Setenv("OMARCHY_PATH", "")
	t.Setenv("QVOS_BUILD_SCRIPT", "")
	t.Chdir(t.TempDir())

	script := filepath.Join(home, ".local", "share", "omarchy", "qv", "tui", "bin", "qvos-build")
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

func TestUpdateLogPanelUsesTheExpandedLandscapeBudget(t *testing.T) {
	leftWidth, rightWidth := sideLogColumnWidths(140)
	if leftWidth != 36 || rightWidth != 90 {
		t.Fatalf("log columns = %d/%d, want 36/90", leftWidth, rightWidth)
	}
	if rightWidth <= sideRightMax {
		t.Fatalf("log width = %d, did not exceed generic panel cap %d", rightWidth, sideRightMax)
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
	if bgTerm != "#020202" {
		t.Fatalf("background = %q, want #020202", bgTerm)
	}

	width, height := 100, 30
	view := stripANSI(renderViewport(width, height, "qvOS"))
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
