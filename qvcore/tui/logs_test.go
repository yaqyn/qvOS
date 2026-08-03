package main

import (
	"errors"
	"fmt"
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
				VisibleRows: 3,
				Empty:       "waiting for logs",
				Border:      true,
			},
		},
		{
			name: "ISO",
			screen: logPanelScreen{
				Lines:       lines,
				Width:       width,
				VisibleRows: 3,
				Empty:       "waiting for install log",
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			panel := renderLogPanel(test.screen)
			content := stripANSI(panel)
			for _, expected := range []string{"更新 qvOS", "deliberately", "long milestone", "verification complete", "ctrl+v  switch"} {
				if !strings.Contains(content, expected) {
					t.Fatalf("shared log panel is missing %q: %q", expected, content)
				}
			}
			if strings.Contains(content, "…") {
				t.Fatalf("shared log panel truncated owner output: %q", content)
			}
			for index, line := range strings.Split(panel, "\n") {
				if got := lipgloss.Width(line); got > width {
					t.Fatalf("line %d width = %d, want <= %d: %q", index, got, width, line)
				}
			}
		})
	}
}

func TestResponsiveLogWidthUsesTheRequestedSharedColumn(t *testing.T) {
	leftWidth, rightWidth := sideColumnWidths(120)
	left := responsiveTUILogContentWidth(responsiveLogWidth{
		Width: 120, Height: 40, CenterMax: maxCanvasW, Maximum: 82, Border: true,
	})
	right := responsiveTUILogContentWidth(responsiveLogWidth{
		Width: 120, Height: 40, CenterMax: maxCanvasW, Maximum: 82,
		SideRight: true,
	})
	if left != tuiLogPanelContentWidth(leftWidth, true) {
		t.Fatalf("left log content width = %d, want %d", left, tuiLogPanelContentWidth(leftWidth, true))
	}
	if right != tuiLogPanelContentWidth(rightWidth, false) {
		t.Fatalf("right log content width = %d, want %d", right, tuiLogPanelContentWidth(rightWidth, false))
	}

	terminal := responsiveTUILogContentWidth(responsiveLogWidth{
		Width: 120, Height: 40, CenterMax: maxCanvasW, Maximum: 82, Terminal: true,
	})
	if terminal != terminalOutputContentWidth(120) {
		t.Fatalf("terminal log content width = %d, want %d", terminal, terminalOutputContentWidth(120))
	}
}

func TestTerminalFramesRedrawInPlaceWithoutDroppingHistory(t *testing.T) {
	lines := make([]string, 0)
	cursor := 0
	for index := range 300 {
		var added int
		lines, cursor, added = applyTerminalFrame(
			lines,
			cursor,
			terminalFrame{
				line:   fmt.Sprintf("terminal line %03d", index),
				update: true,
				commit: true,
			},
		)
		if added != 1 {
			t.Fatalf("line %d added count = %d, want 1", index, added)
		}
	}

	lines, cursor, _ = applyTerminalFrame(lines, cursor, terminalFrame{
		line: "downloading 12%", update: true, redraw: true,
	})
	lines, cursor, _ = applyTerminalFrame(lines, cursor, terminalFrame{
		line: "downloading 68%", update: true, commit: true,
	})
	if len(lines) != 301 {
		t.Fatalf("retained terminal lines = %d, want 301", len(lines))
	}
	if lines[0] != "terminal line 000" || lines[299] != "terminal line 299" {
		t.Fatalf("terminal history was truncated: first=%q last=%q", lines[0], lines[299])
	}
	if lines[300] != "downloading 68%" {
		t.Fatalf("terminal redraw = %q, want latest frame", lines[300])
	}
}

func TestTerminalFramesReplaceDockerComposeRepaints(t *testing.T) {
	raw := strings.Join([]string{
		"\x1b[?25l[+] up 0/1\r\n",
		" ⠋ Image dockurr/windows Pulling 0.1s\r\n",
		"\x1b[2A\x1b[2K[+] up 1/1\r\n",
		"\x1b[2K ⠙ Image dockurr/windows Pulling 8.4MB\r\n",
		"\x1b[2A\x1b[2K[+] up 1/1\r\n",
		"\x1b[2K ✔ Image dockurr/windows Pulled\r\n\x1b[?25h",
	}, "")
	lines := make([]string, 0)
	cursor := 0
	if err := readTerminalFrames(strings.NewReader(raw), func(frame terminalFrame) error {
		if frame.update {
			frame.line = sanitizeLogLine(frame.line)
		}
		lines, cursor, _ = applyTerminalFrame(lines, cursor, frame)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if len(lines) != 2 || lines[0] != "[+] up 1/1" ||
		lines[1] != " ✔ Image dockurr/windows Pulled" {
		t.Fatalf("Docker Compose terminal frame = %#v", lines)
	}
	if joined := strings.Join(lines, "\n"); strings.Contains(joined, "0.1s") ||
		strings.Contains(joined, "8.4MB") {
		t.Fatalf("Docker Compose repaint history leaked: %q", joined)
	}
}

func TestTerminalFramesApplyScreenClears(t *testing.T) {
	tests := []struct {
		name  string
		clear string
	}{
		{name: "CSI erase display", clear: "\x1b[2J"},
		{name: "CSI erase display and scrollback", clear: "\x1b[3J"},
		{name: "terminal reset", clear: "\x1bc"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			lines := make([]string, 0)
			cursor := 0
			raw := "obsolete\npartial" + test.clear + "current\n"
			if err := readTerminalFrames(strings.NewReader(raw), func(frame terminalFrame) error {
				lines, cursor, _ = applyTerminalFrame(lines, cursor, frame)
				return nil
			}); err != nil {
				t.Fatal(err)
			}
			if len(lines) != 1 || lines[0] != "current" {
				t.Fatalf("cleared terminal frame = %#v", lines)
			}
		})
	}
}

func TestTerminalFramesApplyCursorAddressingAndErase(t *testing.T) {
	raw := "alpha\nbravo\ncharlie\x1b[1;1Homega\x1b[2;3H\x1b[1KX"
	lines := make([]string, 0)
	cursor := 0
	if err := readTerminalFrames(strings.NewReader(raw), func(frame terminalFrame) error {
		lines, cursor, _ = applyTerminalFrame(lines, cursor, frame)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	want := []string{"omega", "  Xvo", "charlie"}
	if strings.Join(lines, "\n") != strings.Join(want, "\n") {
		t.Fatalf("addressed terminal frame = %#v, want %#v", lines, want)
	}
}

func TestTerminalFramesRestoreSavedCursor(t *testing.T) {
	tests := []struct {
		name    string
		save    string
		restore string
	}{
		{name: "escape", save: "\x1b7", restore: "\x1b8"},
		{name: "CSI", save: "\x1b[s", restore: "\x1b[u"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			lines := make([]string, 0)
			cursor := 0
			raw := "first\nsecond" + test.save + "\x1b[1A\x1b[1Gtop" + test.restore + "!"
			if err := readTerminalFrames(strings.NewReader(raw), func(frame terminalFrame) error {
				lines, cursor, _ = applyTerminalFrame(lines, cursor, frame)
				return nil
			}); err != nil {
				t.Fatal(err)
			}
			want := []string{"topst", "second!"}
			if strings.Join(lines, "\n") != strings.Join(want, "\n") {
				t.Fatalf("restored terminal frame = %#v, want %#v", lines, want)
			}
		})
	}
}

func TestTerminalReaderReturnsConsumerError(t *testing.T) {
	want := errors.New("stop consuming terminal output")
	err := readTerminalFrames(strings.NewReader("output\n"), func(terminalFrame) error {
		return want
	})
	if !errors.Is(err, want) {
		t.Fatalf("terminal reader error = %v, want %v", err, want)
	}
}
