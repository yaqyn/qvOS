package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

const rebootRequiredPrefix = "qvOS action: reboot required:"

type rebootDoneMsg struct {
	err error
}

func (m *model) resetFollowupAction() {
	m.rebootPrompt = false
	m.rebootChoice = 1
	m.rebootReasons = nil
	m.rebooting = false
	m.rebootErr = nil
	m.postActionFlow = false
}

func postActionRunnerPath(script string) (string, error) {
	runner := filepath.Join(filepath.Dir(script), "post-run")
	info, err := os.Stat(runner)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&0o111 == 0 {
		return "", fmt.Errorf("the qvOS post-success runner is unavailable")
	}
	return runner, nil
}

func (m model) startPostActionFlow() (model, tea.Cmd) {
	runner, err := postActionRunnerPath(m.scriptPath)
	if err != nil {
		m.scriptErr = err
		return m, nil
	}
	spec, err := currentActionSpec.ForPostAction()
	if err != nil {
		m.scriptErr = err
		return m, nil
	}
	currentActionSpec = spec
	return m.startPostActionScriptRun(runner)
}

func (m model) startPostActionScriptRun(script string) (model, tea.Cmd) {
	return m.startRootScriptRun(actionGeneric, script)
}

func rebootReasonFromLine(line string) (string, bool) {
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, rebootRequiredPrefix) {
		return "", false
	}
	reason := strings.TrimSpace(strings.TrimPrefix(line, rebootRequiredPrefix))
	if reason == "" {
		reason = "System changes need a reboot"
	}
	return reason, true
}

func (m *model) addRebootReason(reason string) {
	for _, existing := range m.rebootReasons {
		if existing == reason {
			return
		}
	}
	m.rebootReasons = append(m.rebootReasons, reason)
}

func rebootSystemCmd() tea.Cmd {
	return func() tea.Msg {
		output, err := exec.Command("qv-system-reboot").CombinedOutput()
		if err != nil {
			message := strings.Join(strings.Fields(string(output)), " ")
			if message == "" {
				message = err.Error()
			}
			err = fmt.Errorf("%s", message)
		}
		return rebootDoneMsg{err: err}
	}
}

func (m model) handleRebootChoiceKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if m.rebooting {
		return m, nil
	}
	if handleTUILogViewKey(
		msg,
		len(m.scriptLogLines) > 0,
		&m.terminalView,
		&m.logOverlay,
		&m.logCopyStatus,
	) {
		return m, nil
	}
	switch msg.String() {
	case "left", "h", "up", "k", "shift+tab":
		m.rebootChoice = 0
	case "right", "l", "down", "j", "tab":
		m.rebootChoice = 1
	case "esc", "ctrl+c", "ctrl+z":
		return m.leaveRootAction()
	case "enter":
		if m.rebootChoice == 1 {
			return m.leaveRootAction()
		}
		m.rebooting = true
		m.rebootErr = nil
		return m, rebootSystemCmd()
	}
	return m, nil
}

func (m model) renderRebootChoiceFor(mode layoutMode) string {
	if m.rebooting {
		return m.renderPreparingFor()
	}

	title := centerCanvas(sWhite.Render("REBOOT REQUIRED"))
	summary := strings.Join(m.rebootReasons, " · ")
	if summary == "" {
		summary = "System changes need a reboot"
	}
	summaryLines := wrapDisplayLines([]string{summary}, min(42, max(1, canvasW)))
	for index, line := range summaryLines {
		summaryLines[index] = centerCanvas(sGray.Render(line))
	}
	actions := centerCanvas(lipgloss.JoinHorizontal(
		lipgloss.Center,
		renderConfirmationAction("Reboot Now", m.rebootChoice == 0),
		"   ",
		renderConfirmationAction("Later", m.rebootChoice == 1),
	))

	lines := []string{title, ""}
	lines = append(lines, summaryLines...)
	lines = append(lines, "", actions)
	if m.rebootErr != nil {
		errorLines := wrapDisplayLines(
			[]string{errorMessage(m.rebootErr)},
			min(48, max(1, canvasW)),
		)
		lines = append(lines, "")
		for _, line := range errorLines {
			lines = append(lines, centerCanvas(sGray.Render(line)))
		}
	}
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, m.rootPersistentHints()...)
}
