package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
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
		"[2026-08-02 01:00:00] Starting: /home/installer/.local/share/qvos/qvcore/install/packaging/base",
		"[2026-08-02 01:00:01] Completed: /home/installer/.local/share/qvos/qvcore/install/packaging/base",
		"[2026-08-02 01:00:02] Starting: /home/installer/.local/share/qvos/qvcore/install/config/docker.sh",
	}, "\n")

	status, progress := parseISOProgressLog(log)
	if status != "configuring docker" || progress != 0.72 {
		t.Fatalf("install script progress = %q %.2f, want configuring docker 0.72", status, progress)
	}
}

func TestISOProgressClassifiesNativeInstallStages(t *testing.T) {
	tests := []struct {
		path     string
		status   string
		progress float64
	}{
		{"/home/installer/.local/share/qvos/qvcore/install/preflight/pacman.sh", "checking pacman", 0.58},
		{"/home/installer/.local/share/qvos/qvcore/install/packaging/fonts.sh", "installing fonts", 0.62},
		{"/home/installer/.local/share/qvos/qvcore/install/config/docker.sh", "configuring docker", 0.72},
		{"/home/installer/.local/share/qvos/qvcore/boot/login/hibernation.sh", "configuring hibernation", 0.92},
		{"/home/installer/.local/share/qvos/qvcore/security/install", "applying security defaults", 0.96},
	}

	for _, test := range tests {
		status := isoInstallScriptStatus(test.path)
		progress := isoInstallScriptMilestone(test.path)
		if status != test.status || progress != test.progress {
			t.Fatalf("native stage %q = %q %.2f, want %q %.2f", test.path, status, progress, test.status, test.progress)
		}
	}
}

func TestISOProgressDoesNotTreatPackageHooksAsGlobalProgress(t *testing.T) {
	log := strings.Join([]string{
		"Installation completed without any errors.",
		"(4/6) Reloading system bus configuration...",
		"(6/6) Updating the info directory file...",
	}, "\n")

	status, progress := parseISOProgressLog(log)
	if status != "base system installed" || progress != 0.34 {
		t.Fatalf("package hook progress = %q %.2f, want base system installed 0.34", status, progress)
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
	if command != nil || model.step != isoStepAccount || model.errorText != "make sure passwords match" {
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

func TestISOInstallerCyclesEverySetupPage(t *testing.T) {
	regional := isoInstallerModel{step: isoStepRegional}
	next, command := regional.handleISORegionalKey(tea.KeyPressMsg{Code: tea.KeyRight})
	regional = next.(isoInstallerModel)
	if command != nil || regional.regionalFocus != isoRegionalTimezone {
		t.Fatalf("regional Right did not focus Time zone: %#v", regional)
	}
	next, command = regional.handleISORegionalKey(tea.KeyPressMsg{Code: tea.KeyLeft})
	regional = next.(isoInstallerModel)
	if command != nil || regional.regionalFocus != isoRegionalKeyboard {
		t.Fatalf("regional Left did not focus Keyboard: %#v", regional)
	}
	next, command = regional.handleISORegionalKey(tea.KeyPressMsg{Code: tea.KeyTab})
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
	next, command = account.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyRight})
	account = next.(isoInstallerModel)
	if command != nil || account.accountFocus != isoAccountHostname {
		t.Fatalf("account Right did not focus Machine Name: %#v", account)
	}
	next, command = account.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyLeft})
	account = next.(isoInstallerModel)
	if command != nil || account.accountFocus != isoAccountUsername {
		t.Fatalf("account Left did not return to Username: %#v", account)
	}
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
	next, command = account.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyDown})
	account = next.(isoInstallerModel)
	if command != nil || account.accountFocus != isoAccountUsername {
		t.Fatalf("account Down did not wrap to Username: %#v", account)
	}
	next, command = account.handleISOAccountKey(tea.KeyPressMsg{Code: tea.KeyUp})
	account = next.(isoInstallerModel)
	if command != nil || account.accountFocus != isoAccountPasswordConfirm {
		t.Fatalf("account Up did not wrap to Confirm Password: %#v", account)
	}

	disk := isoInstallerModel{
		step: isoStepDisk,
		disks: []isoDiskChoice{
			{Choice: isoChoice{Label: "First", Value: "/dev/sda"}},
			{Choice: isoChoice{Label: "Second", Value: "/dev/sdb"}},
		},
	}
	next, command = disk.handleISODiskKey(tea.KeyPressMsg{Code: tea.KeyLeft})
	disk = next.(isoInstallerModel)
	if command != nil || disk.choiceIndex != 1 {
		t.Fatalf("disk Left did not wrap to the last drive: %#v", disk)
	}
	next, command = disk.handleISODiskKey(tea.KeyPressMsg{Code: tea.KeyRight})
	disk = next.(isoInstallerModel)
	if command != nil || disk.choiceIndex != 0 {
		t.Fatalf("disk Right did not wrap to the first drive: %#v", disk)
	}
	next, command = disk.handleISODiskKey(tea.KeyPressMsg{Code: tea.KeyUp})
	disk = next.(isoInstallerModel)
	if command != nil || disk.choiceIndex != 1 {
		t.Fatalf("disk Up did not wrap to the last drive: %#v", disk)
	}
	next, command = disk.handleISODiskKey(tea.KeyPressMsg{Code: tea.KeyDown})
	disk = next.(isoInstallerModel)
	if command != nil || disk.choiceIndex != 0 {
		t.Fatalf("disk Down did not wrap to the first drive: %#v", disk)
	}
	next, command = disk.handleISODiskKey(tea.KeyPressMsg{Code: tea.KeyTab})
	disk = next.(isoInstallerModel)
	if command != nil || disk.choiceIndex != 1 {
		t.Fatalf("disk Tab did not wrap to the last drive: %#v", disk)
	}
	next, command = disk.handleISODiskKey(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift})
	disk = next.(isoInstallerModel)
	if command != nil || disk.choiceIndex != 0 {
		t.Fatalf("disk Shift+Tab did not wrap to the first drive: %#v", disk)
	}
}

func TestISOInstallerHeldKeysDoNotRepeatCycling(t *testing.T) {
	repeated := func(code rune) tea.KeyPressMsg {
		return tea.KeyPressMsg{Code: code, IsRepeat: true}
	}

	regional := isoInstallerModel{
		step:          isoStepRegional,
		regionalFocus: isoRegionalKeyboard,
		keyboards: []isoChoice{
			{Label: "First", Value: "first"},
			{Label: "Second", Value: "second"},
		},
	}
	next, _ := regional.Update(repeated(tea.KeyRight))
	regional = next.(isoInstallerModel)
	if regional.regionalFocus != isoRegionalKeyboard {
		t.Fatalf("held Right repeated the Region field cycle: %#v", regional)
	}
	for _, key := range []tea.KeyPressMsg{
		{Code: tea.KeyTab, IsRepeat: true},
		{Code: tea.KeyTab, Mod: tea.ModShift, IsRepeat: true},
	} {
		next, _ = regional.Update(key)
		regional = next.(isoInstallerModel)
		if regional.regionalFocus != isoRegionalKeyboard {
			t.Fatalf("held %s repeated the Region field cycle: %#v", key.String(), regional)
		}
	}
	next, command := regional.Update(repeated(tea.KeyDown))
	regional = next.(isoInstallerModel)
	if command != nil || regional.choiceIndex != 1 {
		t.Fatalf("held Down stopped Step 1 list navigation: %#v", regional)
	}

	account := isoInstallerModel{step: isoStepAccount, accountFocus: isoAccountUsername}
	next, _ = account.Update(repeated(tea.KeyDown))
	account = next.(isoInstallerModel)
	if account.accountFocus != isoAccountUsername {
		t.Fatalf("held Down repeated the Account field cycle: %#v", account)
	}
	for _, key := range []tea.KeyPressMsg{
		{Code: tea.KeyTab, IsRepeat: true},
		{Code: tea.KeyTab, Mod: tea.ModShift, IsRepeat: true},
	} {
		next, _ = account.Update(key)
		account = next.(isoInstallerModel)
		if account.accountFocus != isoAccountUsername {
			t.Fatalf("held %s repeated the Account field cycle: %#v", key.String(), account)
		}
	}

	disk := isoInstallerModel{
		step: isoStepDisk,
		disks: []isoDiskChoice{
			{Choice: isoChoice{Label: "First", Value: "/dev/sda"}},
			{Choice: isoChoice{Label: "Second", Value: "/dev/sdb"}},
		},
	}
	next, _ = disk.Update(repeated(tea.KeyRight))
	disk = next.(isoInstallerModel)
	if disk.choiceIndex != 0 {
		t.Fatalf("held Right repeated the drive cycle: %#v", disk)
	}
	for _, key := range []tea.KeyPressMsg{
		{Code: tea.KeyTab, IsRepeat: true},
		{Code: tea.KeyTab, Mod: tea.ModShift, IsRepeat: true},
	} {
		next, _ = disk.Update(key)
		disk = next.(isoInstallerModel)
		if disk.choiceIndex != 0 {
			t.Fatalf("held %s repeated the drive cycle: %#v", key.String(), disk)
		}
	}

	disk.diskConfirm = true
	disk.diskConfirmAction = isoDiskConfirmationBack
	next, _ = disk.Update(repeated(tea.KeyDown))
	disk = next.(isoInstallerModel)
	if disk.diskConfirmAction != isoDiskConfirmationBack {
		t.Fatalf("held Down repeated the final action cycle: %#v", disk)
	}
	for _, key := range []tea.KeyPressMsg{
		{Code: tea.KeyTab, IsRepeat: true},
		{Code: tea.KeyTab, Mod: tea.ModShift, IsRepeat: true},
	} {
		next, _ = disk.Update(key)
		disk = next.(isoInstallerModel)
		if disk.diskConfirmAction != isoDiskConfirmationBack {
			t.Fatalf("held %s repeated the final action cycle: %#v", key.String(), disk)
		}
	}
}

func TestISOInstallerSuppressesLegacyHeldCycleBursts(t *testing.T) {
	tests := []struct {
		name          string
		key           tea.KeyPressMsg
		pairedRelease bool
		want          isoAccountField
	}{
		{name: "Right", key: tea.KeyPressMsg{Code: tea.KeyRight}, pairedRelease: true, want: isoAccountHostname},
		{name: "Left", key: tea.KeyPressMsg{Code: tea.KeyLeft}, pairedRelease: true, want: isoAccountPasswordConfirm},
		{name: "Down", key: tea.KeyPressMsg{Code: tea.KeyDown}, pairedRelease: true, want: isoAccountHostname},
		{name: "Up", key: tea.KeyPressMsg{Code: tea.KeyUp}, pairedRelease: true, want: isoAccountPasswordConfirm},
		{name: "Tab", key: tea.KeyPressMsg{Code: tea.KeyTab}, want: isoAccountHostname},
		{name: "Shift+Tab", key: tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift}, want: isoAccountPasswordConfirm},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			model := isoInstallerModel{step: isoStepAccount, accountFocus: isoAccountUsername}
			next, _ := model.Update(test.key)
			model = next.(isoInstallerModel)
			for range 2 {
				if test.pairedRelease {
					next, _ = model.Update(tea.KeyReleaseMsg(test.key))
					model = next.(isoInstallerModel)
				}
				next, _ = model.Update(test.key)
				model = next.(isoInstallerModel)
			}
			if model.accountFocus != test.want || !model.repeatSuppressing {
				t.Fatalf("legacy held %s advanced past one field: %#v", test.name, model)
			}

			next, command := model.Update(isoRepeatGuardTimerMsg{generation: model.repeatGeneration})
			model = next.(isoInstallerModel)
			if command != nil || model.accountFocus != test.want || model.repeatSuppressing {
				t.Fatalf("quiet timer changed the held %s result: %#v", test.name, model)
			}
		})
	}
}

func TestISOInstallerPhysicalReleaseRestoresImmediateCycling(t *testing.T) {
	model := isoInstallerModel{step: isoStepAccount, accountFocus: isoAccountUsername}
	right := tea.KeyPressMsg{Code: tea.KeyRight}
	next, _ := model.Update(right)
	model = next.(isoInstallerModel)

	next, command := model.Update(tea.KeyReleaseMsg(right))
	model = next.(isoInstallerModel)
	if command == nil || !model.repeatReleaseSet {
		t.Fatalf("physical release was not deferred for paired-repeat detection: %#v", model)
	}
	next, command = model.Update(isoRepeatReleaseTimerMsg{generation: model.repeatReleaseGen})
	model = next.(isoInstallerModel)
	if command != nil || model.repeatKey != "" || model.repeatReleaseSet {
		t.Fatalf("physical release did not clear the repeat guard: %#v", model)
	}

	next, command = model.Update(right)
	model = next.(isoInstallerModel)
	if command != nil || model.accountFocus != isoAccountPassword {
		t.Fatalf("new Right after release did not move immediately: %#v", model)
	}
}

func TestISOInstallerLegacyHelpTapReturnsThroughTheSharedHandler(t *testing.T) {
	model := isoInstallerModel{step: isoStepRegional}
	f1 := tea.KeyPressMsg{Code: tea.KeyF1}
	next, _ := model.Update(f1)
	model = next.(isoInstallerModel)
	if !model.helpOverlay {
		t.Fatal("first F1 did not open Help")
	}

	next, command := model.Update(f1)
	model = next.(isoInstallerModel)
	if command == nil || !model.repeatPendingSet {
		t.Fatalf("second legacy F1 was not deferred for burst detection: %#v", model)
	}
	next, command = model.Update(isoRepeatGuardTimerMsg{generation: model.repeatGeneration})
	model = next.(isoInstallerModel)
	if command != nil || model.helpOverlay || model.repeatPendingSet {
		t.Fatalf("deliberate legacy F1 did not close Help: %#v", model)
	}
}

func TestISOInstallerShutdownPromptDefaultsToResumeAndHidesShortcuts(t *testing.T) {
	model := isoInstallerModel{step: isoStepRegional, preview: true, width: 90, height: 30}
	next, command := model.requestISOExit()
	model = next.(isoInstallerModel)
	if command != nil || !model.shutdownPrompt || model.shutdownChoice != 0 {
		t.Fatalf("shutdown prompt did not open on safe Resume: %#v", model)
	}
	content := stripANSI(model.View().Content)
	for _, expected := range []string{"Resume", "Shutdown"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("shutdown prompt is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"ctrl+c/z", "again stop", "Cancel", "Continue"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("shutdown prompt retained %q: %q", hidden, content)
		}
	}

	next, command = model.handleISOShutdownKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command != nil || model.shutdownPrompt {
		t.Fatalf("default Resume did not return to setup: %#v", model)
	}

	next, _ = model.requestISOExit()
	model = next.(isoInstallerModel)
	next, _ = model.handleISOShutdownKey(tea.KeyPressMsg{Code: tea.KeyRight})
	model = next.(isoInstallerModel)
	next, command = model.handleISOShutdownKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command == nil || model.shutdownChoice != indexChoiceValue(isoShutdownChoices(), "shutdown") {
		t.Fatalf("explicit Shutdown did not quit the preview: %#v", model)
	}
}

func TestISOInstallerDiskFilterEditingUsesTheSharedControls(t *testing.T) {
	model := isoInstallerModel{
		step:        isoStepDisk,
		filter:      []rune("test"),
		choiceIndex: 3,
		errorText:   "no matching choices",
	}

	next, command := model.handleISODiskKey(tea.KeyPressMsg{Code: 'u', Mod: tea.ModCtrl})
	model = next.(isoInstallerModel)
	if command != nil || len(model.filter) != 0 || model.choiceIndex != 0 || model.errorText != "" {
		t.Fatalf("disk Ctrl+U did not clear the shared filter state: %#v", model)
	}

	model.errorText = "no matching choices"
	next, command = model.handleISODiskKey(tea.KeyPressMsg{Code: 'q', Text: "q"})
	model = next.(isoInstallerModel)
	if command != nil || string(model.filter) != "q" || model.errorText != "" {
		t.Fatalf("disk typing did not reset stale filter guidance: %#v", model)
	}
}

func TestISOInstallerPreservesDeliberateLegacyCycleTaps(t *testing.T) {
	model := isoInstallerModel{step: isoStepAccount, accountFocus: isoAccountUsername}
	next, _ := model.Update(tea.KeyPressMsg{Code: tea.KeyRight})
	model = next.(isoInstallerModel)
	if model.accountFocus != isoAccountHostname {
		t.Fatalf("first Right did not move immediately: %#v", model)
	}

	next, command := model.Update(tea.KeyPressMsg{Code: tea.KeyRight})
	model = next.(isoInstallerModel)
	if command == nil || model.accountFocus != isoAccountHostname || !model.repeatPendingSet {
		t.Fatalf("second deliberate Right was not held for burst detection: %#v", model)
	}

	next, command = model.Update(isoRepeatGuardTimerMsg{generation: model.repeatGeneration})
	model = next.(isoInstallerModel)
	if command != nil || model.accountFocus != isoAccountPassword || model.repeatPendingSet {
		t.Fatalf("deliberate Right did not commit after the burst window: %#v", model)
	}
}

func TestISOInstallerKeepsStepOneVerticalNavigationRepeatable(t *testing.T) {
	model := isoInstallerModel{
		step:          isoStepRegional,
		regionalFocus: isoRegionalKeyboard,
		keyboards: []isoChoice{
			{Label: "First", Value: "first"},
			{Label: "Second", Value: "second"},
			{Label: "Third", Value: "third"},
			{Label: "Fourth", Value: "fourth"},
		},
	}
	for range 3 {
		next, _ := model.Update(tea.KeyPressMsg{Code: tea.KeyDown})
		model = next.(isoInstallerModel)
	}
	if model.choiceIndex != 3 || model.repeatKey != "" {
		t.Fatalf("held Down did not navigate the Step 1 list freely: %#v", model)
	}
	for range 3 {
		next, _ := model.Update(tea.KeyPressMsg{Code: tea.KeyUp})
		model = next.(isoInstallerModel)
	}
	if model.choiceIndex != 0 || model.repeatKey != "" {
		t.Fatalf("held Up did not navigate the Step 1 list freely: %#v", model)
	}
}

func TestISOInstallerGuardsDangerousHeldKeys(t *testing.T) {
	pressThree := func(model isoInstallerModel, key tea.KeyPressMsg) isoInstallerModel {
		t.Helper()
		for range 3 {
			next, _ := model.Update(key)
			model = next.(isoInstallerModel)
		}
		return model
	}

	escape := pressThree(isoInstallerModel{
		step:         isoStepAccount,
		accountFocus: isoAccountPassword,
	}, tea.KeyPressMsg{Code: tea.KeyEscape})
	if escape.accountFocus != isoAccountHostname || !escape.repeatSuppressing {
		t.Fatalf("held Escape moved back through multiple levels: %#v", escape)
	}

	help := pressThree(isoInstallerModel{
		step: isoStepRegional,
	}, tea.KeyPressMsg{Code: tea.KeyF1})
	if !help.helpOverlay || !help.repeatSuppressing {
		t.Fatalf("held F1 toggled Help more than once: %#v", help)
	}

	interrupt := pressThree(isoInstallerModel{
		step:    isoStepRegional,
		preview: true,
	}, tea.KeyPressMsg{Code: 'c', Mod: tea.ModCtrl})
	if !interrupt.shutdownPrompt || interrupt.shutdownChoice != 0 || !interrupt.repeatSuppressing {
		t.Fatalf("held Ctrl+C advanced past the safe Resume prompt: %#v", interrupt)
	}
}

func TestISOInstallerFastEnterTapsAdvanceImmediately(t *testing.T) {
	model := isoInstallerModel{
		step:         isoStepAccount,
		accountFocus: isoAccountUsername,
		username:     []rune("qv"),
		hostname:     []rune("qvOS"),
	}
	for _, want := range []isoAccountField{isoAccountHostname, isoAccountPassword} {
		next, command := model.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
		model = next.(isoInstallerModel)
		if command != nil || model.accountFocus != want || model.repeatPendingSet {
			t.Fatalf("rapid Enter did not advance immediately to field %d: %#v", want, model)
		}
	}
}

func TestISOInstallerHeldEnterStopsBeforeItsSecondAction(t *testing.T) {
	model := isoInstallerModel{
		step:         isoStepAccount,
		accountFocus: isoAccountUsername,
		username:     []rune("qv"),
		hostname:     []rune("qvOS"),
	}
	next, _ := model.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	model.repeatLastPressAt = time.Now().Add(-isoFastEnterTapWindow)

	next, command := model.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command == nil || model.accountFocus != isoAccountHostname || !model.repeatPendingSet {
		t.Fatalf("first held Enter repeat was not deferred: %#v", model)
	}
	next, _ = model.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if model.accountFocus != isoAccountHostname || !model.repeatSuppressing {
		t.Fatalf("held Enter reached a second action: %#v", model)
	}
}

func TestISOInstallerAllowsOnlySafeRepeatableInput(t *testing.T) {
	model := isoInstallerModel{step: isoStepAccount, accountFocus: isoAccountUsername}
	for range 3 {
		next, _ := model.Update(tea.KeyPressMsg{Code: 'a', Text: "a"})
		model = next.(isoInstallerModel)
	}
	if string(model.username) != "aaa" || model.repeatKey != "" {
		t.Fatalf("ordinary text stopped repeating safely: %#v", model)
	}

	for range 2 {
		next, _ := model.Update(tea.KeyPressMsg{Code: tea.KeyBackspace})
		model = next.(isoInstallerModel)
	}
	if string(model.username) != "a" || model.repeatKey != "" {
		t.Fatalf("safe text deletion stopped repeating: %#v", model)
	}
}

func TestISOInstallerAllowsDeliberateSecondInterruptAfterRelease(t *testing.T) {
	model := isoInstallerModel{step: isoStepRegional, preview: true}
	interrupt := tea.KeyPressMsg{Code: 'c', Mod: tea.ModCtrl}
	next, _ := model.Update(interrupt)
	model = next.(isoInstallerModel)
	if !model.shutdownPrompt || model.shutdownChoice != 0 {
		t.Fatalf("first Ctrl+C did not open the safe Resume prompt: %#v", model)
	}

	next, command := model.Update(tea.KeyReleaseMsg(interrupt))
	model = next.(isoInstallerModel)
	if command == nil || !model.repeatReleaseSet {
		t.Fatalf("Ctrl+C release was not tracked: %#v", model)
	}
	next, _ = model.Update(isoRepeatReleaseTimerMsg{generation: model.repeatReleaseGen})
	model = next.(isoInstallerModel)

	next, command = model.Update(interrupt)
	model = next.(isoInstallerModel)
	if command == nil || model.shutdownChoice != indexChoiceValue(isoShutdownChoices(), "shutdown") {
		t.Fatalf("deliberate second Ctrl+C did not choose Shutdown: %#v", model)
	}
}

func TestISOInstallerRequestsHeldKeyEventMetadata(t *testing.T) {
	view := (isoInstallerModel{width: 90, height: 28}).View()
	if !view.KeyboardEnhancements.ReportEventTypes {
		t.Fatal("ISO installer did not request repeat and release event metadata")
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
	if command != nil || model.step != isoStepDisk || !model.diskConfirm ||
		model.diskConfirmAction != isoDiskConfirmationBack || model.config.Disk != "/dev/sda" {
		t.Fatalf("drive selection skipped or left its confirmation screen: %#v", model)
	}
}

func TestISOInstallerDiskConfirmationDefaultsSafeAndRequiresContinue(t *testing.T) {
	model := isoInstallerModel{
		step:     isoStepDisk,
		preview:  true,
		password: []rune("secret"),
		disks: []isoDiskChoice{{
			Choice:    isoChoice{Label: "Test drive", Value: "/dev/sda"},
			SizeBytes: 128 * 1024 * 1024 * 1024,
		}},
	}

	next, command := model.submitISODiskChoice(model.disks[0].Choice)
	model = next.(isoInstallerModel)
	if command != nil || model.diskConfirmAction != isoDiskConfirmationBack {
		t.Fatalf("drive confirmation did not default to Back: %#v", model)
	}

	next, command = model.handleISODiskConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command != nil || model.diskConfirm || model.step != isoStepDisk ||
		model.config.Disk != "/dev/sda" || string(model.password) != "secret" {
		t.Fatalf("default Enter did not return safely with state intact: %#v", model)
	}

	next, command = model.submitISODiskChoice(model.disks[0].Choice)
	model = next.(isoInstallerModel)
	if command != nil {
		t.Fatal("reselecting the drive started a command")
	}
	next, command = model.handleISODiskConfirmationKey(tea.KeyPressMsg{Code: tea.KeyDown})
	model = next.(isoInstallerModel)
	if command != nil || model.diskConfirmAction != isoDiskConfirmationContinue {
		t.Fatalf("Down did not select Continue: %#v", model)
	}
	next, command = model.handleISODiskConfirmationKey(tea.KeyPressMsg{Code: tea.KeyTab})
	model = next.(isoInstallerModel)
	if command != nil || model.diskConfirmAction != isoDiskConfirmationBack {
		t.Fatalf("Tab did not wrap to Back: %#v", model)
	}
	next, command = model.handleISODiskConfirmationKey(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift})
	model = next.(isoInstallerModel)
	if command != nil || model.diskConfirmAction != isoDiskConfirmationContinue {
		t.Fatalf("Shift+Tab did not wrap to Continue: %#v", model)
	}

	next, command = model.handleISODiskConfirmationKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	model = next.(isoInstallerModel)
	if command == nil || model.step != isoStepWriting || !model.allowQuit || len(model.password) != 0 {
		t.Fatalf("explicit Continue did not enter the protected write transition: %#v", model)
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
	for _, expected := range []string{"qvOS · Step 1/3", "REGION", "Keyboard", "Time zone", "Choose how qvOS types."} {
		if !strings.Contains(regionalContent, expected) {
			t.Fatalf("regional page is missing %q: %q", expected, regionalContent)
		}
	}
	if strings.Contains(regionalContent, "WELCOME") {
		t.Fatalf("regional page retained redundant welcome copy: %q", regionalContent)
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
	if strings.Contains(accountContent, "Create your sign-in") {
		t.Fatalf("account page retained redundant hint copy: %q", accountContent)
	}

	drive := isoInstallerModel{
		step:        isoStepDisk,
		diskConfirm: true,
		config:      isoInstallerConfig{Disk: "/dev/sda"},
		disks: []isoDiskChoice{{
			Choice: isoChoice{Label: "Test drive - 128 GiB", Value: "/dev/sda"},
		}},
	}
	left := drive.renderISODiskConfirmationControl(layoutDesktop)
	leftContent := stripANSI(left)
	leftCopy := strings.Join(strings.Fields(leftContent), " ")
	if !strings.Contains(leftCopy, "Test drive") ||
		!strings.Contains(leftCopy, "Everything on this drive will be erased.") ||
		strings.Contains(leftContent, "Continue") {
		t.Fatalf("drive confirmation left column did not stay focused on the selected disk: %q", leftContent)
	}
	context := drive.renderISOSetupContext(layoutDesktop)
	contextContent := stripANSI(context)
	for _, expected := range []string{"Back", "Continue"} {
		if !strings.Contains(contextContent, expected) {
			t.Fatalf("drive confirmation context is missing %s: %q", expected, contextContent)
		}
	}
	backRow, _ := textPosition(contextContent, "Back")
	continueRow, _ := textPosition(contextContent, "Continue")
	if backRow < 0 || continueRow <= backRow {
		t.Fatalf("drive confirmation does not place Back before Continue: %q", contextContent)
	}
	for _, hidden := range []string{
		"qvOS", "Step 3/3", "ERASE DRIVE?", "Install qvOS", "Everything on this drive will be erased.",
	} {
		if strings.Contains(contextContent, hidden) {
			t.Fatalf("drive confirmation context retained %q: %q", hidden, contextContent)
		}
	}
	if !strings.Contains(left, sISOBright.Render("Everything on this drive will be")) ||
		strings.Contains(leftContent, "·") {
		t.Fatalf("erase guidance is not bright, clean left-side copy: %q", left)
	}
	rule := strings.Repeat(tuiRailGlyph, inputWidthForMode(layoutDesktop))
	if !strings.Contains(context, sISOBright.Render("Back")) ||
		!strings.Contains(context, sGray.Render("Continue")) ||
		strings.Count(context, sRed.Render(rule)) != 1 ||
		!strings.Contains(context, sDim.Render(rule)) {
		t.Fatalf("safe-default Back/Continue fields are not styled consistently: %q", context)
	}
	drive.diskConfirmAction = isoDiskConfirmationContinue
	context = drive.renderISOSetupContext(layoutDesktop)
	if !strings.Contains(context, sGray.Render("Back")) ||
		!strings.Contains(context, sISOBright.Render("Continue")) ||
		strings.Count(context, sRed.Render(rule)) != 1 ||
		!strings.Contains(context, sDim.Render(rule)) {
		t.Fatalf("Continue focus did not move the one active rail: %q", context)
	}

	combined := stripANSI(drive.renderISOSetupSideBody(140, 31, layoutDesktop))
	combinedCopy := strings.Join(strings.Fields(combined), " ")
	for _, expected := range []string{"Test drive", "Everything on this drive will be", "erased.", "Back", "Continue"} {
		if !strings.Contains(combinedCopy, expected) {
			t.Fatalf("drive confirmation composition is missing %q: %q", expected, combined)
		}
	}
}

func TestISOInstallerRightContextUsesOneRestrainedHierarchy(t *testing.T) {
	context := (isoInstallerModel{step: isoStepRegional}).renderISOSetupContext(layoutDesktop)
	for _, expected := range []string{
		sGray.Render("qvOS"),
		sDim.Render(" · "),
		sDim.Render("Step 1/3"),
		sISOBright.Render("REGION"),
	} {
		if !strings.Contains(context, expected) {
			t.Fatalf("right context is missing its restrained hierarchy: %q", context)
		}
	}
	if strings.Contains(context, sWhite.Render("REGION")) {
		t.Fatalf("right context promoted REGION to full white: %q", context)
	}
	if strings.Contains(stripANSI(context), "Choose how qvOS") {
		t.Fatalf("right context retained the Region hint: %q", context)
	}

	canvasW, canvasH = 40, 20
	for _, role := range []modelRole{modelOneRing, modelTwoRings, modelThreeRings} {
		model := renderModelRole(role, 0)
		if strings.TrimSpace(stripANSI(model)) == "" {
			t.Fatalf("ISO model role %d rendered empty", role)
		}
		for _, style := range []cellStyle{cellRed, cellHot, cellDeepRed} {
			for shade := 1; shade < len(shadeRamp); shade++ {
				if strings.Contains(model, renderedRamp[style][shade]) {
					t.Fatalf("ISO model role %d retained red style %d", role, style)
				}
			}
		}
	}
}

func TestISOInstallerKeepsOneFixedHintOnTheLeftAcrossAllSteps(t *testing.T) {
	regional := isoInstallerModel{
		step:          isoStepRegional,
		regionalFocus: isoRegionalKeyboard,
		keyboards:     []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones:     []isoChoice{{Label: "Cairo", Value: "Africa/Cairo"}},
		config:        isoInstallerConfig{Keyboard: "us", Timezone: "Africa/Cairo"},
	}
	account := isoInstallerModel{step: isoStepAccount, hostname: []rune("qvOS")}
	drive := isoInstallerModel{
		step:  isoStepDisk,
		disks: []isoDiskChoice{{Choice: isoChoice{Label: "Test drive", Value: "/dev/sda"}}},
	}

	cases := []struct {
		name    string
		model   isoInstallerModel
		control string
		hint    string
	}{
		{"region", regional, regional.renderISORegionalControl(layoutDesktop), "Choose how qvOS types."},
		{"account", account, account.renderISOAccountControl(layoutDesktop), "Use lowercase letters and numbers."},
		{"drive", drive, drive.renderISODiskControl(layoutDesktop), "Choose where qvOS will be installed."},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if !strings.Contains(stripANSI(test.control), test.hint) {
				t.Fatalf("left control is missing %q: %q", test.hint, stripANSI(test.control))
			}
			if height := lipgloss.Height(strings.Join(test.model.renderISOSetupHint(layoutDesktop), "\n")); height != isoSetupHintRows {
				t.Fatalf("hint height = %d, want %d", height, isoSetupHintRows)
			}
			if strings.Contains(stripANSI(test.model.renderISOSetupContext(layoutDesktop)), test.hint) {
				t.Fatalf("right context retained left-side hint %q", test.hint)
			}
		})
	}
}

func TestISOInstallerAccountGuidanceKeepsAReservedHeight(t *testing.T) {
	hints := map[isoAccountField]string{
		isoAccountUsername:        "Use lowercase letters and numbers.",
		isoAccountHostname:        "Name this machine on your network.",
		isoAccountPassword:        "Use a long, unique password.",
		isoAccountPasswordConfirm: "Type the same password again.",
	}
	baseHeight := 0
	for focus, hint := range hints {
		model := isoInstallerModel{
			step:         isoStepAccount,
			accountFocus: focus,
			hostname:     []rune("qvOS"),
		}
		rendered := model.renderISOAccountControl(layoutDesktop)
		if !strings.Contains(stripANSI(rendered), hint) {
			t.Fatalf("account focus %d is missing its hint: %q", focus, stripANSI(rendered))
		}
		if baseHeight == 0 {
			baseHeight = lipgloss.Height(rendered)
		} else if height := lipgloss.Height(rendered); height != baseHeight {
			t.Fatalf("account focus %d moved control height to %d, want %d", focus, height, baseHeight)
		}
	}

	mismatch := isoInstallerModel{
		step:         isoStepAccount,
		accountFocus: isoAccountPasswordConfirm,
		hostname:     []rune("qvOS"),
		errorText:    "make sure passwords match",
	}
	rendered := mismatch.renderISOAccountControl(layoutDesktop)
	if height := lipgloss.Height(rendered); height != baseHeight {
		t.Fatalf("password guidance moved control height to %d, want %d", height, baseHeight)
	}
	if !strings.Contains(rendered, sISOBright.Render("make sure passwords match")) ||
		strings.Contains(stripANSI(rendered), "Type the same password again.") ||
		strings.Contains(stripANSI(rendered), "·") {
		t.Fatalf("password mismatch did not replace the hint with clean bright copy: %q", rendered)
	}
}

func TestISOInstallerFatalSetupErrorUsesCalmCopy(t *testing.T) {
	model := newISOInstallerModel(true)
	next, command := model.Update(isoInstallerDoneMsg{err: errors.New("openssl password hash failed: noisy detail")})
	model = next.(isoInstallerModel)
	if command != nil || model.step != isoStepError || model.errorText != "could not prepare the installation" {
		t.Fatalf("fatal setup error exposed technical detail: %#v", model)
	}
}

func TestISOInstallerRegionalErrorReplacesTheReservedHint(t *testing.T) {
	model := isoInstallerModel{
		step:          isoStepRegional,
		regionalFocus: isoRegionalKeyboard,
		keyboards:     []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones:     []isoChoice{{Label: "Cairo", Value: "Africa/Cairo"}},
		config:        isoInstallerConfig{Keyboard: "us", Timezone: "Africa/Cairo"},
		errorText:     "try another keyboard layout",
	}
	rendered := model.renderISORegionalControl(layoutDesktop)
	content := stripANSI(rendered)
	if !strings.Contains(content, "try another keyboard layout") {
		t.Fatalf("regional error was not visible: %q", content)
	}
	if !strings.Contains(rendered, sISOBright.Render("try another keyboard layout")) ||
		strings.Contains(content, "Choose how qvOS types.") {
		t.Fatalf("regional error did not replace the fixed hint with bright copy: %q", rendered)
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

func TestISOInstallerUsesQuietColumnsForWideSetupOnly(t *testing.T) {
	regional := isoInstallerModel{
		step:      isoStepRegional,
		width:     140,
		height:    31,
		keyboards: []isoChoice{{Label: "English (US)", Value: "us"}},
		timezones: []isoChoice{{Label: "UTC", Value: "UTC"}},
		config:    isoInstallerConfig{Keyboard: "us", Timezone: "UTC"},
	}
	content := stripANSI(regional.View().Content)
	if strings.Contains(content, "│") || !strings.Contains(content, "REGION") || !strings.Contains(content, "Keyboard") {
		t.Fatalf("wide setup is missing its quiet two-column composition: %q", content)
	}
	_, keyboardColumn := textPosition(content, "Keyboard")
	_, regionColumn := textPosition(content, "REGION")
	if keyboardColumn < 0 || regionColumn < 0 || keyboardColumn >= regional.width/2 || regionColumn <= regional.width/2 {
		t.Fatalf("wide setup columns moved: keyboard=%d region=%d", keyboardColumn, regionColumn)
	}
	assertViewFits(t, regional.View().Content, regional.width, regional.height)

	regional.width, regional.height = 70, 28
	if content := stripANSI(regional.View().Content); strings.Contains(content, "│") {
		t.Fatalf("narrow setup did not stack safely: %q", content)
	}
}

func TestISOInstallerWrapsCompleteDiskLabelsUnderOneSelectedRail(t *testing.T) {
	selectedLabel := "/dev/nvme0n1 (238.5G) - Samsung SSD 970 EVO Plus Internal Drive"
	model := isoInstallerModel{
		step:        isoStepDisk,
		choiceIndex: 1,
		disks: []isoDiskChoice{
			{Choice: isoChoice{Label: "/dev/sda (64G) - Quiet backup drive", Value: "/dev/sda"}},
			{Choice: isoChoice{Label: selectedLabel, Value: "/dev/nvme0n1"}},
		},
	}
	choices := []isoChoice{model.disks[0].Choice, model.disks[1].Choice}
	styled := strings.Join(model.visibleDiskChoiceRows(choices, layoutDesktop), "\n")
	content := stripANSI(styled)
	normalized := strings.Join(strings.Fields(strings.ReplaceAll(content, "│", "")), " ")
	if !strings.Contains(normalized, selectedLabel) {
		t.Fatalf("wrapped disk choice lost its complete label: %q", content)
	}
	selectedLines := wrapDisplayLines([]string{selectedLabel}, inputWidthForMode(layoutDesktop)-2)
	if rails := strings.Count(styled, sRed.Render("│")); rails != len(selectedLines) {
		t.Fatalf("selected disk rails = %d, want %d across %q", rails, len(selectedLines), styled)
	}
	if strings.Contains(content, "…") {
		t.Fatalf("disk label was truncated instead of wrapped: %q", content)
	}

	model.config.Disk = "/dev/nvme0n1"
	model.diskConfirm = true
	confirmation := model.renderISODiskConfirmationControl(layoutDesktop)
	confirmationText := stripANSI(confirmation)
	normalized = strings.Join(strings.Fields(strings.ReplaceAll(confirmationText, "│", "")), " ")
	if !strings.Contains(normalized, selectedLabel) {
		t.Fatalf("disk confirmation lost the complete selection: %q", confirmationText)
	}
	if strings.Contains(confirmationText, "Continue") || strings.Contains(confirmationText, "Install qvOS") {
		t.Fatalf("disk selection column retained the final action: %q", confirmationText)
	}
	if rails := strings.Count(confirmation, sDeepRed.Render("│")); rails != len(selectedLines) {
		t.Fatalf("completed confirmation rails = %d, want %d: %q", rails, len(selectedLines), confirmation)
	}
	if strings.Contains(confirmation, sRed.Render("│")) ||
		!strings.Contains(confirmation, sISOBright.Render("Everything on this drive will be")) {
		t.Fatalf("completed disk did not dim while the erase hint became bright: %q", confirmation)
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

func TestISOPrimaryActionUsesNearWhiteWithoutAMarker(t *testing.T) {
	want := sISOBright.Render("Reboot")
	if got := renderISOPrimaryAction("Reboot"); got != want {
		t.Fatalf("primary action style = %q, want %q", got, want)
	}
}

func TestISOInputFieldsStartAtTheLeftEdge(t *testing.T) {
	styled := renderISOInputField("secret", true, false, layoutDesktop)
	rendered := stripANSI(styled)
	firstLine := strings.Split(rendered, "\n")[0]
	if !strings.HasPrefix(firstLine, "secret") {
		t.Fatalf("input did not start at the left edge: %q", rendered)
	}
	if !strings.Contains(styled, sISOBright.Render("secret")) ||
		!strings.Contains(styled, sRed.Render(strings.Repeat("─", inputWidthForMode(layoutDesktop)))) {
		t.Fatalf("active input did not use near-white text and one red rail: %q", styled)
	}
}

func TestISOAccountEmptyFieldsRenderEmpty(t *testing.T) {
	rendered := strings.Split(stripANSI((isoInstallerModel{
		step:         isoStepAccount,
		accountFocus: isoAccountUsername,
	}).renderISOAccountControl(layoutDesktop)), "\n")

	for _, label := range []string{"Username", "Machine Name"} {
		labelIndex := -1
		for index, line := range rendered {
			if strings.TrimSpace(line) == label {
				labelIndex = index
				break
			}
		}
		if labelIndex < 0 || labelIndex+1 >= len(rendered) {
			t.Fatalf("account control is missing %q: %q", label, strings.Join(rendered, "\n"))
		}
		if value := strings.TrimSpace(rendered[labelIndex+1]); value != "" {
			t.Fatalf("empty %s rendered placeholder value %q", label, value)
		}
	}
}

func TestISOInputRailsShowSelectedPendingAndCompleteStates(t *testing.T) {
	rule := strings.Repeat("─", inputWidthForMode(layoutDesktop))
	selected := renderISOInputField("selected", true, false, layoutDesktop)
	if !strings.Contains(selected, sISOBright.Render("selected")) || !strings.Contains(selected, sRed.Render(rule)) {
		t.Fatalf("selected field is missing near-white text or red rail: %q", selected)
	}
	pending := renderISOInputField("pending", false, false, layoutDesktop)
	if !strings.Contains(pending, sMid.Render("pending")) || !strings.Contains(pending, sGray.Render(rule)) {
		t.Fatalf("pending field is not slightly bright: %q", pending)
	}
	complete := renderISOInputField("complete", false, true, layoutDesktop)
	if !strings.Contains(complete, sGray.Render("complete")) || !strings.Contains(complete, sDim.Render(rule)) {
		t.Fatalf("complete field is not dimmed: %q", complete)
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

func TestISOProgressAllowsTheInstallerToTerminateIt(t *testing.T) {
	quit := tea.QuitMsg{}
	if got := filterISOProgressExitMessages(isoProgressModel{}, quit); got == nil {
		t.Fatal("ISO progress swallowed the installer termination message")
	}

	for _, guarded := range []tea.Msg{tea.InterruptMsg{}, tea.SuspendMsg{}} {
		if got := filterISOProgressExitMessages(isoProgressModel{}, guarded); got != nil {
			t.Fatalf("ISO progress accepted guarded signal message %T", guarded)
		}
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
		name string
		logs bool
	}{
		{"progress", false},
		{"logs", true},
	}

	for _, size := range sizes {
		for _, state := range states {
			t.Run(size.name+"/"+state.name, func(t *testing.T) {
				model := isoProgressModel{
					width:      size.width,
					height:     size.height,
					progress:   0.42,
					status:     "installing qvOS",
					logLines:   []string{"installing base system", "applying qvOS"},
					logOverlay: state.logs,
				}
				assertViewFits(t, model.View().Content, size.width, size.height)
			})
		}
	}
}

func TestISOProgressShowsOnlyMessagePercentageAndBar(t *testing.T) {
	model := isoProgressModel{
		width:    140,
		height:   31,
		progress: 0.42,
		status:   "installing qvOS",
	}
	content := stripANSI(model.View().Content)
	for _, expected := range []string{"installing qvOS", "42%", tuiRailGlyph} {
		if !strings.Contains(content, expected) {
			t.Fatalf("simple ISO progress is missing %q: %q", expected, content)
		}
	}
	for _, hidden := range []string{"INSTALLING QVOS", "v log", "ctrl+v terminal"} {
		if strings.Contains(content, hidden) {
			t.Fatalf("simple ISO progress retained %q: %q", hidden, content)
		}
	}
	if !strings.Contains(content, "Estimated 4:00  -  ? Help") {
		t.Fatalf("simple ISO progress is missing its estimate and Help footer: %q", content)
	}
	bar := renderProgressRail(0.42, 0)
	if !strings.Contains(bar, renderTUIRail(14, sRed)) ||
		!strings.Contains(bar, renderTUIRail(20, sDim)) || strings.Contains(bar, "━") {
		t.Fatalf("ISO progress is not using the shared thin red/dim rail: %q", bar)
	}
}

func TestISOProgressEstimateCountsDownThenStaysCalm(t *testing.T) {
	tests := []struct {
		name  string
		frame int
		want  string
	}{
		{"start", 0, "Estimated 4:00"},
		{"one second", framesPerSecond * framesPerTick, "Estimated 3:59"},
		{"last second", (isoProgressEstimate - 1) * framesPerSecond * framesPerTick, "Estimated 0:01"},
		{"estimate reached", isoProgressEstimate * framesPerSecond * framesPerTick, "Any moment now"},
		{"estimate passed", (isoProgressEstimate + 90) * framesPerSecond * framesPerTick, "Any moment now"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := (isoProgressModel{frame: test.frame}).isoProgressEstimateLabel(); got != test.want {
				t.Fatalf("estimate = %q, want %q", got, test.want)
			}
		})
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

func TestISOChoicesUseBrightnessWithoutMarkerClutter(t *testing.T) {
	row := stripANSI(renderISOChoiceRow("English (US)", true))
	if row != "English (US)" {
		t.Fatalf("selected ISO choice = %q", row)
	}
	if strings.ContainsAny(row, "•›>0123456789") {
		t.Fatalf("ISO choice retained marker decoration: %q", row)
	}
	if selected := renderISOChoiceRow("English (US)", true); selected != sISOBright.Render("English (US)") {
		t.Fatalf("selected ISO choice is not near-white: %q", selected)
	}
	if unselected := renderISOChoiceRow("English (US)", false); unselected != sGray.Render("English (US)") {
		t.Fatalf("unselected ISO choice is not dim grayscale: %q", unselected)
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
