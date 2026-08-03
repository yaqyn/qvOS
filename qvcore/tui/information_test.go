package main

import (
	"strings"
	"testing"

	"charm.land/lipgloss/v2"
)

func TestInformationFieldsPresentStatusHierarchy(t *testing.T) {
	lines := formatInformationLines(
		"Battery Protection",
		[]string{
			"Battery Protection: Enabled - Mostly plugged in",
			"Hardware: firmware Long Life mode (approximately 50-60%)",
		},
		46,
		false,
	)
	rendered := strings.Join(lines, "\n")
	plain := stripANSI(rendered)
	for _, expected := range []string{
		"STATUS   · Enabled",
		"HARDWARE · Long Life - 50-60%",
	} {
		if !strings.Contains(plain, expected) {
			t.Fatalf("presented information is missing %q: %q", expected, plain)
		}
	}
	for _, styled := range []string{
		sGray.Render("STATUS  "),
		sWhite.Render("Enabled"),
		sWhite.Render("Long Life"),
		sRed.Render("50-60%"),
	} {
		if !strings.Contains(rendered, styled) {
			t.Fatalf("information hierarchy is missing styled value %q", stripANSI(styled))
		}
	}
	for _, noisy := range []string{
		"Mostly plugged in",
		"firmware",
		" mode",
		"approximately",
	} {
		if strings.Contains(plain, noisy) {
			t.Fatalf("information retained noisy copy %q: %q", noisy, plain)
		}
	}
	if strings.Contains(rendered, sRed.Render("STATUS")) {
		t.Fatalf("secondary field label competed with its value: %q", plain)
	}
}

func TestInformationFieldsWrapWithoutClipping(t *testing.T) {
	lines := formatInformationLines(
		"Battery Protection",
		[]string{
			"Battery Protection: Enabled - Mostly plugged in",
			"Hardware: firmware Long Life mode (approximately 50-60%)",
		},
		24,
		false,
	)
	rendered := strings.Join(lines, "\n")
	if strings.Contains(rendered, "…") {
		t.Fatalf("information was clipped instead of wrapped: %q", stripANSI(rendered))
	}
	for _, line := range lines {
		if width := lipgloss.Width(line); width > 24 {
			t.Fatalf("information line width = %d: %q", width, stripANSI(line))
		}
	}
	if len(lines) < 3 {
		t.Fatalf("narrow information did not expand into readable rows: %q", stripANSI(rendered))
	}
}

func TestInformationReportUsesAReadableGridAndTrailingProse(t *testing.T) {
	lines := formatInformationLines(
		"Battery Protection",
		[]string{
			"Battery Protection: Enabled - Mostly plugged in",
			"Hardware: firmware Long Life mode (approximately 50-60%)",
			"Batteries: 1",
			"Battery 1:",
			"UPower support: yes",
			"Supported settings mask: 4",
			"UPower enabled: true",
			"Kernel charge mode: Long_Life",
			"Firmware range: approximately 50-60%",
			"qvOS hwdb override: absent",
			"Conflicting charging manager: none active",
			"Report privacy: serials, DMI data, and native paths omitted",
		},
		46,
		false,
	)
	plainLines := make([]string, len(lines))
	for index, line := range lines {
		plainLines[index] = stripANSI(line)
	}
	plain := strings.Join(plainLines, "\n")

	var hardwareLine, rangeLine string
	privacyIndex := -1
	for index, line := range plainLines {
		switch {
		case strings.Contains(line, "HARDWARE"):
			hardwareLine = line
		case strings.TrimSpace(line) == "50-60%" && rangeLine == "":
			rangeLine = line
		case strings.Contains(line, "Report Privacy:"):
			privacyIndex = index
		}
	}
	if hardwareLine == "" || rangeLine == "" {
		t.Fatalf("report hardware hierarchy is missing: %q", plain)
	}
	valueColumn := strings.Index(hardwareLine, "Long Life")
	if valueColumn < 0 || strings.Index(rangeLine, "50-60%") != valueColumn {
		t.Fatalf(
			"hardware threshold is not aligned under its value: %q / %q",
			hardwareLine,
			rangeLine,
		)
	}
	if !strings.Contains(hardwareLine, " - Long Life") {
		t.Fatalf("report field does not use a normal dash: %q", hardwareLine)
	}
	if privacyIndex < 1 || strings.TrimSpace(plainLines[privacyIndex-1]) != "" {
		t.Fatalf("report prose is not separated from the field grid: %q", plain)
	}
	normalized := strings.Join(strings.Fields(plain), " ")
	if !strings.Contains(
		normalized,
		"Report Privacy: Serials, DMI Data, & Native paths omitted",
	) {
		t.Fatalf("report privacy is not presented as clear prose: %q", plain)
	}
	if strings.Contains(plain, "Battery 1") {
		t.Fatalf("single-battery report retained a redundant section: %q", plain)
	}
	for _, noisy := range []string{
		"REPORT PRIVACY",
		"approximately",
		"Long_Life",
		"50-\n60%",
	} {
		if strings.Contains(plain, noisy) {
			t.Fatalf("report retained noisy output %q: %q", noisy, plain)
		}
	}
	if len(lines) > 16 {
		t.Fatalf("normal report needs %d rows, want at most 16: %q", len(lines), plain)
	}

	var gridLine, proseLine string
	for _, line := range plainLines {
		switch {
		case strings.Contains(line, "CONFLICTING CHARGING MANAGER"):
			gridLine = line
		case strings.Contains(line, "paths omitted"):
			proseLine = line
		}
	}
	for name, line := range map[string]string{
		"grid":  gridLine,
		"prose": proseLine,
	} {
		if line == "" {
			t.Fatalf("centered report %s is missing: %q", name, plain)
		}
		left := len(line) - len(strings.TrimLeft(line, " "))
		right := len(line) - len(strings.TrimRight(line, " "))
		if difference := left - right; difference < -1 || difference > 1 {
			t.Fatalf(
				"report %s is not independently centered: left=%d right=%d",
				name,
				left,
				right,
			)
		}
	}
}

func TestInformationReportSeparatesMultipleCollectionMembers(t *testing.T) {
	lines := formatInformationLines(
		"Battery Protection",
		[]string{
			"Batteries: 2",
			"Battery 1:",
			"UPower support: yes",
			"Battery 2:",
			"UPower support: no",
		},
		46,
		false,
	)
	plain := stripANSI(strings.Join(lines, "\n"))
	for _, expected := range []string{"<Battery 1>", "<Battery 2>"} {
		if !strings.Contains(plain, expected) {
			t.Fatalf("multi-battery report is missing %q: %q", expected, plain)
		}
	}
	for _, line := range strings.Split(plain, "\n") {
		if !strings.Contains(line, "<Battery ") {
			continue
		}
		left := len(line) - len(strings.TrimLeft(line, " "))
		right := len(line) - len(strings.TrimRight(line, " "))
		if difference := left - right; difference < -1 || difference > 1 {
			t.Fatalf(
				"battery section is not centered: left=%d right=%d line=%q",
				left,
				right,
				line,
			)
		}
	}

	generic := stripANSI(strings.Join(formatInformationLines(
		"Devices",
		[]string{
			"Devices: 2",
			"Device 1:",
			"Status: ready",
			"Device 2:",
			"Status: ready",
		},
		46,
		false,
	), "\n"))
	for _, expected := range []string{"<Device 1>", "<Device 2>"} {
		if !strings.Contains(generic, expected) {
			t.Fatalf("generic collection report is missing %q: %q", expected, generic)
		}
	}
}

func TestInformationScreenCentersAlignedFieldsAsOneBlock(t *testing.T) {
	previousWidth := canvasW
	t.Cleanup(func() {
		canvasW = previousWidth
	})
	canvasW = 46

	rendered := stripANSI(renderInformationScreen(informationScreen{
		Title: "Battery Protection",
		Lines: []string{
			"Battery Protection: Enabled - Mostly plugged in",
			"Hardware: firmware Long Life mode (approximately 50-60%)",
		},
		Width:       46,
		VisibleRows: 4,
	}))

	var statusLine, hardwareLine string
	for _, line := range strings.Split(rendered, "\n") {
		switch {
		case strings.Contains(line, "STATUS"):
			statusLine = line
		case strings.Contains(line, "HARDWARE"):
			hardwareLine = line
		}
	}
	if statusLine == "" || hardwareLine == "" {
		t.Fatalf("centered information fields are missing: %q", rendered)
	}

	statusIndent := len(statusLine) - len(strings.TrimLeft(statusLine, " "))
	hardwareIndent := len(hardwareLine) - len(strings.TrimLeft(hardwareLine, " "))
	if statusIndent != hardwareIndent {
		t.Fatalf(
			"information rows do not share a left guide: status=%d hardware=%d",
			statusIndent,
			hardwareIndent,
		)
	}
	if hardwareIndent < 2 {
		t.Fatalf("information block remained pinned left: %q", hardwareLine)
	}

	hardwareRight := len(hardwareLine) - len(strings.TrimRight(hardwareLine, " "))
	if difference := hardwareIndent - hardwareRight; difference < -1 || difference > 1 {
		t.Fatalf(
			"information block is not horizontally centered: left=%d right=%d",
			hardwareIndent,
			hardwareRight,
		)
	}
}
