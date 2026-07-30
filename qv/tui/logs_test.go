package main

import (
	"strings"
	"testing"

	"charm.land/lipgloss/v2"
)

func TestSharedLogPanelFitsBorderedAndBorderlessConsumers(t *testing.T) {
	const width = 40
	lines := []string{
		"更新 qvOS packages with a deliberately long milestone",
		"verification complete",
	}
	tests := []struct {
		name   string
		screen logPanelScreen
	}{
		{
			name: "update and software",
			screen: logPanelScreen{
				Lines:       lines,
				Width:       width,
				VisibleRows: 2,
				Empty:       "waiting for logs",
				Border:      true,
			},
		},
		{
			name: "ISO",
			screen: logPanelScreen{
				Lines:       lines,
				Width:       width,
				VisibleRows: 2,
				Empty:       "waiting for install log",
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			panel := renderLogPanel(test.screen)
			content := stripANSI(panel)
			for _, expected := range []string{"更新 qvOS", "verification complete", "ctrl+v  switch"} {
				if !strings.Contains(content, expected) {
					t.Fatalf("shared log panel is missing %q: %q", expected, content)
				}
			}
			for index, line := range strings.Split(panel, "\n") {
				if got := lipgloss.Width(line); got > width {
					t.Fatalf("line %d width = %d, want <= %d: %q", index, got, width, line)
				}
			}
		})
	}
}
