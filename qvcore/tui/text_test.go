package main

import (
	"strings"
	"testing"

	"charm.land/lipgloss/v2"
)

func TestTrimDisplayUsesTerminalCellWidth(t *testing.T) {
	tests := []struct {
		name     string
		value    string
		maxWidth int
	}{
		{"wide characters", "更新 qvOS packages", 10},
		{"emoji grapheme", "ready 🔴 for update", 12},
		{"combining grapheme", "Cafe\u0301 update complete", 12},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			rendered := trimDisplay(test.value, test.maxWidth)
			if width := lipgloss.Width(rendered); width > test.maxWidth {
				t.Fatalf("trimmed width = %d, want <= %d: %q", width, test.maxWidth, rendered)
			}
			if !strings.HasSuffix(rendered, "…") {
				t.Fatalf("truncated value is missing its ellipsis: %q", rendered)
			}
		})
	}
}

func TestWrapDisplayLinesPreservesInformationWithoutEllipses(t *testing.T) {
	lines := wrapDisplayLines([]string{
		"Battery Protection: Enabled - Mostly plugged in",
		"Hardware: firmware Long Life mode (approximately 50-60%)",
	}, 24)
	rendered := strings.Join(lines, "\n")
	for _, expected := range []string{
		"Battery Protection:",
		"Mostly plugged",
		"Hardware: firmware Long",
		"50-60%",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("wrapped information is missing %q: %q", expected, rendered)
		}
	}
	if strings.Contains(rendered, "…") {
		t.Fatalf("wrapped information was truncated: %q", rendered)
	}
	for _, line := range lines {
		if width := lipgloss.Width(line); width > 24 {
			t.Fatalf("wrapped line width = %d: %q", width, line)
		}
	}
}

func TestRenderTUIRailOwnsOneThinSharedGlyph(t *testing.T) {
	if got := renderTUIRail(4, sRed); got != sRed.Render("────") {
		t.Fatalf("shared rail = %q, want one thin styled glyph", got)
	}
	if got := renderTUIRail(0, sRed); got != "" {
		t.Fatalf("empty shared rail = %q, want empty", got)
	}
}
