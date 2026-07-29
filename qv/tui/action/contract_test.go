package action

import (
	"strings"
	"testing"
)

func TestSpecCopyMatchesInstallAndUninstall(t *testing.T) {
	install := Spec{Operation: "install", Title: "Rust"}
	if install.Heading() != "INSTALL RUST" ||
		install.PrimaryAction() != "Install" ||
		install.PastTense() != "INSTALLED" {
		t.Fatalf("install copy = %#v", install)
	}

	uninstall := Spec{Operation: "uninstall", Title: "Go"}
	if uninstall.Heading() != "UNINSTALL GO" ||
		uninstall.PrimaryAction() != "Uninstall" ||
		uninstall.PastTense() != "UNINSTALLED" {
		t.Fatalf("uninstall copy = %#v", uninstall)
	}
}

func TestProgressUsesOnlyOwnedMilestones(t *testing.T) {
	spec := Spec{Operation: "install", Title: "Rust"}
	status, progress := ProgressFromLine("qvOS action: verifying", spec)
	if status != "verifying Rust" || progress != 0.88 {
		t.Fatalf("verification milestone = %q / %f", status, progress)
	}

	status, progress = ProgressFromLine("downloading a package", spec)
	if status != "" || progress >= 0 {
		t.Fatalf("unknown output fabricated progress = %q / %f", status, progress)
	}
}

func TestStopPromptKeepsTheOwnerRunningByDefault(t *testing.T) {
	spec := Spec{Operation: "uninstall", Title: "Steam"}
	for _, expected := range []string{
		"STOP UNINSTALL?",
		"Steam keeps running until you confirm",
		"Keep Uninstalling",
		"Stop Uninstall",
	} {
		copy := strings.Join([]string{
			spec.StopPromptTitle(),
			spec.StopPromptNotice(),
			spec.KeepRunningAction(),
			spec.StopAction(),
		}, "\n")
		if !strings.Contains(copy, expected) {
			t.Fatalf("stop copy is missing %q: %q", expected, copy)
		}
	}
}
