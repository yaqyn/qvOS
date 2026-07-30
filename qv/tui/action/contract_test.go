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

func TestTaskSpecLoadsExplicitCopyAndRingRole(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "refresh-waybar")
	t.Setenv("QVOS_ACTION_OPERATION", "task")
	t.Setenv("QVOS_ACTION_TITLE", "Waybar Config")
	t.Setenv("QVOS_ACTION_SUMMARY", "Restore Waybar defaults with qvOS overrides")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "0")
	t.Setenv("QVOS_ACTION_RINGS", "1")
	t.Setenv("QVOS_ACTION_PRIMARY", "Restore")
	t.Setenv("QVOS_ACTION_ACTIVE", "Restoring")
	t.Setenv("QVOS_ACTION_COMPLETE", "Restored")

	spec, err := FromEnvironment()
	if err != nil {
		t.Fatalf("task spec: %v", err)
	}
	if spec.Rings != 1 ||
		spec.Heading() != "RESTORE WAYBAR CONFIG" ||
		spec.ActiveTitle() != "RESTORING" ||
		spec.PastTense() != "RESTORED" ||
		spec.RunningStatus() != "restoring Waybar Config" ||
		spec.CompleteStatus() != "Waybar Config restored" {
		t.Fatalf("task copy = %#v", spec)
	}
}

func TestTaskSpecRejectsMissingCopyOrInvalidRings(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "firmware-update")
	t.Setenv("QVOS_ACTION_OPERATION", "task")
	t.Setenv("QVOS_ACTION_TITLE", "Firmware")
	t.Setenv("QVOS_ACTION_SUMMARY", "Update system firmware")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "1")
	t.Setenv("QVOS_ACTION_RINGS", "4")
	t.Setenv("QVOS_ACTION_PRIMARY", "Update")
	t.Setenv("QVOS_ACTION_ACTIVE", "Updating")
	t.Setenv("QVOS_ACTION_COMPLETE", "Updated")

	if _, err := FromEnvironment(); err == nil {
		t.Fatal("invalid task ring contract passed validation")
	}

	t.Setenv("QVOS_ACTION_RINGS", "3")
	t.Setenv("QVOS_ACTION_COMPLETE", "")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("incomplete task copy contract passed validation")
	}
}
