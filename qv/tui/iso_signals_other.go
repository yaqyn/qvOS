//go:build !unix

package main

import tea "charm.land/bubbletea/v2"

func guardISOInstallerSignals(_ *tea.Program) func() {
	return func() {}
}
