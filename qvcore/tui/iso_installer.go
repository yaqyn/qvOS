package main

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type isoStep int

const (
	isoStepRegional isoStep = iota
	isoStepAccount
	isoStepDisk
	isoStepWriting
	isoStepError
)

type isoRegionalField int

const (
	isoRegionalKeyboard isoRegionalField = iota
	isoRegionalTimezone
	isoRegionalFieldCount
)

type isoAccountField int

const (
	isoAccountUsername isoAccountField = iota
	isoAccountHostname
	isoAccountPassword
	isoAccountPasswordConfirm
	isoAccountFieldCount
)

type isoDiskConfirmationAction int

const (
	isoDiskConfirmationBack isoDiskConfirmationAction = iota
	isoDiskConfirmationContinue
	isoDiskConfirmationActionCount
)

type isoChoice struct {
	Label string
	Value string
}

type isoDiskChoice struct {
	Choice    isoChoice
	SizeBytes int64
}

type isoInstallerModel struct {
	step              isoStep
	frame             int
	width, height     int
	preview           bool
	filter            []rune
	username          []rune
	hostname          []rune
	password          []rune
	passwordConfirm   []rune
	regionalFocus     isoRegionalField
	accountFocus      isoAccountField
	choiceIndex       int
	diskConfirm       bool
	diskConfirmAction isoDiskConfirmationAction
	shutdownPrompt    bool
	shutdownChoice    int
	allowQuit         bool
	errorText         string
	helpOverlay       bool
	keyboards         []isoChoice
	timezones         []isoChoice
	disks             []isoDiskChoice
	config            isoInstallerConfig
	repeatKey         string
	repeatPending     tea.KeyPressMsg
	repeatPendingSet  bool
	repeatSuppressing bool
	repeatGeneration  uint64
	repeatReleaseKey  string
	repeatReleaseSet  bool
	repeatReleaseGen  uint64
	repeatLastPressAt time.Time
}

type isoInstallerDoneMsg struct {
	err error
}

type isoExitRequestedMsg struct{}

type isoPowerOffDoneMsg struct {
	err error
}

type isoRepeatGuardTimerMsg struct {
	generation uint64
}

type isoRepeatReleaseTimerMsg struct {
	generation uint64
}

const (
	isoRepeatBurstWindow   = 100 * time.Millisecond
	isoRepeatReleaseWindow = 10 * time.Millisecond
	isoFastEnterTapWindow  = 200 * time.Millisecond
)

func runISOInstaller(preview ...bool) error {
	if err := ensureISOInstallerRuntime(); err != nil {
		return err
	}

	p := newTUIProgram(newISOInstallerModel(preview...), tea.WithFilter(filterISOInstallerExitMessages))
	stopSignals := guardISOInstallerSignals(p)
	defer stopSignals()

	_, err := p.Run()
	return err
}

func filterISOInstallerExitMessages(model tea.Model, msg tea.Msg) tea.Msg {
	switch msg.(type) {
	case tea.QuitMsg:
		if isoModel, ok := model.(isoInstallerModel); ok && isoModel.allowQuit {
			return msg
		}
		return isoExitRequestedMsg{}
	case tea.InterruptMsg, tea.SuspendMsg:
		return isoExitRequestedMsg{}
	default:
		return msg
	}
}

func ensureISOInstallerRuntime() error {
	for _, commandName := range []string{"findmnt", "loadkeys", "lspci", "lsblk", "openssl", "timedatectl"} {
		if _, err := exec.LookPath(commandName); err != nil {
			return fmt.Errorf("qvOS ISO installer requires %s", commandName)
		}
	}
	out, err := exec.Command("lspci", "-nn").Output()
	if err != nil {
		return fmt.Errorf("qvOS ISO installer could not inspect PCI hardware: %w", err)
	}
	if isoT2Pattern.Match(out) {
		return fmt.Errorf("qvOS cannot safely install on T2 Macs because their required third-party packages are not verifiably signed")
	}
	return nil
}

func newISOInstallerModel(preview ...bool) isoInstallerModel {
	keyboards := isoKeyboardChoices()
	timezones := isoTimezoneChoices()
	disks := isoDiskChoices()
	previewMode := len(preview) > 0 && preview[0]
	keyboard := "us"
	timezone := "UTC"
	if len(timezones) > 0 {
		timezone = timezones[0].Value
	}

	return isoInstallerModel{
		step:        isoStepRegional,
		preview:     previewMode,
		keyboards:   keyboards,
		timezones:   timezones,
		disks:       disks,
		hostname:    []rune(isoInstallerDefaultHostname),
		choiceIndex: indexChoiceValue(keyboards, keyboard),
		config: isoInstallerConfig{
			Keyboard:            keyboard,
			Hostname:            isoInstallerDefaultHostname,
			Timezone:            timezone,
			EncryptInstallation: true,
			Kernel:              "linux",
		},
	}
}

func (m isoInstallerModel) Init() tea.Cmd {
	return initialTUICommand(tick())
}

func (m isoInstallerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case isoInstallerDoneMsg:
		if msg.err != nil {
			m.step = isoStepError
			m.errorText = "could not prepare the installation"
			return m, nil
		}
		m.allowQuit = true
		return m, tea.Quit
	case isoExitRequestedMsg:
		return m.requestISOExit()
	case isoPowerOffDoneMsg:
		if msg.err != nil {
			m.shutdownPrompt = true
			m.shutdownChoice = 0
			m.errorText = "could not shut down"
		}
		return m, nil
	case isoRepeatGuardTimerMsg:
		return m.handleISORepeatGuardTimer(msg)
	case isoRepeatReleaseTimerMsg:
		return m.handleISORepeatReleaseTimer(msg)
	case tea.KeyReleaseMsg:
		return m.handleISORepeatRelease(msg)
	case tea.KeyPressMsg:
		return m.handleISOKeyPress(msg)
	}
	return m, nil
}

func (m isoInstallerModel) handleISOKeyPress(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	commands := make([]tea.Cmd, 0, 2)
	m.cancelISORepeatRelease(msg.String())
	if m.repeatPendingSet && msg.String() != m.repeatKey {
		var command tea.Cmd
		m, command = m.commitISOPendingRepeat()
		commands = append(commands, command)
	}

	if !m.isISORepeatAllowedKey(msg) {
		allow, command := m.guardISORepeatPress(msg)
		commands = append(commands, command)
		if !allow {
			return m, tea.Batch(commands...)
		}
	} else {
		m.resetISORepeatGuard()
	}

	next, command := m.handleISOResolvedKey(msg)
	commands = append(commands, command)
	return next, tea.Batch(commands...)
}

func (m isoInstallerModel) handleISOResolvedKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if !m.shutdownPrompt {
		if helpOverlay, handled := handleTUIHelpKeyWithQuestion(
			m.helpOverlay,
			msg,
			!m.capturesTextInput(),
		); handled {
			m.helpOverlay = helpOverlay
			return m, nil
		}
	}
	return m.handleISOKey(msg)
}

func (m isoInstallerModel) isISORepeatAllowedKey(msg tea.KeyPressMsg) bool {
	switch msg.String() {
	case "up", "down":
		return !m.shutdownPrompt && !m.helpOverlay && m.step == isoStepRegional
	case "backspace", "ctrl+h", "ctrl+u":
		return m.capturesTextInput()
	}
	return m.capturesTextInput() && msg.Key().Text != ""
}

func (m *isoInstallerModel) guardISORepeatPress(msg tea.KeyPressMsg) (bool, tea.Cmd) {
	key := msg.String()
	now := time.Now()
	if msg.Key().IsRepeat {
		m.repeatKey = key
		m.repeatPending = tea.KeyPressMsg{}
		m.repeatPendingSet = false
		m.repeatSuppressing = true
		return false, m.restartISORepeatGuardTimer()
	}

	if key != m.repeatKey {
		m.resetISORepeatGuard()
		m.repeatKey = key
		m.repeatLastPressAt = now
		return true, nil
	}
	if m.repeatSuppressing {
		return false, m.restartISORepeatGuardTimer()
	}
	if m.repeatPendingSet {
		m.repeatPending = tea.KeyPressMsg{}
		m.repeatPendingSet = false
		m.repeatSuppressing = true
		return false, m.restartISORepeatGuardTimer()
	}
	if key == "enter" && now.Sub(m.repeatLastPressAt) < isoFastEnterTapWindow {
		m.repeatLastPressAt = now
		return true, nil
	}

	m.repeatPending = msg
	m.repeatPendingSet = true
	m.repeatLastPressAt = now
	return false, m.restartISORepeatGuardTimer()
}

func (m *isoInstallerModel) restartISORepeatGuardTimer() tea.Cmd {
	m.repeatGeneration++
	generation := m.repeatGeneration
	return tea.Tick(isoRepeatBurstWindow, func(time.Time) tea.Msg {
		return isoRepeatGuardTimerMsg{generation: generation}
	})
}

func (m *isoInstallerModel) resetISORepeatGuard() {
	m.repeatGeneration++
	m.repeatKey = ""
	m.repeatPending = tea.KeyPressMsg{}
	m.repeatPendingSet = false
	m.repeatSuppressing = false
	m.repeatLastPressAt = time.Time{}
	m.cancelISORepeatRelease("")
}

func (m isoInstallerModel) handleISORepeatGuardTimer(msg isoRepeatGuardTimerMsg) (tea.Model, tea.Cmd) {
	if msg.generation != m.repeatGeneration {
		return m, nil
	}
	if m.repeatSuppressing {
		m.resetISORepeatGuard()
		return m, nil
	}
	if !m.repeatPendingSet {
		return m, nil
	}
	return m.commitISOPendingRepeat()
}

func (m isoInstallerModel) commitISOPendingRepeat() (isoInstallerModel, tea.Cmd) {
	msg := m.repeatPending
	m.repeatPending = tea.KeyPressMsg{}
	m.repeatPendingSet = false
	next, command := m.handleISOResolvedKey(msg)
	return next.(isoInstallerModel), command
}

func (m isoInstallerModel) handleISORepeatRelease(msg tea.KeyReleaseMsg) (tea.Model, tea.Cmd) {
	key := msg.String()
	if key == "" || key != m.repeatKey {
		return m, nil
	}
	m.repeatReleaseGen++
	generation := m.repeatReleaseGen
	m.repeatReleaseKey = key
	m.repeatReleaseSet = true
	return m, tea.Tick(isoRepeatReleaseWindow, func(time.Time) tea.Msg {
		return isoRepeatReleaseTimerMsg{generation: generation}
	})
}

func (m isoInstallerModel) handleISORepeatReleaseTimer(msg isoRepeatReleaseTimerMsg) (tea.Model, tea.Cmd) {
	if msg.generation != m.repeatReleaseGen || !m.repeatReleaseSet {
		return m, nil
	}
	m.resetISORepeatGuard()
	return m, nil
}

func (m *isoInstallerModel) cancelISORepeatRelease(key string) {
	if key != "" && (!m.repeatReleaseSet || key != m.repeatReleaseKey) {
		return
	}
	m.repeatReleaseGen++
	m.repeatReleaseKey = ""
	m.repeatReleaseSet = false
}

func (m isoInstallerModel) handleISOKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if m.shutdownPrompt {
		return m.handleISOShutdownKey(msg)
	}

	if isISOExitKey(msg) {
		return m.requestISOExit()
	}

	if m.step == isoStepWriting {
		return m, nil
	}
	if m.step == isoStepError {
		switch msg.String() {
		case "enter", "esc":
			return m, tea.Quit
		}
		return m, nil
	}
	switch m.step {
	case isoStepRegional:
		return m.handleISORegionalKey(msg)
	case isoStepAccount:
		return m.handleISOAccountKey(msg)
	case isoStepDisk:
		if m.diskConfirm {
			return m.handleISODiskConfirmationKey(msg)
		}
		return m.handleISODiskKey(msg)
	}
	return m, nil
}

func (m isoInstallerModel) requestISOExit() (tea.Model, tea.Cmd) {
	m.shutdownPrompt = true
	m.shutdownChoice = 0
	m.errorText = ""
	return m, nil
}

func isISOExitKey(msg tea.KeyPressMsg) bool {
	switch msg.String() {
	case "ctrl+c", "ctrl+d", "ctrl+z", "ctrl+\\", "ctrl+q":
		return true
	default:
		return false
	}
}

func (m isoInstallerModel) handleISOShutdownKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "left", "up":
		if m.shutdownChoice > 0 {
			m.shutdownChoice--
		}
	case "right", "down":
		if m.shutdownChoice < len(isoShutdownChoices())-1 {
			m.shutdownChoice++
		}
	case "ctrl+c", "ctrl+z":
		m.shutdownChoice = indexChoiceValue(isoShutdownChoices(), "shutdown")
		if m.preview {
			return m, tea.Quit
		}
		return m, powerOffCmd()
	case "enter":
		choices := isoShutdownChoices()
		if m.shutdownChoice >= 0 && m.shutdownChoice < len(choices) &&
			choices[m.shutdownChoice].Value == "shutdown" {
			if m.preview {
				return m, tea.Quit
			}
			return m, powerOffCmd()
		}
		m.shutdownPrompt = false
		m.shutdownChoice = 0
	}
	return m, nil
}

func (m isoInstallerModel) handleISORegionalKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	choices := m.filteredChoices()
	switch msg.String() {
	case "esc":
		if m.regionalFocus == isoRegionalTimezone {
			m.setISORegionalFocus(isoRegionalKeyboard)
			return m, nil
		}
		return m.requestISOExit()
	case "tab", "right":
		m.setISORegionalFocus(isoRegionalField(cycleISOIndex(
			int(m.regionalFocus), int(isoRegionalFieldCount), 1,
		)))
		return m, nil
	case "shift+tab", "left":
		m.setISORegionalFocus(isoRegionalField(cycleISOIndex(
			int(m.regionalFocus), int(isoRegionalFieldCount), -1,
		)))
		return m, nil
	case "up":
		if m.choiceIndex > 0 {
			m.choiceIndex--
		}
	case "down":
		if m.choiceIndex < len(choices)-1 {
			m.choiceIndex++
		}
	case "enter":
		if len(choices) == 0 {
			m.errorText = ""
			return m, nil
		}
		return m.submitISORegionalChoice(choices[m.choiceIndex])
	case "backspace", "ctrl+h":
		m.backspaceISOFilter()
	case "ctrl+u":
		m.clearISOFilter()
	default:
		if text := msg.Key().Text; text != "" {
			m.appendISOFilter(text)
		}
	}
	m.clampISOChoiceIndex(len(choices))
	return m, nil
}

func (m *isoInstallerModel) setISORegionalFocus(focus isoRegionalField) {
	m.regionalFocus = focus
	clearRunes(m.filter)
	m.filter = nil
	m.errorText = ""
	if focus == isoRegionalTimezone {
		m.choiceIndex = indexChoiceValue(m.timezones, m.config.Timezone)
	} else {
		m.choiceIndex = indexChoiceValue(m.keyboards, m.config.Keyboard)
	}
}

func (m isoInstallerModel) submitISORegionalChoice(choice isoChoice) (tea.Model, tea.Cmd) {
	m.filter = nil
	m.errorText = ""
	if m.regionalFocus == isoRegionalKeyboard {
		if !m.preview {
			if err := loadISOKeyboard(choice.Value); err != nil {
				m.errorText = "try another keyboard layout"
				return m, nil
			}
		}
		m.config.Keyboard = choice.Value
		m.setISORegionalFocus(isoRegionalTimezone)
		return m, nil
	}

	m.config.Timezone = choice.Value
	m.step = isoStepAccount
	m.accountFocus = isoAccountUsername
	return m, nil
}

func (m isoInstallerModel) handleISOAccountKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	active := m.activeISOAccountInput()
	switch msg.String() {
	case "esc":
		if m.accountFocus > isoAccountUsername {
			m.accountFocus--
			m.errorText = ""
			return m, nil
		}
		clearRunes(m.password)
		m.password = nil
		clearRunes(m.passwordConfirm)
		m.passwordConfirm = nil
		m.step = isoStepRegional
		m.setISORegionalFocus(isoRegionalTimezone)
		return m, nil
	case "tab", "down", "right":
		m.accountFocus = isoAccountField(cycleISOIndex(
			int(m.accountFocus), int(isoAccountFieldCount), 1,
		))
		m.errorText = ""
		return m, nil
	case "shift+tab", "up", "left":
		m.accountFocus = isoAccountField(cycleISOIndex(
			int(m.accountFocus), int(isoAccountFieldCount), -1,
		))
		m.errorText = ""
		return m, nil
	case "enter":
		return m.submitISOAccountField()
	case "backspace", "ctrl+h":
		if len(*active) > 0 {
			(*active)[len(*active)-1] = 0
			*active = (*active)[:len(*active)-1]
			m.errorText = ""
		}
	case "ctrl+u":
		clearRunes(*active)
		*active = nil
		m.errorText = ""
	default:
		if text := msg.Key().Text; text != "" {
			switch m.accountFocus {
			case isoAccountUsername:
				m.username = appendISOUsernameText(m.username, text)
			case isoAccountHostname:
				m.hostname = appendISOHostnameText(m.hostname, text)
			default:
				*active = append(*active, []rune(text)...)
			}
			m.errorText = ""
		}
	}
	return m, nil
}

func (m *isoInstallerModel) activeISOAccountInput() *[]rune {
	switch m.accountFocus {
	case isoAccountHostname:
		return &m.hostname
	case isoAccountPassword:
		return &m.password
	case isoAccountPasswordConfirm:
		return &m.passwordConfirm
	default:
		return &m.username
	}
}

func appendISOUsernameText(current []rune, text string) []rune {
	for _, char := range strings.ToLower(text) {
		if len(current) == 0 {
			if (char >= 'a' && char <= 'z') || char == '_' {
				current = append(current, char)
			}
			continue
		}
		if current[len(current)-1] == '$' {
			continue
		}
		if (char >= 'a' && char <= 'z') ||
			(char >= '0' && char <= '9') || char == '_' || char == '-' || char == '$' {
			current = append(current, char)
		}
	}
	return current
}

func appendISOHostnameText(current []rune, text string) []rune {
	for _, char := range text {
		letter := (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
		digit := char >= '0' && char <= '9'
		if letter || digit || (char == '-' && len(current) > 0) {
			current = append(current, char)
		}
	}
	return current
}

func (m isoInstallerModel) submitISOAccountField() (tea.Model, tea.Cmd) {
	switch m.accountFocus {
	case isoAccountUsername:
		username := strings.ToLower(strings.TrimSpace(string(m.username)))
		if !validISOUsername(username) {
			m.errorText = "enter a username"
			return m, nil
		}
		m.username = []rune(username)
		m.config.Username = username
		m.accountFocus = isoAccountHostname
	case isoAccountHostname:
		hostname := strings.TrimSpace(string(m.hostname))
		if !validISOHostname(hostname) {
			m.errorText = "check the machine name"
			return m, nil
		}
		m.config.Hostname = hostname
		m.accountFocus = isoAccountPassword
	case isoAccountPassword:
		if len(m.password) == 0 {
			m.errorText = "enter a password"
			return m, nil
		}
		m.accountFocus = isoAccountPasswordConfirm
	case isoAccountPasswordConfirm:
		username := strings.ToLower(strings.TrimSpace(string(m.username)))
		if !validISOUsername(username) {
			m.accountFocus = isoAccountUsername
			m.errorText = "enter a username"
			return m, nil
		}
		hostname := strings.TrimSpace(string(m.hostname))
		if !validISOHostname(hostname) {
			m.accountFocus = isoAccountHostname
			m.errorText = "check the machine name"
			return m, nil
		}
		if len(m.password) == 0 {
			m.accountFocus = isoAccountPassword
			m.errorText = "enter a password"
			return m, nil
		}
		if string(m.passwordConfirm) != string(m.password) {
			m.errorText = "make sure passwords match"
			clearRunes(m.passwordConfirm)
			m.passwordConfirm = nil
			return m, nil
		}
		m.config.Username = username
		m.config.Hostname = hostname
		clearRunes(m.passwordConfirm)
		m.passwordConfirm = nil
		m.accountFocus = isoAccountUsername
		m.step = isoStepDisk
		m.choiceIndex = 0
		m.filter = nil
	}
	m.errorText = ""
	return m, nil
}

func (m isoInstallerModel) handleISODiskConfirmationKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "left", "up", "shift+tab":
		m.diskConfirmAction = isoDiskConfirmationAction(cycleISOIndex(
			int(m.diskConfirmAction), int(isoDiskConfirmationActionCount), -1,
		))
		return m, nil
	case "right", "down", "tab":
		m.diskConfirmAction = isoDiskConfirmationAction(cycleISOIndex(
			int(m.diskConfirmAction), int(isoDiskConfirmationActionCount), 1,
		))
		return m, nil
	case "esc":
		return m.returnToISODiskSelection()
	case "enter":
		if m.diskConfirmAction == isoDiskConfirmationBack {
			return m.returnToISODiskSelection()
		}
		password := append([]rune(nil), m.password...)
		clearRunes(m.password)
		m.password = nil
		m.step = isoStepWriting
		m.errorText = ""
		if m.preview {
			clearRunes(password)
			m.allowQuit = true
			return m, tea.Quit
		}
		return m, writeISOInstallerOutputCmd(m.config, password)
	}
	return m, nil
}

func (m isoInstallerModel) returnToISODiskSelection() (tea.Model, tea.Cmd) {
	m.diskConfirm = false
	m.diskConfirmAction = isoDiskConfirmationBack
	m.filter = nil
	m.errorText = ""
	return m, nil
}

func (m isoInstallerModel) handleISODiskKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	choices := m.filteredChoices()
	switch msg.String() {
	case "esc":
		m.step = isoStepAccount
		m.accountFocus = isoAccountPasswordConfirm
		m.filter = nil
		m.errorText = ""
		return m, nil
	case "up", "left":
		m.choiceIndex = cycleISOIndex(m.choiceIndex, len(choices), -1)
	case "down", "right", "tab":
		m.choiceIndex = cycleISOIndex(m.choiceIndex, len(choices), 1)
	case "shift+tab":
		m.choiceIndex = cycleISOIndex(m.choiceIndex, len(choices), -1)
	case "enter":
		if len(choices) == 0 {
			m.errorText = "no matching choices"
			return m, nil
		}
		return m.submitISODiskChoice(choices[m.choiceIndex])
	case "backspace", "ctrl+h":
		m.backspaceISOFilter()
	case "ctrl+u":
		m.clearISOFilter()
	default:
		if text := msg.Key().Text; text != "" {
			m.appendISOFilter(text)
		}
	}
	m.clampISOChoiceIndex(len(choices))
	return m, nil
}

func (m *isoInstallerModel) appendISOFilter(text string) {
	m.filter = append(m.filter, []rune(text)...)
	m.choiceIndex = 0
	m.errorText = ""
}

func (m *isoInstallerModel) backspaceISOFilter() {
	if len(m.filter) > 0 {
		m.filter[len(m.filter)-1] = 0
		m.filter = m.filter[:len(m.filter)-1]
	}
	m.choiceIndex = 0
	m.errorText = ""
}

func (m *isoInstallerModel) clearISOFilter() {
	clearRunes(m.filter)
	m.filter = nil
	m.choiceIndex = 0
	m.errorText = ""
}

func (m isoInstallerModel) submitISODiskChoice(choice isoChoice) (tea.Model, tea.Cmd) {
	m.config.Disk = choice.Value
	m.config.DiskSizeBytes = m.diskSizeFor(choice.Value)
	if m.config.DiskSizeBytes < isoInstallerMinimumDiskSize {
		m.errorText = "choose a drive with at least " + formatISOBytes(isoInstallerMinimumDiskSize)
		return m, nil
	}
	m.config.EncryptInstallation = true
	m.diskConfirm = true
	m.diskConfirmAction = isoDiskConfirmationBack
	m.filter = nil
	m.errorText = ""
	return m, nil
}

func (m *isoInstallerModel) clampISOChoiceIndex(choiceCount int) {
	if m.choiceIndex >= choiceCount {
		m.choiceIndex = choiceCount - 1
	}
	if m.choiceIndex < 0 {
		m.choiceIndex = 0
	}
}

func cycleISOIndex(current, count, delta int) int {
	if count < 1 {
		return 0
	}
	next := (current + delta) % count
	if next < 0 {
		next += count
	}
	return next
}

func writeISOInstallerOutputCmd(cfg isoInstallerConfig, password []rune) tea.Cmd {
	return func() tea.Msg {
		defer clearRunes(password)

		hash, err := hashISOInstallerPassword(password)
		if err != nil {
			return isoInstallerDoneMsg{err: err}
		}

		cfg.Password = string(password)
		cfg.PasswordHash = hash
		cfg.Kernel = "linux"
		return isoInstallerDoneMsg{err: writeISOInstallerFiles(".", cfg)}
	}
}

func powerOffCmd() tea.Cmd {
	return func() tea.Msg {
		if err := exec.Command("systemctl", "poweroff").Run(); err == nil {
			return nil
		}
		if err := exec.Command("poweroff").Run(); err != nil {
			return isoPowerOffDoneMsg{err: err}
		}
		return nil
	}
}

func (m isoInstallerModel) filteredChoices() []isoChoice {
	var choices []isoChoice
	switch m.step {
	case isoStepRegional:
		if m.regionalFocus == isoRegionalTimezone {
			choices = m.timezones
		} else {
			choices = m.keyboards
		}
	case isoStepDisk:
		for _, disk := range m.disks {
			choices = append(choices, disk.Choice)
		}
	}

	filter := strings.ToLower(strings.TrimSpace(string(m.filter)))
	if filter == "" {
		return choices
	}

	var filtered []isoChoice
	for _, choice := range choices {
		text := strings.ToLower(choice.Label + " " + choice.Value)
		if strings.Contains(text, filter) {
			filtered = append(filtered, choice)
		}
	}
	return filtered
}

func (m isoInstallerModel) diskSizeFor(device string) int64 {
	for _, disk := range m.disks {
		if disk.Choice.Value == device {
			return disk.SizeBytes
		}
	}
	return 0
}

func (m isoInstallerModel) View() tea.View {
	termWidth, termHeight := safeDimensions(m.width, m.height)
	width, height := termWidth, termHeight
	mode := layoutFor(width, height)

	var body string
	if m.helpOverlay {
		body = renderTUIHelp(width, "ISO "+m.stepTitle()+" controls", m.helpHints())
	} else if m.shutdownPrompt {
		canvasW, canvasH = fitContentWidth(width), 0
		body = m.renderISOShutdownPrompt(mode)
	} else if m.usesISOSetupSideLayout(width, height) {
		body = m.renderISOSetupSideBody(width, height, mode)
	} else {
		canvasW, canvasH = fitContentWidth(width), 0
		body = m.renderISOStep(mode)
	}

	placed := renderViewport(termWidth, termHeight, body)

	v := tea.NewView(placed)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeNone
	v.BackgroundColor = lipgloss.Color(bgTerm)
	v.WindowTitle = "qvOS ISO"
	v.KeyboardEnhancements.ReportEventTypes = true
	return v
}

func (m isoInstallerModel) usesISOSetupSideLayout(width, height int) bool {
	return m.isISOSetupStep() && width >= desktopMinWidth &&
		isSideComposition(width, height, false)
}

func (m isoInstallerModel) isISOSetupStep() bool {
	return m.step == isoStepRegional || m.step == isoStepAccount || m.step == isoStepDisk
}

func (m isoInstallerModel) capturesTextInput() bool {
	return !m.shutdownPrompt &&
		(m.step == isoStepRegional || m.step == isoStepAccount ||
			(m.step == isoStepDisk && !m.diskConfirm))
}

func (m isoInstallerModel) helpHints() []tuiHint {
	exitHint := tuiHint{
		Key:    "ctrl+c / ctrl+d / ctrl+z / ctrl+q / ctrl+\\",
		Action: "open the guarded shutdown prompt",
	}
	if m.step == isoStepDisk && m.diskConfirm {
		return []tuiHint{
			{Key: "arrows / tab", Action: "choose Back or Continue"},
			{Key: "enter", Action: "confirm the selected option"},
			{Key: "esc", Action: "return to the drive list"},
			exitHint,
		}
	}
	switch m.step {
	case isoStepWriting:
		return []tuiHint{exitHint}
	case isoStepError:
		return []tuiHint{
			{Key: "enter / esc", Action: "close the installer"},
			exitHint,
		}
	case isoStepRegional:
		return []tuiHint{
			{Key: "type", Action: "filter the focused choices"},
			{Key: "↑ / ↓", Action: "move between matches"},
			{Key: "← / → / tab", Action: "cycle fields"},
			{Key: "backspace / ctrl+u", Action: "edit or clear the filter"},
			{Key: "enter", Action: "use the selection and move forward"},
			{Key: "esc", Action: "move back or return"},
			exitHint,
		}
	case isoStepAccount:
		return []tuiHint{
			{Key: "type", Action: "enter the focused field"},
			{Key: "arrows / tab", Action: "cycle fields"},
			{Key: "backspace", Action: "delete one character"},
			{Key: "ctrl+u", Action: "clear the focused field"},
			{Key: "enter", Action: "move forward or continue"},
			{Key: "esc", Action: "move back or return"},
			exitHint,
		}
	case isoStepDisk:
		return []tuiHint{
			{Key: "type", Action: "filter the available drives"},
			{Key: "arrows / tab", Action: "move between drives"},
			{Key: "backspace / ctrl+u", Action: "edit or clear the filter"},
			{Key: "enter", Action: "select the install drive"},
			{Key: "esc", Action: "return to account setup"},
			exitHint,
		}
	default:
		return []tuiHint{exitHint}
	}
}

func (m isoInstallerModel) renderISOStep(mode layoutMode) string {
	var content string
	if m.shutdownPrompt {
		content = m.renderISOShutdownPrompt(mode)
	} else if m.step == isoStepWriting {
		return renderProgressScreen(progressScreen{
			Title:        "Preparing installation",
			Status:       "securing setup details",
			Phase:        loadRun,
			HideProgress: true,
		}, mode)
	} else if m.step == isoStepError {
		return renderFailureScreen(failureScreen{
			Subject: "SETUP",
			Message: m.errorText,
		})
	} else {
		content = m.renderISOSetupStack(mode)
	}
	return content
}

func (m isoInstallerModel) renderISOSetupSideBody(width, height int, mode layoutMode) string {
	leftWidth, rightWidth := sideColumnWidths(width)
	canvasW, canvasH = leftWidth, 0
	left := m.renderISOSetupControl(mode)
	canvasW = rightWidth
	right := m.renderISOSetupContext(mode)
	if iconWidth, iconHeight, ok := fitSideIconCanvas(width, height); ok && !m.diskConfirm {
		canvasW, canvasH = iconWidth, iconHeight
		icon := renderModelRole(m.isoSetupModelRole(), m.frame)
		canvasW, canvasH = rightWidth, 0
		right = lipgloss.JoinVertical(lipgloss.Center, icon, "", right)
	}
	canvasW = fitContentWidth(width)
	return renderISOColumns(width, left, right)
}

func (m isoInstallerModel) isoSetupModelRole() modelRole {
	switch m.step {
	case isoStepRegional:
		return modelOneRing
	case isoStepAccount:
		return modelTwoRings
	default:
		return modelThreeRings
	}
}

func (m isoInstallerModel) renderISOSetupStack(mode layoutMode) string {
	if m.step == isoStepDisk && m.diskConfirm {
		return lipgloss.JoinVertical(
			lipgloss.Center,
			m.renderISOSetupControl(mode),
			"",
			m.renderISOSetupContext(mode),
		)
	}
	return lipgloss.JoinVertical(
		lipgloss.Center,
		m.renderISOSetupContext(mode),
		"",
		m.renderISOSetupControl(mode),
	)
}

func (m isoInstallerModel) renderISOSetupContext(mode layoutMode) string {
	if m.step == isoStepDisk && m.diskConfirm {
		return m.renderISOFinalConfirmation(mode)
	}
	if mode == layoutMobile && m.step == isoStepAccount {
		return sGray.Render("qvOS") +
			sDim.Render(" · ") + m.renderISOStepTracker() +
			sDim.Render(" · ") + sISOBright.Render(strings.ToUpper(m.stepTitle()))
	}
	lines := []string{}
	if tracker := m.renderISOStepTracker(); tracker != "" {
		identity := sGray.Render("qvOS") + sDim.Render(" · ") + tracker
		lines = append(lines, identity, "")
	}
	lines = append(lines, sISOBright.Render(strings.ToUpper(m.stepTitle())))
	return lipgloss.JoinVertical(lipgloss.Center, lines...)
}

func (m isoInstallerModel) renderISOSetupControl(mode layoutMode) string {
	switch m.step {
	case isoStepRegional:
		return m.renderISORegionalControl(mode)
	case isoStepAccount:
		return m.renderISOAccountControl(mode)
	case isoStepDisk:
		if m.diskConfirm {
			return m.renderISODiskConfirmationControl(mode)
		}
		return m.renderISODiskControl(mode)
	default:
		return ""
	}
}

func renderISOColumns(width int, left, right string) string {
	leftWidth, rightWidth := sideColumnWidths(width)
	leftColumn := lipgloss.NewStyle().Width(leftWidth).Align(lipgloss.Center).Render(left)
	rightColumn := lipgloss.NewStyle().Width(rightWidth).Align(lipgloss.Center).Render(right)
	gap := lipgloss.NewStyle().
		Width(sideGap + 1).
		Height(max(lipgloss.Height(leftColumn), lipgloss.Height(rightColumn))).
		Render("")
	return lipgloss.JoinHorizontal(
		lipgloss.Center,
		leftColumn,
		gap,
		rightColumn,
	)
}

func (m isoInstallerModel) renderISOShutdownPrompt(mode layoutMode) string {
	title := sWhite.Render("CANCEL INSTALLATION?")
	subtitle := sDim.Render("(shutdown)")
	choices := renderISOOptionRows(isoShutdownChoices(), m.shutdownChoice)

	if mode == layoutMobile {
		return strings.Join(append([]string{centerCanvas(title)}, centerLines(choices)...), "\n")
	}

	lines := []string{centerCanvas(title), centerCanvas(subtitle), ""}
	lines = append(lines, centerLines(choices)...)
	if m.errorText != "" {
		lines = append(lines, "", centerCanvas(sGray.Render(m.errorText)))
	}
	return strings.Join(lines, "\n")
}

func (m isoInstallerModel) renderISORegionalControl(mode layoutMode) string {
	keyboard := selectedISOChoiceLabel(m.keyboards, m.config.Keyboard)
	timezone := selectedISOChoiceLabel(m.timezones, m.config.Timezone)
	lines := []string{
		renderISONamedField("Keyboard", keyboard, m.regionalFocus == isoRegionalKeyboard,
			m.regionalFocus == isoRegionalTimezone && keyboard != "", mode),
		"",
		renderISONamedField("Time zone", timezone, m.regionalFocus == isoRegionalTimezone,
			false, mode),
		"",
	}
	status := ""
	if filter := strings.TrimSpace(string(m.filter)); filter != "" {
		status = sDim.Render("Search ") + sBright.Render(filter)
	}
	lines = append(lines, status, "")
	lines = append(lines, m.visibleChoiceRows(m.filteredChoices(), mode)...)
	lines = append(lines, "")
	lines = append(lines, m.renderISOSetupHint(mode)...)
	return renderISOControlBlock(lines, mode)
}

func (m isoInstallerModel) renderISOAccountControl(mode layoutMode) string {
	username := string(m.username)
	usernameComplete := validISOUsername(strings.TrimSpace(username))
	hostname := string(m.hostname)
	hostnameComplete := validISOHostname(strings.TrimSpace(hostname))
	fields := []string{
		renderISONamedField("Username", username, m.accountFocus == isoAccountUsername,
			usernameComplete, mode),
		renderISONamedField("Machine Name", hostname, m.accountFocus == isoAccountHostname,
			hostnameComplete, mode),
		renderISONamedField("Password", strings.Repeat("•", len(m.password)), m.accountFocus == isoAccountPassword,
			len(m.password) > 0, mode),
		renderISONamedField("Confirm Password", strings.Repeat("•", len(m.passwordConfirm)), m.accountFocus == isoAccountPasswordConfirm,
			len(m.passwordConfirm) > 0 && string(m.passwordConfirm) == string(m.password), mode),
	}
	separator := "\n\n"
	if mode == layoutMobile {
		separator = "\n"
	}
	lines := strings.Split(strings.Join(fields, separator), "\n")
	lines = append(lines, "")
	lines = append(lines, m.renderISOSetupHint(mode)...)
	return renderISOControlBlock(lines, mode)
}

const isoSetupHintRows = 2

func (m isoInstallerModel) renderISOSetupHint(mode layoutMode) []string {
	hint := m.isoSetupHintText(mode)
	style := sDim
	if m.errorText != "" {
		hint = compactISOSetupError(m.errorText, mode)
		style = sISOBright
	} else if m.step == isoStepDisk && m.diskConfirm {
		style = sISOBright
	}
	return renderISOFixedCopy(hint, inputWidthForMode(mode), isoSetupHintRows, style)
}

func (m isoInstallerModel) isoSetupHintText(mode layoutMode) string {
	switch m.step {
	case isoStepRegional:
		if mode == layoutMobile {
			if m.regionalFocus == isoRegionalKeyboard {
				return "typing layout"
			}
			return "time zone"
		}
		if m.regionalFocus == isoRegionalKeyboard {
			return "Choose how qvOS types."
		}
		return "Choose how qvOS keeps time."
	case isoStepAccount:
		if mode == layoutMobile {
			switch m.accountFocus {
			case isoAccountUsername:
				return "lowercase name"
			case isoAccountHostname:
				return "this device"
			case isoAccountPassword:
				return "long + unique"
			case isoAccountPasswordConfirm:
				return "type it again"
			}
		}
		switch m.accountFocus {
		case isoAccountUsername:
			return "Use lowercase letters and numbers."
		case isoAccountHostname:
			return "Name this machine on your network."
		case isoAccountPassword:
			return "Use a long, unique password."
		case isoAccountPasswordConfirm:
			return "Type the same password again."
		}
	case isoStepDisk:
		if m.diskConfirm {
			if mode == layoutMobile {
				return "Erase this drive."
			}
			return "Everything on this drive will be erased."
		}
		if mode == layoutMobile {
			return "Choose install drive."
		}
		return "Choose where qvOS will be installed."
	}
	return ""
}

func compactISOSetupError(message string, mode layoutMode) string {
	if mode == layoutMobile {
		switch message {
		case "enter a username":
			return "enter username"
		case "check the machine name":
			return "check name"
		case "enter a password":
			return "enter password"
		case "make sure passwords match":
			return "passwords differ"
		case "try another keyboard layout":
			return "try another layout"
		case "no matching choices":
			return "no matches"
		}
		if minimum, found := strings.CutPrefix(message, "choose a drive with at least "); found {
			return "at least " + minimum
		}
	}
	return message
}

func renderISOFixedCopy(text string, width, rowCount int, style lipgloss.Style) []string {
	wrapped := wrapDisplayLines([]string{strings.TrimSpace(text)}, width)
	if strings.TrimSpace(text) == "" {
		wrapped = nil
	}
	rows := make([]string, 0, rowCount)
	for index := 0; index < rowCount; index++ {
		if index >= len(wrapped) {
			rows = append(rows, "")
			continue
		}
		rows = append(rows, style.Render(wrapped[index]))
	}
	return rows
}

func (m isoInstallerModel) renderISODiskControl(mode layoutMode) string {
	lines := []string{}
	if filter := strings.TrimSpace(string(m.filter)); filter != "" {
		lines = append(lines, sDim.Render("Search ")+sBright.Render(filter), "")
	}
	choices := m.filteredChoices()
	lines = append(lines, m.visibleDiskChoiceRows(choices, mode)...)
	lines = append(lines, "")
	lines = append(lines, m.renderISOSetupHint(mode)...)
	return renderISOControlBlock(lines, mode)
}

func (m isoInstallerModel) renderISODiskConfirmationControl(mode layoutMode) string {
	diskLabel := m.config.Disk
	for _, disk := range m.disks {
		if disk.Choice.Value == m.config.Disk {
			diskLabel = disk.Choice.Label
			break
		}
	}
	lines := renderISOCompletedDisk(diskLabel, inputWidthForMode(mode))
	lines = append(lines, "")
	lines = append(lines, m.renderISOSetupHint(mode)...)
	return renderISOControlBlock(lines, mode)
}

func (m isoInstallerModel) renderISOFinalConfirmation(mode layoutMode) string {
	labels := []string{"Back", "Continue"}
	lines := make([]string, 0, len(labels)*2-1)
	for index, label := range labels {
		active := isoDiskConfirmationAction(index) == m.diskConfirmAction
		lines = append(lines, renderISOInputField(label, active, !active, mode))
		if index < len(labels)-1 {
			lines = append(lines, "")
		}
	}
	return renderISOControlBlock(lines, mode)
}

func renderISONamedField(label, value string, active, complete bool, mode layoutMode) string {
	labelStyle := isoFieldTextStyle(active, complete)
	return strings.Join([]string{
		labelStyle.Render(label),
		renderISOInputField(value, active, complete, mode),
	}, "\n")
}

func renderISOControlBlock(lines []string, mode layoutMode) string {
	return lipgloss.NewStyle().
		Width(inputWidthForMode(mode)).
		Align(lipgloss.Left).
		Render(strings.Join(lines, "\n"))
}

func selectedISOChoiceLabel(choices []isoChoice, value string) string {
	for _, choice := range choices {
		if choice.Value == value {
			return choice.Label
		}
	}
	return value
}

func (m isoInstallerModel) visibleChoiceRows(choices []isoChoice, mode layoutMode) []string {
	limit := isoChoiceRowLimit(mode)
	rows := make([]string, 0, limit)
	if len(choices) == 0 {
		rows = append(rows, sGray.Render("no matching choices"))
		return append(rows, make([]string, limit-len(rows))...)
	}

	start := m.choiceIndex - limit/2
	if start < 0 {
		start = 0
	}
	if start+limit > len(choices) {
		start = len(choices) - limit
		if start < 0 {
			start = 0
		}
	}

	end := start + limit
	if end > len(choices) {
		end = len(choices)
	}
	for i := start; i < end; i++ {
		label := trimDisplay(choices[i].Label, max(1, inputWidthForMode(mode)-2))
		rows = append(rows, renderISOChoiceRow(label, i == m.choiceIndex))
	}
	rows = append(rows, make([]string, limit-len(rows))...)
	return rows
}

func (m isoInstallerModel) visibleDiskChoiceRows(choices []isoChoice, mode layoutMode) []string {
	lineLimit := isoDiskLineLimit(mode)
	if len(choices) == 0 {
		rows := []string{sGray.Render("no matching choices")}
		return append(rows, make([]string, lineLimit-len(rows))...)
	}

	selected := min(max(m.choiceIndex, 0), len(choices)-1)
	itemHeight := func(index int) int {
		return len(wrapDisplayLines([]string{choices[index].Label}, max(1, inputWidthForMode(mode)-2)))
	}
	start, end := selected, selected
	used := itemHeight(selected)
	for {
		changed := false
		if start > 0 {
			height := itemHeight(start - 1)
			if used+1+height <= lineLimit {
				start--
				used += 1 + height
				changed = true
			}
		}
		if end+1 < len(choices) {
			height := itemHeight(end + 1)
			if used+1+height <= lineLimit {
				end++
				used += 1 + height
				changed = true
			}
		}
		if !changed {
			break
		}
	}

	rows := make([]string, 0, max(lineLimit, used))
	for index := start; index <= end; index++ {
		if len(rows) > 0 {
			rows = append(rows, "")
		}
		if index == selected {
			rows = append(rows, renderISOSelectedDisk(choices[index].Label, inputWidthForMode(mode))...)
			continue
		}
		for _, line := range wrapDisplayLines([]string{choices[index].Label}, max(1, inputWidthForMode(mode)-2)) {
			rows = append(rows, "  "+sGray.Render(line))
		}
	}
	for len(rows) < lineLimit {
		rows = append(rows, "")
	}
	return rows
}

func renderISOSelectedDisk(label string, width int) []string {
	return renderISODiskRows(label, width, sRed, sISOBright)
}

func renderISOCompletedDisk(label string, width int) []string {
	return renderISODiskRows(label, width, sDeepRed, sGray)
}

func renderISODiskRows(label string, width int, railStyle, textStyle lipgloss.Style) []string {
	lines := wrapDisplayLines([]string{label}, max(1, width-2))
	rows := make([]string, 0, len(lines))
	for _, line := range lines {
		rows = append(rows, railStyle.Render("│")+" "+textStyle.Render(line))
	}
	return rows
}

func isoChoiceRowLimit(mode layoutMode) int {
	switch mode {
	case layoutMobile:
		return 3
	case layoutTablet:
		return 5
	default:
		return 7
	}
}

func isoDiskLineLimit(mode layoutMode) int {
	switch mode {
	case layoutMobile:
		return 5
	case layoutTablet:
		return 7
	default:
		return 9
	}
}

func (m isoInstallerModel) renderISOStepTracker() string {
	switch m.step {
	case isoStepRegional:
		return sDim.Render("Step 1/3")
	case isoStepAccount:
		return sDim.Render("Step 2/3")
	case isoStepDisk:
		return sDim.Render("Step 3/3")
	default:
		return ""
	}
}

func (m isoInstallerModel) stepTitle() string {
	switch m.step {
	case isoStepRegional:
		return "Region"
	case isoStepAccount:
		return "Account"
	case isoStepDisk:
		if m.diskConfirm {
			return "Erase drive?"
		}
		return "Install drive"
	default:
		return "Install"
	}
}

func inputWidthForMode(mode layoutMode) int {
	switch mode {
	case layoutMobile:
		return 14
	case layoutTablet:
		return 26
	default:
		return 36
	}
}

func renderISOOptionRows(choices []isoChoice, active int) []string {
	var rows []string
	for i, choice := range choices {
		rows = append(rows, renderISOChoiceRow(choice.Label, i == active))
	}
	return rows
}

func renderISOChoiceRow(label string, selected bool) string {
	if selected {
		return sISOBright.Render(label)
	}
	return sGray.Render(label)
}

func renderISOPrimaryAction(label string) string {
	return sISOBright.Render(label)
}

func renderISOInputField(value string, active, complete bool, mode layoutMode) string {
	fieldWidth := inputWidthForMode(mode)
	value = trimDisplay(value, fieldWidth)

	labelStyle := isoFieldTextStyle(active, complete)

	valueLine := lipgloss.PlaceHorizontal(fieldWidth, lipgloss.Left, labelStyle.Render(value))
	ruleStyle := sGray
	switch {
	case active:
		ruleStyle = sRed
	case complete:
		ruleStyle = sDim
	}
	rule := renderTUIRail(fieldWidth, ruleStyle)
	return strings.Join([]string{valueLine, rule}, "\n")
}

func isoFieldTextStyle(active, complete bool) lipgloss.Style {
	switch {
	case active:
		return sISOBright
	case complete:
		return sGray
	default:
		return sMid
	}
}

func centerLines(lines []string) []string {
	width := 0
	for _, line := range lines {
		if lineWidth := lipgloss.Width(line); lineWidth > width {
			width = lineWidth
		}
	}
	return centerLinesWithWidth(lines, width)
}

func centerLinesWithWidth(lines []string, width int) []string {
	centered := make([]string, 0, len(lines))
	for _, line := range lines {
		if width > 0 {
			line = lipgloss.PlaceHorizontal(width, lipgloss.Left, line)
		}
		centered = append(centered, centerCanvas(line))
	}
	return centered
}

func isoShutdownChoices() []isoChoice {
	return []isoChoice{{Label: "Resume", Value: "resume"}, {Label: "Shutdown", Value: "shutdown"}}
}

func isoKeyboardChoices() []isoChoice {
	keyboards := []isoChoice{
		{"Azerbaijani", "azerty"},
		{"Belarusian", "by"},
		{"Belgian", "be-latin1"},
		{"Bosnian", "ba"},
		{"Bulgarian", "bg-cp1251"},
		{"Croatian", "croat"},
		{"Czech", "cz"},
		{"Danish", "dk-latin1"},
		{"Dutch", "nl"},
		{"English (UK)", "uk"},
		{"English (US)", "us"},
		{"English (US, Dvorak)", "dvorak"},
		{"English (US, Colemak)", "colemak"},
		{"Estonian", "et"},
		{"Finnish", "fi"},
		{"French", "fr"},
		{"French (Canada)", "cf"},
		{"French (Switzerland)", "fr_CH"},
		{"Georgian", "ge"},
		{"German", "de"},
		{"German (Switzerland)", "de_CH-latin1"},
		{"Greek", "gr"},
		{"Hebrew", "il"},
		{"Hungarian", "hu"},
		{"Icelandic", "is-latin1"},
		{"Irish", "ie"},
		{"Italian", "it"},
		{"Japanese", "jp106"},
		{"Kazakh", "kazakh"},
		{"Khmer (Cambodia)", "khmer"},
		{"Kyrgyz", "kyrgyz"},
		{"Lao", "la-latin1"},
		{"Latvian", "lv"},
		{"Lithuanian", "lt"},
		{"Macedonian", "mk-utf"},
		{"Norwegian", "no-latin1"},
		{"Polish", "pl"},
		{"Portuguese", "pt-latin1"},
		{"Portuguese (Brazil)", "br-abnt2"},
		{"Romanian", "ro"},
		{"Russian", "ru"},
		{"Serbian", "sr-latin"},
		{"Slovak", "sk-qwertz"},
		{"Slovenian", "slovene"},
		{"Spanish", "es"},
		{"Spanish (Latin American)", "la-latin1"},
		{"Swedish", "sv-latin1"},
		{"Tajik", "tj_alt-UTF8"},
		{"Turkish", "trq"},
		{"Ukrainian", "ua"},
	}
	return keyboards
}

func isoTimezoneChoices() []isoChoice {
	out, err := exec.Command("timedatectl", "list-timezones").Output()
	var zones []string
	if err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			if line != "" {
				zones = append(zones, line)
			}
		}
	}
	if len(zones) == 0 {
		zones = []string{"UTC"}
	}

	current := strings.TrimSpace(commandOutput("timedatectl", "show", "--property=Timezone", "--value"))
	guessed := strings.TrimSpace(commandOutput("tzupdate", "-p"))
	sort.Strings(zones)
	zones = orderISOTimezones(zones, current, guessed)

	choices := make([]isoChoice, 0, len(zones))
	for _, zone := range zones {
		choices = append(choices, isoChoice{Label: zone, Value: zone})
	}
	return choices
}

func isoDiskChoices() []isoDiskChoice {
	disks := discoverISOInstallDisks()
	if len(disks) == 0 {
		return nil
	}
	return disks
}

func discoverISOInstallDisks() []isoDiskChoice {
	excludeDisk := rootDiskForDevice(strings.TrimSpace(commandOutput("findmnt", "-no", "SOURCE", "/run/archiso/bootmnt")))

	out, err := exec.Command("lsblk", "-dpno", "NAME,TYPE").Output()
	if err != nil {
		return nil
	}

	allowedDisk := regexp.MustCompile(`^/dev/(sd|hd|vd|nvme|mmcblk|xv)`)
	var disks []isoDiskChoice
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 || fields[1] != "disk" {
			continue
		}
		device := fields[0]
		if device == excludeDisk || !allowedDisk.MatchString(device) {
			continue
		}
		size := blockDeviceSize(device)
		if size <= 0 {
			continue
		}
		disks = append(disks, isoDiskChoice{
			Choice:    isoChoice{Label: diskDisplayLabel(device, size), Value: device},
			SizeBytes: size,
		})
	}
	return disks
}

func diskDisplayLabel(device string, sizeBytes int64) string {
	size := strings.TrimSpace(commandOutput("lsblk", "-dno", "SIZE", device))
	vendor := strings.TrimSpace(commandOutput("lsblk", "-dno", "VENDOR", device))
	model := strings.TrimSpace(commandOutput("lsblk", "-dno", "MODEL", device))

	label := ""
	switch {
	case vendor != "" && model != "" && strings.Contains(model, vendor):
		label = model
	case vendor != "" && model != "":
		label = vendor + " " + model
	case model != "":
		label = model
	case vendor != "":
		label = vendor
	}

	display := device
	if size != "" {
		display += " (" + size + ")"
	}
	if label != "" {
		display += " - " + label
	}
	if sizeBytes > 0 && sizeBytes < isoInstallerMinimumDiskSize {
		display += " - too small, needs " + formatISOBytes(isoInstallerMinimumDiskSize)
	}
	return display
}

func formatISOBytes(size int64) string {
	const gib int64 = 1024 * 1024 * 1024
	if size > 0 && size%gib == 0 {
		return strconv.FormatInt(size/gib, 10) + " GiB"
	}
	return strconv.FormatInt(size, 10) + " B"
}

func blockDeviceSize(device string) int64 {
	sizeText := strings.TrimSpace(commandOutput("lsblk", "-bdno", "SIZE", device))
	size, err := strconv.ParseInt(sizeText, 10, 64)
	if err != nil {
		return 0
	}
	return size
}

func rootDiskForDevice(device string) string {
	if device == "" {
		return ""
	}

	if resolved, err := filepath.EvalSymlinks(device); err == nil {
		device = resolved
	}

	for {
		parent := strings.TrimSpace(commandOutput("lsblk", "-dno", "PKNAME", device))
		if parent == "" {
			break
		}
		device = "/dev/" + parent
	}

	if strings.TrimSpace(commandOutput("lsblk", "-dno", "TYPE", device)) == "disk" {
		return device
	}
	return ""
}

func loadISOKeyboard(layout string) error {
	if !strings.HasPrefix(strings.TrimSpace(commandOutput("tty")), "/dev/tty") {
		return nil
	}
	return exec.Command("loadkeys", layout).Run()
}

func commandOutput(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return string(out)
}

func moveStringFirst(values []string, target string) []string {
	targetIndex := -1
	for index, value := range values {
		if value == target {
			targetIndex = index
			break
		}
	}
	if targetIndex < 0 {
		return values
	}

	out := make([]string, 0, len(values))
	out = append(out, target)
	for index, value := range values {
		if index != targetIndex {
			out = append(out, value)
		}
	}
	return out
}

func orderISOTimezones(zones []string, current, guessed string) []string {
	preferred := guessed
	if current != "" && current != "UTC" && current != "Etc/UTC" {
		preferred = current
	}
	return moveStringFirst(zones, preferred)
}

func indexChoiceValue(choices []isoChoice, value string) int {
	for i, choice := range choices {
		if choice.Value == value {
			return i
		}
	}
	return 0
}
