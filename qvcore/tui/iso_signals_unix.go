//go:build unix

package main

import (
	"os"
	"os/signal"
	"syscall"

	tea "charm.land/bubbletea/v2"
)

func guardISOInstallerSignals(p *tea.Program) func() {
	signals := make(chan os.Signal, 2)
	done := make(chan struct{})

	signal.Notify(signals, syscall.SIGQUIT, syscall.SIGTSTP)
	go func() {
		for {
			select {
			case <-done:
				return
			case <-signals:
				p.Send(isoExitRequestedMsg{})
			}
		}
	}()

	return func() {
		signal.Stop(signals)
		close(done)
	}
}
