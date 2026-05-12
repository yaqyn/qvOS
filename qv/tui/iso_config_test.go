package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
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

func TestISOInstallerFlowCollectsOptionalIdentity(t *testing.T) {
	model := isoInstallerModel{step: isoStepUsername, input: []rune("QV")}

	next, _ := model.submitISOInput()
	model = next.(isoInstallerModel)
	if model.step != isoStepFullName {
		t.Fatalf("step = %v, want isoStepFullName", model.step)
	}
	if model.config.Username != "qv" {
		t.Fatalf("username = %q, want qv", model.config.Username)
	}

	model.input = []rune("qvOS User")
	next, _ = model.submitISOInput()
	model = next.(isoInstallerModel)
	if model.step != isoStepEmail {
		t.Fatalf("step = %v, want isoStepEmail", model.step)
	}
	if model.config.FullName != "qvOS User" {
		t.Fatalf("full name = %q, want qvOS User", model.config.FullName)
	}

	model.input = []rune("qvos@example.test")
	next, _ = model.submitISOInput()
	model = next.(isoInstallerModel)
	if model.step != isoStepPassword {
		t.Fatalf("step = %v, want isoStepPassword", model.step)
	}
	if model.config.EmailAddress != "qvos@example.test" {
		t.Fatalf("email = %q, want qvos@example.test", model.config.EmailAddress)
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
