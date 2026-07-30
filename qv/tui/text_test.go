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
