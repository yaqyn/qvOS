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
