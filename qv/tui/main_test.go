package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

func TestInstallMenuContainsOnlySupportedLifecycleActions(t *testing.T) {
	got := sections[0].items
	want := []item{
		{"00", "UPDATE", "Sync qvOS"},
		{"01", "REPAIR", "Repair qvOS"},
		{"02", "BUILD", "Build qvOS ISO"},
	}

	if len(got) != len(want) {
		t.Fatalf("install action count = %d, want %d", len(got), len(want))
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("install action %d = %#v, want %#v", index, got[index], want[index])
		}
	}
}

func TestTweakMenuNamesPersonalSoftwareWithoutLegacyDebloatLanguage(t *testing.T) {
	got := sections[2].items
	want := []item{
		{"00", "KEYBIND", "Edit bindings"},
		{"01", "BROWSER", "Set browser"},
		{"02", "SOFTWARE", "Review personal"},
	}

	if len(got) != len(want) {
		t.Fatalf("tweak action count = %d, want %d", len(got), len(want))
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("tweak action %d = %#v, want %#v", index, got[index], want[index])
		}
	}
}

func TestRepairActionUsesTheQvOSMaintenanceOwner(t *testing.T) {
	script, environment, err := rootScriptSpec(actionRepair)
	if err != nil {
		t.Fatalf("repair action spec: %v", err)
	}
	if script != "bin/qvos-repair" {
		t.Fatalf("repair script = %q", script)
	}
	if environment != "QVOS_REPAIR_SCRIPT" {
		t.Fatalf("repair environment = %q", environment)
	}
	if rootActionName(actionRepair) != "REPAIR" {
		t.Fatalf("repair action name = %q", rootActionName(actionRepair))
	}
	if rootActionCompleteStatus(actionRepair) != "repair complete" {
		t.Fatalf("repair completion = %q", rootActionCompleteStatus(actionRepair))
	}

	status, progress := scriptProgressFromLine(actionRepair, "qvOS repair: Runtime")
	if status != "runtime" || progress <= 0 {
		t.Fatalf("repair progress = %q, %f", status, progress)
	}

	status, progress = scriptProgressFromLine(actionRepair, "qvOS repair: Complete")
	if status != "complete" || progress <= 0 {
		t.Fatalf("repair completion progress = %q, %f", status, progress)
	}
}

func TestUpdateActionUsesTheQvOSMaintenanceOwner(t *testing.T) {
	script, environment, err := rootScriptSpec(actionUpdate)
	if err != nil {
		t.Fatalf("update action spec: %v", err)
	}
	if script != "bin/qvos-update" {
		t.Fatalf("update script = %q", script)
	}
	if environment != "QVOS_UPDATE_SCRIPT" {
		t.Fatalf("update environment = %q", environment)
	}

	status, progress := scriptProgressFromLine(actionUpdate, "Update system packages")
	if status != "updating system packages" || progress <= 0 {
		t.Fatalf("update progress = %q, %f", status, progress)
	}

	status, progress = scriptProgressFromLine(actionUpdate, "qvOS update is complete.")
	if status != "update complete" || progress != 1 {
		t.Fatalf("update completion = %q, %f", status, progress)
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
	if _, _, ok := fitCenteredIconCanvas(desktopMinWidth, desktopMinHeight, 26); ok {
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
