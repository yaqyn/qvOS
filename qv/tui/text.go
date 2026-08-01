package main

import (
	"strings"

	"github.com/charmbracelet/x/ansi"
)

func trimDisplay(value string, maxWidth int) string {
	if maxWidth < 1 {
		return ""
	}
	return ansi.Truncate(value, maxWidth, "…")
}

func wrapDisplayLines(lines []string, maxWidth int) []string {
	if maxWidth < 1 {
		return nil
	}

	wrapped := make([]string, 0, len(lines))
	for _, line := range lines {
		wrapped = append(wrapped, strings.Split(ansi.Wrap(line, maxWidth, " "), "\n")...)
	}
	return wrapped
}

func renderSearchField(filter string, mode layoutMode) string {
	return renderSearchFieldWidth(filter, inputWidthForMode(mode))
}

func renderSearchFieldWidth(filter string, width int) string {
	value := trimDisplay(strings.TrimSpace(filter), max(1, width))
	if value == "" {
		return sMid.Render("search")
	}
	return sBright.Render(value)
}
