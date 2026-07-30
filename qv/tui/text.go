package main

import "github.com/charmbracelet/x/ansi"

func trimDisplay(value string, maxWidth int) string {
	if maxWidth < 1 {
		return ""
	}
	return ansi.Truncate(value, maxWidth, "…")
}
