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
		"STATUS",
		"Enabled",
		"Mostly plugged in",
		"HARDWARE",
		"firmware Long Life mode",
		"approximately 50-60%",
	} {
		if !strings.Contains(plain, expected) {
			t.Fatalf("presented information is missing %q: %q", expected, plain)
		}
	}
	for _, styled := range []string{
		sRed.Render("STATUS"),
		sHot.Render("Enabled"),
		sWhite.Render("firmware Long Life mode"),
		sRed.Render("approximately 50-60%"),
	} {
		if !strings.Contains(rendered, styled) {
			t.Fatalf("information hierarchy is missing styled value %q", stripANSI(styled))
		}
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
	if len(lines) <= 4 {
		t.Fatalf("narrow information did not expand into readable rows: %q", stripANSI(rendered))
	}
}
