package main

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type isoStep int

const (
	isoStepIntro isoStep = iota
	isoStepKeyboard
	isoStepUsername
	isoStepFullName
	isoStepEmail
	isoStepPassword
	isoStepPasswordConfirm
	isoStepHostname
	isoStepTimezone
	isoStepReview
	isoStepDisk
	isoStepConfirm
	isoStepWriting
	isoStepError
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
	step           isoStep
	frame          int
	width, height  int
	preview        bool
	input          []rune
	filter         []rune
	password       []rune
	choiceIndex    int
	shutdownPrompt bool
	shutdownChoice int
	allowQuit      bool
	errorText      string
	keyboards      []isoChoice
	timezones      []isoChoice
	disks          []isoDiskChoice
	config         isoInstallerConfig
}

type isoInstallerDoneMsg struct {
	err error
}

type isoExitRequestedMsg struct{}

type isoPowerOffDoneMsg struct {
	err error
}

func runISOInstaller(preview ...bool) error {
	if err := ensureISOInstallerRuntime(); err != nil {
		return err
	}

	p := tea.NewProgram(newISOInstallerModel(preview...), tea.WithFilter(filterISOInstallerExitMessages))
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
	for _, commandName := range []string{"openssl", "lsblk", "timedatectl"} {
		if _, err := exec.LookPath(commandName); err != nil {
			return fmt.Errorf("qvOS ISO installer requires %s", commandName)
		}
	}
	return nil
}

func newISOInstallerModel(preview ...bool) isoInstallerModel {
	keyboards := isoKeyboardChoices()
	timezones := isoTimezoneChoices()
	disks := isoDiskChoices()
	previewMode := len(preview) > 0 && preview[0]

	return isoInstallerModel{
		step:        isoStepIntro,
		preview:     previewMode,
		keyboards:   keyboards,
		timezones:   timezones,
		disks:       disks,
		choiceIndex: indexChoiceValue(keyboards, "us"),
		config: isoInstallerConfig{
			Hostname:            isoInstallerDefaultHostname,
			EncryptInstallation: true,
			Kernel:              detectISOInstallerKernel(),
		},
	}
}

func (m isoInstallerModel) Init() tea.Cmd { return tick() }

func (m isoInstallerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.frame += framesPerTick
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case isoInstallerDoneMsg:
		if msg.err != nil {
			m.step = isoStepError
			m.errorText = shortError(msg.err)
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
			m.errorText = shortError(msg.err)
		}
		return m, nil
	case tea.KeyPressMsg:
		return m.handleISOKey(msg)
	}
	return m, nil
}

func (m isoInstallerModel) handleISOKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if isISOExitKey(msg) {
		return m.requestISOExit()
	}

	if m.shutdownPrompt {
		return m.handleISOShutdownKey(msg)
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
	if m.step == isoStepIntro {
		return m.handleISOIntroKey(msg)
	}

	if m.isListStep() {
		return m.handleISOListKey(msg)
	}
	if m.step == isoStepReview || m.step == isoStepConfirm {
		return m.handleISOChoiceKey(msg)
	}
	return m.handleISOInputKey(msg)
}

func (m isoInstallerModel) handleISOIntroKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		m.step = isoStepKeyboard
		m.choiceIndex = indexChoiceValue(m.keyboards, "us")
	case "esc":
		return m.requestISOExit()
	}
	return m, nil
}

func (m isoInstallerModel) requestISOExit() (tea.Model, tea.Cmd) {
	m.shutdownPrompt = true
	m.shutdownChoice = 1
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
	case "esc":
		m.shutdownPrompt = false
		m.shutdownChoice = 1
	case "enter":
		if m.shutdownChoice == 0 {
			if m.preview {
				return m, tea.Quit
			}
			return m, powerOffCmd()
		}
		m.shutdownPrompt = false
		m.shutdownChoice = 1
	}
	return m, nil
}

func (m isoInstallerModel) handleISOInputKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		return m.goBack(), nil
	case "enter":
		return m.submitISOInput()
	case "backspace", "ctrl+h":
		if len(m.input) > 0 {
			m.input[len(m.input)-1] = 0
			m.input = m.input[:len(m.input)-1]
			m.errorText = ""
		}
	case "ctrl+u":
		clearRunes(m.input)
		m.input = nil
	default:
		if text := msg.Key().Text; text != "" {
			if m.step == isoStepUsername {
				text = strings.ToLower(text)
			}
			m.input = append(m.input, []rune(text)...)
			m.errorText = ""
		}
	}
	return m, nil
}

func (m isoInstallerModel) handleISOListKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	choices := m.filteredChoices()
	switch msg.String() {
	case "esc":
		return m.goBack(), nil
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
			m.errorText = "no matches"
			return m, nil
		}
		return m.submitISOListChoice(choices[m.choiceIndex])
	case "backspace", "ctrl+h":
		if len(m.filter) > 0 {
			m.filter[len(m.filter)-1] = 0
			m.filter = m.filter[:len(m.filter)-1]
			m.choiceIndex = 0
		}
	default:
		if text := msg.Key().Text; text != "" {
			m.filter = append(m.filter, []rune(text)...)
			m.choiceIndex = 0
		}
	}
	if m.choiceIndex >= len(choices) {
		m.choiceIndex = len(choices) - 1
	}
	if m.choiceIndex < 0 {
		m.choiceIndex = 0
	}
	return m, nil
}

func (m isoInstallerModel) handleISOChoiceKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	choices := m.staticStepChoices()
	switch msg.String() {
	case "esc":
		return m.goBack(), nil
	case "left", "up":
		if m.choiceIndex > 0 {
			m.choiceIndex--
		}
	case "right", "down":
		if m.choiceIndex < len(choices)-1 {
			m.choiceIndex++
		}
	case "enter":
		return m.submitStaticChoice()
	}
	return m, nil
}

func (m isoInstallerModel) submitISOInput() (tea.Model, tea.Cmd) {
	rawValue := string(m.input)
	value := strings.TrimSpace(rawValue)
	switch m.step {
	case isoStepUsername:
		value = strings.ToLower(value)
		if !validISOUsername(value) {
			m.errorText = "invalid username"
			return m, nil
		}
		m.config.Username = value
		m.step = isoStepFullName
		m.input = []rune(m.config.FullName)
		return m, nil
	case isoStepFullName:
		m.config.FullName = value
		m.step = isoStepEmail
		m.input = []rune(m.config.EmailAddress)
		return m, nil
	case isoStepEmail:
		m.config.EmailAddress = value
		m.step = isoStepPassword
	case isoStepPassword:
		if rawValue == "" {
			m.errorText = "password required"
			return m, nil
		}
		m.password = append([]rune(nil), m.input...)
		m.step = isoStepPasswordConfirm
	case isoStepPasswordConfirm:
		if string(m.input) != string(m.password) {
			m.errorText = "passwords do not match"
			clearRunes(m.input)
			m.input = nil
			return m, nil
		}
		m.step = isoStepHostname
		if m.config.Hostname == "" {
			m.input = []rune(isoInstallerDefaultHostname)
		} else {
			m.input = []rune(m.config.Hostname)
		}
		return m, nil
	case isoStepHostname:
		if value == "" {
			value = isoInstallerDefaultHostname
		}
		if !validISOHostname(value) {
			m.errorText = "invalid hostname"
			return m, nil
		}
		m.config.Hostname = value
		m.step = isoStepTimezone
		m.choiceIndex = indexChoiceValue(m.timezones, m.config.Timezone)
		m.filter = nil
	default:
		return m, nil
	}
	clearRunes(m.input)
	m.input = nil
	m.errorText = ""
	return m, nil
}

func (m isoInstallerModel) submitISOListChoice(choice isoChoice) (tea.Model, tea.Cmd) {
	switch m.step {
	case isoStepKeyboard:
		m.config.Keyboard = choice.Value
		if !m.preview {
			_ = loadISOKeyboard(choice.Value)
		}
		m.step = isoStepUsername
		m.input = []rune(m.config.Username)
		return m, nil
	case isoStepTimezone:
		m.config.Timezone = choice.Value
		m.step = isoStepReview
		m.choiceIndex = 0
	case isoStepDisk:
		m.config.Disk = choice.Value
		m.config.DiskSizeBytes = m.diskSizeFor(choice.Value)
		if m.config.DiskSizeBytes < isoInstallerMinimumDiskSize {
			m.errorText = "disk needs " + formatISOBytes(isoInstallerMinimumDiskSize) + " minimum"
			return m, nil
		}
		m.config.EncryptInstallation = true
		m.step = isoStepConfirm
		m.choiceIndex = 0
	default:
		return m, nil
	}
	m.filter = nil
	m.errorText = ""
	return m, nil
}

func (m isoInstallerModel) submitStaticChoice() (tea.Model, tea.Cmd) {
	switch m.step {
	case isoStepReview:
		if m.choiceIndex == 0 {
			m.step = isoStepDisk
			m.choiceIndex = 0
			m.filter = nil
		} else {
			m.step = isoStepKeyboard
			m.choiceIndex = indexChoiceValue(m.keyboards, m.config.Keyboard)
			m.filter = nil
			clearRunes(m.input)
			m.input = nil
		}
	case isoStepConfirm:
		if m.choiceIndex != 0 {
			m.step = isoStepDisk
			m.choiceIndex = 0
			m.filter = nil
			return m, nil
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

func writeISOInstallerOutputCmd(cfg isoInstallerConfig, password []rune) tea.Cmd {
	return func() tea.Msg {
		defer clearRunes(password)

		hash, err := hashISOInstallerPassword(password)
		if err != nil {
			return isoInstallerDoneMsg{err: err}
		}

		cfg.Password = string(password)
		cfg.PasswordHash = hash
		cfg.Kernel = detectISOInstallerKernel()
		return isoInstallerDoneMsg{err: writeOmarchyInstallerFiles(".", cfg)}
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

func (m isoInstallerModel) goBack() isoInstallerModel {
	m.errorText = ""
	clearRunes(m.input)
	m.input = nil
	m.filter = nil
	m.choiceIndex = 0

	switch m.step {
	case isoStepKeyboard:
		m.step = isoStepIntro
	case isoStepUsername:
		m.step = isoStepKeyboard
		m.choiceIndex = indexChoiceValue(m.keyboards, m.config.Keyboard)
	case isoStepFullName:
		m.step = isoStepUsername
		m.input = []rune(m.config.Username)
	case isoStepEmail:
		m.step = isoStepFullName
		m.input = []rune(m.config.FullName)
	case isoStepPassword:
		m.step = isoStepEmail
		m.input = []rune(m.config.EmailAddress)
	case isoStepPasswordConfirm:
		m.step = isoStepPassword
	case isoStepHostname:
		m.step = isoStepPasswordConfirm
	case isoStepTimezone:
		m.step = isoStepHostname
		m.input = []rune(m.config.Hostname)
	case isoStepReview:
		m.step = isoStepTimezone
		m.choiceIndex = indexChoiceValue(m.timezones, m.config.Timezone)
	case isoStepDisk:
		m.step = isoStepReview
	case isoStepConfirm:
		m.step = isoStepDisk
		m.choiceIndex = indexDiskValue(m.disks, m.config.Disk)
	}
	return m
}

func (m isoInstallerModel) isListStep() bool {
	return m.step == isoStepKeyboard || m.step == isoStepTimezone || m.step == isoStepDisk
}

func (m isoInstallerModel) filteredChoices() []isoChoice {
	var choices []isoChoice
	switch m.step {
	case isoStepKeyboard:
		choices = m.keyboards
	case isoStepTimezone:
		choices = m.timezones
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

func (m isoInstallerModel) staticStepChoices() []isoChoice {
	switch m.step {
	case isoStepReview:
		return []isoChoice{{Label: "continue", Value: "yes"}, {Label: "change", Value: "no"}}
	case isoStepConfirm:
		return []isoChoice{{Label: "install", Value: "yes"}, {Label: "change disk", Value: "no"}}
	default:
		return nil
	}
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
	width, height := safeDimensions(m.width, m.height)
	mode := layoutFor(width, height)
	if mode == layoutFull {
		canvasW, canvasH = fitCanvas(width, height)
	} else if mode == layoutMid {
		canvasW, canvasH = fitMidCanvas(width, height)
	} else {
		canvasW, canvasH = fitSmallBody(width), 0
	}

	icon := ""
	if mode != layoutSmall {
		icon = renderBloom(m.frame)
	}

	body := m.renderISOBody(mode, icon)
	placed := lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, body)
	placed = lipgloss.NewStyle().
		Width(width).
		Height(height).
		Background(lipgloss.Color("#000000")).
		Render(placed)

	v := tea.NewView(placed)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeNone
	v.BackgroundColor = lipgloss.Color("#000000")
	v.WindowTitle = "qvOS ISO"
	return v
}

func (m isoInstallerModel) renderISOBody(mode layoutMode, icon string) string {
	var lines []string
	if icon != "" {
		lines = append(lines, icon, "")
	}
	if m.step == isoStepIntro && mode != layoutSmall {
		lines = append(lines, sWhite.Render("qvOS"), sDim.Render("BASED ON OMARCHY"), "")
	}
	lines = append(lines, m.renderISOStep(mode))
	return strings.Join(lines, "\n")
}

func (m isoInstallerModel) renderISOStep(mode layoutMode) string {
	if m.shutdownPrompt {
		return m.renderISOShutdownPrompt(mode)
	}
	if m.step == isoStepIntro {
		return m.renderISOIntro(mode)
	}
	if m.step == isoStepWriting {
		return renderReducedProgress("CONFIG", loadRun, realisticProgress(float64(m.frame%buildFrames)/float64(buildFrames)), mode)
	}
	if m.step == isoStepError {
		return centerCanvas(sRed.Render("ERROR") + sGray.Render("  ") + sMid.Render(m.errorText))
	}
	if m.isListStep() {
		return m.renderISOListStep(mode)
	}
	if m.step == isoStepReview {
		return m.renderISOReview(mode)
	}
	if m.step == isoStepConfirm {
		return m.renderISOStaticChoice(mode)
	}
	return m.renderISOInputStep(mode)
}

func (m isoInstallerModel) renderISOIntro(mode layoutMode) string {
	begin := renderISOActionRow("00", "BEGIN", true, mode)
	if mode == layoutSmall {
		return strings.Join([]string{
			centerCanvas(sWhite.Render("qvOS")),
			centerCanvas(sDim.Render("BASED ON OMARCHY")),
			"",
			centerCanvas(begin),
		}, "\n")
	}

	lines := []string{centerCanvas(begin)}
	if mode == layoutFull {
		lines = append(lines, "", "", centerCanvas(isoHelpLine()))
	}
	return strings.Join(lines, "\n")
}

func (m isoInstallerModel) renderISOInputStep(mode layoutMode) string {
	title := sWhite.Render(m.stepTitle())
	field := m.renderISOInputField(mode)
	if mode == layoutSmall {
		return strings.Join([]string{centerCanvas(title), centerCanvas(field)}, "\n")
	}

	lines := []string{centerCanvas(title), "", centerCanvas(field)}
	if help := m.inputHelp(); help != "" {
		lines = append(lines, "", centerCanvas(sGray.Render(help)))
	}
	if m.errorText != "" {
		lines = append(lines, "", centerCanvas(sRed.Render(m.errorText)))
	}
	if mode == layoutFull {
		lines = append(lines, "", "", centerCanvas(isoHelpLine()))
	}
	return strings.Join(lines, "\n")
}

func (m isoInstallerModel) renderISOShutdownPrompt(mode layoutMode) string {
	title := sWhite.Render("CANCEL INSTALLATION?")
	subtitle := sDim.Render("(shutdown)")
	choices := renderISOOptionRows(isoShutdownChoices(), m.shutdownChoice, mode)

	if mode == layoutSmall {
		return strings.Join(append([]string{centerCanvas(title)}, centerLines(choices)...), "\n")
	}

	lines := []string{centerCanvas(title), centerCanvas(subtitle), ""}
	lines = append(lines, centerLines(choices)...)
	if m.errorText != "" {
		lines = append(lines, "", centerCanvas(sRed.Render(m.errorText)))
	}
	if mode == layoutFull {
		lines = append(lines, "", "", centerCanvas(isoHelpLine()))
	}
	return strings.Join(lines, "\n")
}

func (m isoInstallerModel) renderISOInputField(mode layoutMode) string {
	value := string(m.input)
	if m.step == isoStepPassword || m.step == isoStepPasswordConfirm {
		value = strings.Repeat("•", len(m.input))
	}
	if value == "" {
		value = m.placeholder()
		return renderISOInputField(value, true, mode)
	}
	return renderISOInputField(value, false, mode)
}

func (m isoInstallerModel) renderISOListStep(mode layoutMode) string {
	choices := m.filteredChoices()
	title := sWhite.Render(m.stepTitle())
	filter := strings.TrimSpace(string(m.filter))
	filterLine := renderISOSearchField(filter, mode)

	if mode == layoutSmall {
		selected := "none"
		if len(choices) > 0 {
			selected = trimDisplay(choices[m.choiceIndex].Label, inputWidthForMode(mode))
		}
		return strings.Join([]string{centerCanvas(title), centerCanvas(renderISOActionRow("00", selected, true, mode))}, "\n")
	}

	lines := []string{centerCanvas(title), "", centerCanvas(filterLine), ""}
	lines = append(lines, centerLines(m.visibleChoiceRows(choices, mode))...)
	if m.errorText != "" {
		lines = append(lines, centerCanvas(sRed.Render(m.errorText)))
	}
	if mode == layoutFull {
		lines = append(lines, "", centerCanvas(isoHelpLine()))
	}
	return strings.Join(lines, "\n")
}

func (m isoInstallerModel) renderISOReview(mode layoutMode) string {
	lines := []string{centerCanvas(sWhite.Render("REVIEW")), ""}
	if mode != layoutSmall {
		reviewRows := m.renderISOReviewGridRows(mode)
		blockWidth := isoReviewBlockWidth(mode)

		lines = append(lines, centerLinesWithWidth(reviewRows, blockWidth)...)
		return strings.Join(lines, "\n")
	}
	lines = append(lines, centerLines(renderISOOptionRows(m.staticStepChoices(), m.choiceIndex, mode))...)
	return strings.Join(lines, "\n")
}

func (m isoInstallerModel) renderISOReviewGridRows(mode layoutMode) []string {
	fields := []struct {
		label string
		value string
	}{
		{"USER", m.config.Username},
		{"NAME", m.config.FullName},
		{"EMAIL", m.config.EmailAddress},
		{"HOST", m.config.Hostname},
		{"ENCRYPT", encryptionLabel(m.config.EncryptInstallation)},
		{"TIMEZONE", m.config.Timezone},
		{"KEYBOARD", m.config.Keyboard},
	}

	labelWidth, valueWidth, actionWidth := isoReviewColumnWidths(mode)
	actions := renderISOOptionRows(m.staticStepChoices(), m.choiceIndex, mode)

	rows := make([]string, 0, len(fields))
	for i, field := range fields {
		value := strings.TrimSpace(field.value)
		if value == "" {
			value = "-"
		}

		label := lipgloss.PlaceHorizontal(labelWidth, lipgloss.Left, field.label)
		value = lipgloss.PlaceHorizontal(valueWidth, lipgloss.Left, trimDisplay(value, valueWidth))
		action := ""
		if i < len(actions) {
			action = actions[i]
		}
		action = lipgloss.PlaceHorizontal(actionWidth, lipgloss.Left, action)

		rows = append(rows, sGray.Render(label)+"  "+sBright.Render(value)+"  "+action)
	}
	return rows
}

func isoReviewColumnWidths(mode layoutMode) (int, int, int) {
	labelWidth := 8
	valueWidth := 15
	actionWidth := 14
	if mode == layoutMid {
		valueWidth = 12
		actionWidth = 12
	}
	return labelWidth, valueWidth, actionWidth
}

func isoReviewBlockWidth(mode layoutMode) int {
	labelWidth, valueWidth, actionWidth := isoReviewColumnWidths(mode)
	return labelWidth + 2 + valueWidth + 2 + actionWidth
}

func (m isoInstallerModel) renderISOStaticChoice(mode layoutMode) string {
	title := m.stepTitle()
	if m.step == isoStepConfirm {
		title = "ERASE " + m.config.Disk
	}
	if mode == layoutSmall {
		return strings.Join([]string{
			centerCanvas(sWhite.Render(title)),
			centerCanvas(renderISOActionRow("00", strings.ToUpper(m.staticStepChoices()[m.choiceIndex].Label), true, mode)),
		}, "\n")
	}

	lines := []string{centerCanvas(sWhite.Render(title)), ""}
	if m.step == isoStepConfirm {
		lines = append(lines, centerCanvas(sRed.Render("everything on this disk will be overwritten")), "")
		lines = append(lines, centerCanvas(sGray.Render("disk encryption: "+encryptionLabel(m.config.EncryptInstallation))), "")
	}
	lines = append(lines, centerLines(renderISOOptionRows(m.staticStepChoices(), m.choiceIndex, mode))...)
	if mode == layoutFull {
		lines = append(lines, "", "", centerCanvas(isoHelpLine()))
	}
	return strings.Join(lines, "\n")
}

func encryptionLabel(enabled bool) string {
	if enabled {
		return "enabled"
	}
	return "disabled"
}

func (m isoInstallerModel) visibleChoiceRows(choices []isoChoice, mode layoutMode) []string {
	if len(choices) == 0 {
		return []string{sRed.Render("no matches")}
	}

	limit := 7
	if mode == layoutMid {
		limit = 5
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

	var rows []string
	end := start + limit
	if end > len(choices) {
		end = len(choices)
	}
	for i := start; i < end; i++ {
		label := trimDisplay(choices[i].Label, 34)
		rows = append(rows, renderISOActionRow(fmt.Sprintf("%02d", i%100), label, i == m.choiceIndex, mode))
	}
	return rows
}

func (m isoInstallerModel) stepTitle() string {
	switch m.step {
	case isoStepIntro:
		return "BEGIN"
	case isoStepKeyboard:
		return "KEYBOARD"
	case isoStepUsername:
		return "USERNAME"
	case isoStepFullName:
		return "FULL NAME"
	case isoStepEmail:
		return "EMAIL"
	case isoStepPassword:
		return "PASSWORD"
	case isoStepPasswordConfirm:
		return "CONFIRM"
	case isoStepHostname:
		return "HOSTNAME"
	case isoStepTimezone:
		return "TIMEZONE"
	case isoStepDisk:
		return "INSTALL DISK"
	default:
		return "INSTALL"
	}
}

func (m isoInstallerModel) placeholder() string {
	switch m.step {
	case isoStepUsername:
		return "username"
	case isoStepFullName:
		return "optional full name"
	case isoStepEmail:
		return "optional email"
	case isoStepPassword:
		return "password"
	case isoStepPasswordConfirm:
		return "repeat password"
	case isoStepHostname:
		return isoInstallerDefaultHostname
	default:
		return ""
	}
}

func (m isoInstallerModel) inputHelp() string {
	switch m.step {
	case isoStepUsername:
		return "lowercase user account"
	case isoStepFullName:
		return "optional"
	case isoStepEmail:
		return "optional"
	case isoStepPassword:
		return "used for user, root, and disk encryption"
	case isoStepPasswordConfirm:
		return "repeat the same password"
	default:
		return ""
	}
}

func inputWidthForMode(mode layoutMode) int {
	switch mode {
	case layoutSmall:
		return 14
	case layoutMid:
		return 26
	default:
		return 36
	}
}

func renderISOOptionRows(choices []isoChoice, active int, mode layoutMode) []string {
	var rows []string
	for i, choice := range choices {
		label := strings.ToUpper(choice.Label)
		rows = append(rows, renderISOActionRow(fmt.Sprintf("%02d", i), label, i == active, mode))
	}
	return rows
}

func renderISOOptionRow(choices []isoChoice, active int) string {
	return strings.Join(renderISOOptionRows(choices, active, layoutFull), "\n")
}

func renderISOActionRow(_ string, label string, selected bool, mode layoutMode) string {
	labelStyle := sMid
	marker := sDim.Render("╎")

	if selected {
		labelStyle = sWhite
		marker = sRed.Render("▐")
	}
	if mode == layoutSmall {
		return labelStyle.Render(label)
	}
	return marker + "  " + labelStyle.Render(label)
}

func renderISOInputField(value string, placeholder bool, mode layoutMode) string {
	fieldWidth := inputWidthForMode(mode)
	value = trimDisplay(value, fieldWidth)

	labelStyle := sWhite
	if placeholder {
		labelStyle = sMid
	}

	valueLine := lipgloss.PlaceHorizontal(fieldWidth, lipgloss.Center, labelStyle.Render(value))
	rule := sDeepRed.Render(strings.Repeat("─", fieldWidth))
	return strings.Join([]string{valueLine, rule}, "\n")
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

func renderISOSearchField(filter string, mode layoutMode) string {
	value := trimDisplay(strings.TrimSpace(filter), inputWidthForMode(mode))
	if value == "" {
		return sMid.Render("search")
	}
	return sBright.Render(value)
}

func isoShutdownChoices() []isoChoice {
	return []isoChoice{{Label: "cancel", Value: "shutdown"}, {Label: "continue", Value: "continue"}}
}

func isoHelpLine() string {
	return sDim.Render("←↑↓→") + sGray.Render("  cycle    ") +
		sDim.Render("⏎") + sGray.Render("  next    ") +
		sDim.Render("esc") + sGray.Render("  back")
}

func trimDisplay(value string, maxWidth int) string {
	if maxWidth < 1 {
		return ""
	}
	runes := []rune(value)
	if len(runes) <= maxWidth {
		return value
	}
	if maxWidth <= 1 {
		return string(runes[:maxWidth])
	}
	return string(runes[:maxWidth-1]) + "…"
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

	guessed := strings.TrimSpace(commandOutput("tzupdate", "-p"))
	sort.Strings(zones)
	if guessed != "" {
		zones = moveStringFirst(zones, guessed)
	}

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
	var out []string
	out = append(out, target)
	for _, value := range values {
		if value != target {
			out = append(out, value)
		}
	}
	return out
}

func indexChoiceValue(choices []isoChoice, value string) int {
	for i, choice := range choices {
		if choice.Value == value {
			return i
		}
	}
	return 0
}

func indexDiskValue(disks []isoDiskChoice, value string) int {
	for i, disk := range disks {
		if disk.Choice.Value == value {
			return i
		}
	}
	return 0
}
