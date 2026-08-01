package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func TestWriteOmarchyInstallerFilesMatchesISOContract(t *testing.T) {
	dir := t.TempDir()
	cfg := isoInstallerConfig{
		Keyboard:            "us",
		Username:            "qv",
		Password:            "test-password",
		PasswordHash:        "$6$hash",
		FullName:            "qvOS User",
		EmailAddress:        "qvos@example.test",
		Hostname:            "qvOS",
		Timezone:            "UTC",
		Disk:                "/dev/sda",
		DiskSizeBytes:       128 * 1024 * 1024 * 1024,
		EncryptInstallation: true,
		Kernel:              "linux",
	}

	if err := writeOmarchyInstallerFiles(dir, cfg); err != nil {
		t.Fatalf("writeOmarchyInstallerFiles() error = %v", err)
	}

	assertFileEquals(t, filepath.Join(dir, "user_full_name.txt"), "qvOS User\n")
	assertFileEquals(t, filepath.Join(dir, "user_email_address.txt"), "qvos@example.test\n")
	assertFileEquals(t, filepath.Join(dir, "user_encrypt_installation.txt"), "true\n")
	for _, name := range []string{
		"user_full_name.txt",
		"user_email_address.txt",
		"user_credentials.json",
		"user_encrypt_installation.txt",
		"user_configuration.json",
	} {
		assertFileMode(t, filepath.Join(dir, name), 0o600)
	}

	credentials := readCredentials(t, filepath.Join(dir, "user_credentials.json"))
	if credentials.EncryptionPassword == nil || *credentials.EncryptionPassword != cfg.Password {
		t.Fatalf("encryption password was not written")
	}
	if credentials.RootEncPassword != cfg.PasswordHash {
		t.Fatalf("root hash = %q, want %q", credentials.RootEncPassword, cfg.PasswordHash)
	}
	if len(credentials.Users) != 1 || credentials.Users[0].Username != cfg.Username {
		t.Fatalf("credentials users = %#v", credentials.Users)
	}

	configuration := readConfiguration(t, filepath.Join(dir, "user_configuration.json"))
	if configuration.Hostname != cfg.Hostname {
		t.Fatalf("hostname = %q, want %q", configuration.Hostname, cfg.Hostname)
	}
	if configuration.LocaleConfig.KeyboardLayout != cfg.Keyboard {
		t.Fatalf("keyboard = %q, want %q", configuration.LocaleConfig.KeyboardLayout, cfg.Keyboard)
	}
	if len(configuration.DiskConfig.DeviceModifications) != 1 {
		t.Fatalf("device modifications = %#v", configuration.DiskConfig.DeviceModifications)
	}
	device := configuration.DiskConfig.DeviceModifications[0]
	if device.Device != cfg.Disk || !device.Wipe {
		t.Fatalf("device modification = %#v", device)
	}
	if configuration.DiskConfig.DiskEncryption == nil {
		t.Fatalf("disk encryption was not written")
	}
	if !containsString(configuration.Packages, "snapper") {
		t.Fatalf("packages missing snapper: %#v", configuration.Packages)
	}
}

func TestValidateISOInstallerConfigRequiresEncryption(t *testing.T) {
	cfg := isoInstallerConfig{
		Keyboard:            "us",
		Username:            "qv",
		Password:            "test-password",
		PasswordHash:        "$6$hash",
		Hostname:            "qvOS",
		Timezone:            "UTC",
		Disk:                "/dev/sda",
		DiskSizeBytes:       128 * 1024 * 1024 * 1024,
		EncryptInstallation: false,
		Kernel:              "linux",
	}

	if err := validateISOInstallerConfig(cfg); err == nil || err.Error() != "disk encryption is required" {
		t.Fatalf("validateISOInstallerConfig() error = %v, want disk encryption is required", err)
	}
}

func TestBuildOmarchyDiskLayoutUsesQvOSProductName(t *testing.T) {
	_, err := buildOmarchyDiskLayout("/dev/sda", 1024*1024*1024)
	if err == nil || err.Error() != "disk /dev/sda is too small for qvOS layout" {
		t.Fatalf("buildOmarchyDiskLayout() error = %v, want qvOS layout error", err)
	}
}

func TestParseISOProgressLogFromFixture(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("testdata", "iso-install.log"))
	if err != nil {
		t.Fatal(err)
	}

	status, progress := parseISOProgressLog(string(data))
	if status != "install complete" {
		t.Fatalf("status = %q, want install complete", status)
	}
	if progress != 1 {
		t.Fatalf("progress = %v, want 1", progress)
	}
}

func TestISOProgressLogRetainsTheCompleteTerminalHistory(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "install.log")
	var log strings.Builder
	log.WriteString("qvOS ISO progress: internal milestone\n")
	for index := range 300 {
		fmt.Fprintf(&log, "install line %03d\n", index)
	}
	log.WriteString("qvOS target apply: internal milestone\n")
	log.WriteString("downloading 10%\rdownloading 72%\r\n")
	if err := os.WriteFile(logPath, []byte(log.String()), 0o600); err != nil {
		t.Fatal(err)
	}

	_, lines := readISOProgressLog(logPath)
	if len(lines) != 301 {
		t.Fatalf("ISO terminal history lines = %d, want 301", len(lines))
	}
	if lines[0] != "install line 000" || lines[299] != "install line 299" {
		t.Fatalf("ISO terminal history was truncated: first=%q last=%q", lines[0], lines[299])
	}
	if lines[300] != "downloading 72%" {
		t.Fatalf("ISO terminal redraw = %q, want latest frame", lines[300])
	}
	if strings.Contains(strings.Join(lines, "\n"), "internal milestone") {
		t.Fatalf("ISO terminal retained internal progress protocol: %#v", lines)
	}
}

func TestISOProgressUsesTheLatestRealInstallScript(t *testing.T) {
	log := strings.Join([]string{
		"[2026-08-02 01:00:00] Starting: /home/installer/.local/share/omarchy/install/packaging/base.sh",
		"[2026-08-02 01:00:01] Completed: /home/installer/.local/share/omarchy/install/packaging/base.sh",
		"[2026-08-02 01:00:02] Starting: /home/installer/.local/share/omarchy/install/config/docker.sh",
	}, "\n")

	status, progress := parseISOProgressLog(log)
	if status != "configuring docker" || progress != 0.72 {
		t.Fatalf("install script progress = %q %.2f, want configuring docker 0.72", status, progress)
	}
}

func TestISOTimezoneOrderPrefersConfiguredAndRejectsUnknownZones(t *testing.T) {
	zones := []string{"Africa/Cairo", "Europe/Paris", "UTC"}
	if got := orderISOTimezones(zones, "Africa/Cairo", "Europe/Paris"); got[0] != "Africa/Cairo" {
		t.Fatalf("configured timezone was not preferred: %#v", got)
	}
	if got := orderISOTimezones(zones, "UTC", "Europe/Paris"); got[0] != "Europe/Paris" {
		t.Fatalf("geographic fallback was not used for neutral UTC: %#v", got)
	}
	if got := orderISOTimezones(zones, "Unknown/Local", "Unknown/Guess"); got[0] != "Africa/Cairo" || len(got) != len(zones) {
		t.Fatalf("unknown timezone entered the valid choice list: %#v", got)
	}
}

func TestISOInstallerRegionalPageCommitsKeyboardThenTimeZone(t *testing.T) {
	model := isoInstallerModel{
		step:          isoStepRegional,
		regionalFocus: isoRegionalKeyboard,
		keyboards:     []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones:     []isoChoice{{Label: "Cairo", Value: "Africa/Cairo"}},
	}

	next, command := model.submitISORegionalChoice(model.keyboards[0])
	model = next.(isoInstallerModel)
	if command != nil || model.step != isoStepRegional || model.regionalFocus != isoRegionalTimezone || model.config.Keyboard != "us" {
		t.Fatalf("keyboard did not commit in place and focus time zone: %#v", model)
	}

	next, command = model.submitISORegionalChoice(model.timezones[0])
	model = next.(isoInstallerModel)
	if command != nil || model.step != isoStepAccount || model.config.Timezone != "Africa/Cairo" {
		t.Fatalf("time zone did not open account setup: %#v", model)
	}
}

func TestISOInstallerAccountPageFiltersUsernameAndRequiresMatchingPasswords(t *testing.T) {
	model := isoInstallerModel{
		step:         isoStepAccount,
		accountFocus: isoAccountUsername,
		hostname:     []rune("qvOS"),
	}

	next, command := model.handleISOAccountKey(tea.KeyPressMsg{Code: 'Q', Text: " 9QV user!?"})
	model = next.(isoInstallerModel)
	if command != nil || string(model.username) != "qvuser" {
		t.Fatalf("username accepted unsupported characters: %q", string(model.username))
	}

	next, command = model.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command != nil || model.accountFocus != isoAccountHostname || model.config.Username != "qvuser" {
		t.Fatalf("username did not commit and focus Machine Name: %#v", model)
	}

	next, command = model.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command != nil || model.accountFocus != isoAccountPassword || model.config.Hostname != "qvOS" {
		t.Fatalf("Machine Name did not commit and focus Password: %#v", model)
	}

	model.password = []rune("correct horse")
	next, command = model.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command != nil || model.accountFocus != isoAccountPasswordConfirm {
		t.Fatalf("Password did not focus Confirm Password: %#v", model)
	}

	model.passwordConfirm = []rune("wrong")
	next, command = model.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command != nil || model.step != isoStepAccount || model.errorText != "passwords do not match" {
		t.Fatalf("mismatched passwords continued: %#v", model)
	}

	model.passwordConfirm = []rune("correct horse")
	next, command = model.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command != nil || model.step != isoStepDisk || model.errorText != "" {
		t.Fatalf("matching account details did not continue to drive selection: %#v", model)
	}
	if model.config.FullName != "" || model.config.EmailAddress != "" {
		t.Fatalf("optional identity was invented: %#v", model.config)
	}
}

func TestISOInstallerFiltersUnsupportedMachineNameCharactersWhileTyping(t *testing.T) {
	if got := string(appendISOHostnameText(nil, " qv OS!?-1")); got != "qvOS-1" {
		t.Fatalf("Machine Name input = %q, want qvOS-1", got)
	}
}

func TestISOInstallerCyclesEveryMultiFieldPage(t *testing.T) {
	regional := isoInstallerModel{step: isoStepRegional}
	next, command := regional.handleISORegionalKey(tea.KeyPressMsg{Code: tea.KeyTab})
	regional = next.(isoInstallerModel)
	if command != nil || regional.regionalFocus != isoRegionalTimezone {
		t.Fatalf("regional Tab did not focus Time zone: %#v", regional)
	}
	next, command = regional.handleISORegionalKey(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift})
	regional = next.(isoInstallerModel)
	if command != nil || regional.regionalFocus != isoRegionalKeyboard {
		t.Fatalf("regional Shift+Tab did not focus Keyboard: %#v", regional)
	}

	account := isoInstallerModel{step: isoStepAccount}
	next, command = account.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyTab})
	account = next.(isoInstallerModel)
	if command != nil || account.accountFocus != isoAccountHostname {
		t.Fatalf("account Tab did not focus Machine Name: %#v", account)
	}
	next, command = account.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift})
	account = next.(isoInstallerModel)
	if command != nil || account.accountFocus != isoAccountUsername {
		t.Fatalf("account Shift+Tab did not return to Username: %#v", account)
	}
	next, command = account.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift})
	account = next.(isoInstallerModel)
	if command != nil || account.accountFocus != isoAccountPasswordConfirm {
		t.Fatalf("account Shift+Tab did not wrap to Confirm Password: %#v", account)
	}
}

func TestISOInstallerStartsAtRegionAndKeepsDriveConfirmationOnStepThree(t *testing.T) {
	if model := newISOInstallerModel(true); model.step != isoStepRegional {
		t.Fatalf("installer starts at step %d, want Region", model.step)
	}

	model := isoInstallerModel{
		step: isoStepDisk,
		disks: []isoDiskChoice{{
			Choice:    isoChoice{Label: "Test drive", Value: "/dev/sda"},
			SizeBytes: 128 * 1024 * 1024 * 1024,
		}},
	}
	next, command := model.submitISODiskChoice(model.disks[0].Choice)
	model = next.(isoInstallerModel)
	if command != nil || model.step != isoStepDisk || !model.diskConfirm || model.config.Disk != "/dev/sda" {
		t.Fatalf("drive selection skipped or left its confirmation screen: %#v", model)
	}
}

func TestISOInstallerRendersTheApprovedSideHierarchy(t *testing.T) {
	previousCanvasW, previousCanvasH := canvasW, canvasH
	t.Cleanup(func() { canvasW, canvasH = previousCanvasW, previousCanvasH })
	canvasW, canvasH = 60, 0

	regional := isoInstallerModel{
		step:          isoStepRegional,
		regionalFocus: isoRegionalKeyboard,
		keyboards:     []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones:     []isoChoice{{Label: "Cairo", Value: "Africa/Cairo"}},
		config:        isoInstallerConfig{Keyboard: "us", Timezone: "Africa/Cairo"},
	}
	regionalContent := stripANSI(regional.renderISOStep(layoutDesktop))
	for _, expected := range []string{"qvOS", "WELCOME", "Step 1/3", "REGION", "Keyboard", "Time zone", "keeps time"} {
		if !strings.Contains(regionalContent, expected) {
			t.Fatalf("regional page is missing %q: %q", expected, regionalContent)
		}
	}

	account := isoInstallerModel{
		step:     isoStepAccount,
		hostname: []rune("qvOS"),
	}
	accountContent := stripANSI(account.renderISOStep(layoutDesktop))
	for _, expected := range []string{"Step 2/3", "ACCOUNT", "Username", "Machine Name", "Password", "Confirm Password"} {
		if !strings.Contains(accountContent, expected) {
			t.Fatalf("account page is missing %q: %q", expected, accountContent)
		}
	}

	drive := isoInstallerModel{
		step:        isoStepDisk,
		diskConfirm: true,
		config:      isoInstallerConfig{Disk: "/dev/sda"},
		disks: []isoDiskChoice{{
			Choice: isoChoice{Label: "Test drive - 128 GiB", Value: "/dev/sda"},
		}},
	}
	confirmation := stripANSI(drive.renderISOStep(layoutDesktop))
	for _, expected := range []string{"Step 3/3", "ERASE DRIVE?", "Test drive", "will be erased", "› Install qvOS"} {
		if !strings.Contains(confirmation, expected) {
			t.Fatalf("drive confirmation is missing %q: %q", expected, confirmation)
		}
	}
}

func TestISOInstallerRegionalErrorUsesTheReservedStatusRow(t *testing.T) {
	model := isoInstallerModel{
		step:          isoStepRegional,
		regionalFocus: isoRegionalKeyboard,
		keyboards:     []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones:     []isoChoice{{Label: "Cairo", Value: "Africa/Cairo"}},
		config:        isoInstallerConfig{Keyboard: "us", Timezone: "Africa/Cairo"},
		errorText:     "could not apply keyboard",
	}
	content := stripANSI(model.renderISORegionalControl(layoutDesktop))
	if !strings.Contains(content, "could not apply keyboard") {
		t.Fatalf("regional error was not visible: %q", content)
	}
}

func TestISOInstallerRegionFilteringKeepsEveryLayoutAnchorStill(t *testing.T) {
	base := isoInstallerModel{
		step:          isoStepRegional,
		width:         140,
		height:        31,
		regionalFocus: isoRegionalKeyboard,
		keyboards: []isoChoice{
			{Label: "English (US)", Value: "us"},
			{Label: "English (UK)", Value: "uk"},
			{Label: "Arabic", Value: "ara"},
		},
		timezones: []isoChoice{{Label: "Cairo", Value: "Africa/Cairo"}},
		config:    isoInstallerConfig{Keyboard: "us", Timezone: "Africa/Cairo"},
	}

	baseline := stripANSI(base.View().Content)
	anchors := []string{"Keyboard", "Time zone", "Step 1/3", "REGION"}
	rowOf := func(content, needle string) int {
		for index, line := range strings.Split(content, "\n") {
			if strings.Contains(line, needle) {
				return index
			}
		}
		return -1
	}
	for _, filter := range []string{"uk", "missing"} {
		filtered := base
		filtered.filter = []rune(filter)
		content := stripANSI(filtered.View().Content)
		for _, anchor := range anchors {
			if got, want := rowOf(content, anchor), rowOf(baseline, anchor); got != want {
				t.Fatalf("filter %q moved %q from row %d to %d", filter, anchor, want, got)
			}
		}
		assertViewFits(t, filtered.View().Content, filtered.width, filtered.height)
	}
}

func TestISOInstallerUsesDividedColumnsForWideSetupOnly(t *testing.T) {
	regional := isoInstallerModel{
		step:      isoStepRegional,
		width:     140,
		height:    31,
		keyboards: []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones: []isoChoice{{Label: "UTC", Value: "UTC"}},
		config:    isoInstallerConfig{Keyboard: "us", Timezone: "UTC"},
	}
	content := stripANSI(regional.View().Content)
	if !strings.Contains(content, "│") || !strings.Contains(content, "REGION") || !strings.Contains(content, "Keyboard") {
		t.Fatalf("wide setup is missing its divided composition: %q", content)
	}
	assertViewFits(t, regional.View().Content, regional.width, regional.height)

	regional.width, regional.height = 70, 28
	if content := stripANSI(regional.View().Content); strings.Contains(content, "│") {
		t.Fatalf("narrow setup did not stack safely: %q", content)
	}
}

func TestISOInstallerSetupFitsTheResponsiveMatrix(t *testing.T) {
	regional := isoInstallerModel{
		step:      isoStepRegional,
		keyboards: []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones: []isoChoice{{Label: "Africa/Cairo", Value: "Africa/Cairo"}},
		config:    isoInstallerConfig{Keyboard: "us", Timezone: "Africa/Cairo"},
	}
	account := isoInstallerModel{
		step:            isoStepAccount,
		username:        []rune("qv"),
		hostname:        []rune("qvOS"),
		password:        []rune("secret"),
		passwordConfirm: []rune("secret"),
	}
	drive := isoInstallerModel{
		step: isoStepDisk,
		disks: []isoDiskChoice{{
			Choice:    isoChoice{Label: "Test drive - 128 GiB", Value: "/dev/sda"},
			SizeBytes: 128 * 1024 * 1024 * 1024,
		}},
	}
	confirmation := drive
	confirmation.diskConfirm = true
	confirmation.config.Disk = "/dev/sda"

	states := map[string]isoInstallerModel{
		"regional":     regional,
		"account":      account,
		"drive":        drive,
		"confirmation": confirmation,
	}
	sizes := []struct {
		name          string
		width, height int
	}{
		{"wide", 140, 31},
		{"stacked", 72, 28},
		{"compact", 44, 20},
	}

	for stateName, state := range states {
		for _, size := range sizes {
			t.Run(stateName+"/"+size.name, func(t *testing.T) {
				state.width, state.height = size.width, size.height
				assertViewFits(t, state.View().Content, size.width, size.height)
			})
		}
	}
}

func TestISOInstallerStepsIncreaseTheirRingCount(t *testing.T) {
	tests := []struct {
		step isoStep
		want modelRole
	}{
		{isoStepRegional, modelOneRing},
		{isoStepAccount, modelTwoRings},
		{isoStepDisk, modelThreeRings},
	}
	for _, test := range tests {
		if got := (isoInstallerModel{step: test.step}).isoSetupModelRole(); got != test.want {
			t.Fatalf("step %d model = %v, want %v", test.step, got, test.want)
		}
	}
}

func TestISOPrimaryActionUsesAQuietRedMarkerWithoutBackground(t *testing.T) {
	want := sRed.Render("›") + " " + sWhite.Render("Reboot")
	if got := renderISOPrimaryAction("Reboot"); got != want {
		t.Fatalf("primary action style = %q, want %q", got, want)
	}
}

func TestISOInputFieldsStartAtTheLeftEdge(t *testing.T) {
	rendered := stripANSI(renderISOInputField("secret", false, true, layoutDesktop))
	firstLine := strings.Split(rendered, "\n")[0]
	if !strings.HasPrefix(firstLine, "secret") {
		t.Fatalf("input did not start at the left edge: %q", rendered)
	}
}

func TestISOProgressMovesOnlyWhenTheInstallerReportsAMilestone(t *testing.T) {
	m := isoProgressModel{progress: 0.22, status: "installing base system"}
	next, _ := m.Update(tickMsg{})
	m = next.(isoProgressModel)
	if m.progress != 0.22 {
		t.Fatalf("clock tick fabricated progress: %v", m.progress)
	}

	next, _ = m.Update(isoProgressSnapshotMsg{
		status:   "base system installed",
		progress: 0.34,
	})
	m = next.(isoProgressModel)
	if m.progress != 0.34 || m.status != "base system installed" {
		t.Fatalf("reported milestone was not reflected exactly: %#v", m)
	}

	next, _ = m.Update(isoProgressSnapshotMsg{progress: 0.12})
	if got := next.(isoProgressModel).progress; got != 0.34 {
		t.Fatalf("older milestone moved progress backward: %v", got)
	}
}

func TestISOProgressViewsFitTheResponsiveMatrix(t *testing.T) {
	sizes := []struct {
		name          string
		width, height int
	}{
		{"wide", 140, 31},
		{"stacked", 72, 28},
		{"compact", 44, 20},
	}
	states := []struct {
		name     string
		split    bool
		terminal bool
	}{
		{"progress", false, false},
		{"split", true, false},
		{"terminal", false, true},
	}

	for _, size := range sizes {
		for _, state := range states {
			t.Run(size.name+"/"+state.name, func(t *testing.T) {
				model := isoProgressModel{
					width:        size.width,
					height:       size.height,
					progress:     0.42,
					status:       "installing qvOS",
					logLines:     []string{"installing base system", "applying qvOS"},
					logOverlay:   state.split,
					terminalView: state.terminal,
				}
				assertViewFits(t, model.View().Content, size.width, size.height)
			})
		}
	}
}

func TestISOProgressPrototypeSpansBaseSystemAndQvOSInstall(t *testing.T) {
	model := newISOProgressPrototypeModel()
	for range 360 {
		model.advancePrototype()
	}

	if model.progress != 1 {
		t.Fatalf("prototype progress = %v, want 1", model.progress)
	}
	if model.status != "install complete" {
		t.Fatalf("prototype status = %q, want install complete", model.status)
	}
	if len(model.logLines) < 7 {
		t.Fatalf("prototype log lines = %d, want all install phases", len(model.logLines))
	}
}

func TestISOChoicesUseOneQuietMarkerWithoutNumericClutter(t *testing.T) {
	row := stripANSI(renderISOChoiceRow("English (US)", true))
	if row != "• English (US)" {
		t.Fatalf("selected ISO choice = %q", row)
	}
	if strings.ContainsAny(row, "0123456789") {
		t.Fatalf("ISO choice retained numeric decoration: %q", row)
	}
}

func assertFileEquals(t *testing.T, path string, want string) {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != want {
		t.Fatalf("%s = %q, want %q", filepath.Base(path), string(data), want)
	}
}

func assertFileMode(t *testing.T, path string, want os.FileMode) {
	t.Helper()

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != want {
		t.Fatalf("%s mode = %o, want %o", filepath.Base(path), mode, want)
	}
}

func readCredentials(t *testing.T, path string) omarchyCredentials {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var out omarchyCredentials
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}
	return out
}

func readConfiguration(t *testing.T, path string) omarchyUserConfiguration {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var out omarchyUserConfiguration
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}
	return out
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
