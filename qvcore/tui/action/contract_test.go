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

	for _, line := range []string{
		"qvOS action: preparing",
		"qvOS action: applying",
		"qvOS action: verifying",
		"qvOS action: complete",
	} {
		if !IsProtocolLine(line) {
			t.Fatalf("milestone is not recognized as internal protocol: %q", line)
		}
	}
	if IsProtocolLine("Downloading owner package") {
		t.Fatal("real owner output was classified as internal protocol")
	}
}

func TestInstallStopPromptKeepsTheOwnerRunningByDefault(t *testing.T) {
	spec := Spec{Operation: "install", Title: "Helix"}
	for _, expected := range []string{
		"STOP INSTALL?",
		"Helix keeps running until you confirm",
		"Keep Installing",
		"Stop Install",
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

func TestInformationTaskOmitsTransactionCopy(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "battery-status")
	t.Setenv("QVOS_ACTION_OPERATION", "task")
	t.Setenv("QVOS_ACTION_TITLE", "Battery Protection")
	t.Setenv("QVOS_ACTION_SUMMARY", "Inspect the charging-protection state")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "0")
	t.Setenv("QVOS_ACTION_RINGS", "1")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "information")

	spec, err := FromEnvironment()
	if err != nil {
		t.Fatalf("task spec: %v", err)
	}
	if spec.Rings != 1 || !spec.Information || spec.Primary != "" ||
		spec.Active != "" || spec.Complete != "" {
		t.Fatalf("information task contract = %#v", spec)
	}

	t.Setenv("QVOS_ACTION_PRIMARY", "Inspect")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("information task accepted transaction copy")
	}
}

func TestTaskSpecRejectsMissingCopyOrInvalidRings(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "firmware-update")
	t.Setenv("QVOS_ACTION_OPERATION", "task")
	t.Setenv("QVOS_ACTION_TITLE", "Firmware")
	t.Setenv("QVOS_ACTION_SUMMARY", "Update system firmware")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "1")
	t.Setenv("QVOS_ACTION_RINGS", "4")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
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

	t.Setenv("QVOS_ACTION_COMPLETE", "Updated")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "unknown")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("invalid task behavior contract passed validation")
	}
}

func TestTaskSpecLoadsSearchableSelectionContract(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "timezone")
	t.Setenv("QVOS_ACTION_OPERATION", "task")
	t.Setenv("QVOS_ACTION_TITLE", "Timezone")
	t.Setenv("QVOS_ACTION_SUMMARY", "Choose and apply the system timezone")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "1")
	t.Setenv("QVOS_ACTION_RINGS", "1")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_PRIMARY", "Set")
	t.Setenv("QVOS_ACTION_ACTIVE", "Setting")
	t.Setenv("QVOS_ACTION_COMPLETE", "Set")
	t.Setenv("QVOS_ACTION_SELECTION_MODE", "single")
	t.Setenv("QVOS_ACTION_SELECTION_TITLE", "Select Timezone")
	t.Setenv("QVOS_ACTION_SELECTION_EMPTY", "No timezones are available.")

	spec, err := FromEnvironment()
	if err != nil {
		t.Fatalf("selection spec: %v", err)
	}
	if !spec.HasSelection() || spec.AllowsMultipleSelections() ||
		spec.SelectionTitle != "Select Timezone" ||
		spec.SelectionEmpty != "No timezones are available." {
		t.Fatalf("selection contract = %#v", spec)
	}

	t.Setenv("QVOS_ACTION_SELECTION_MODE", "multi")
	spec, err = FromEnvironment()
	if err != nil || !spec.AllowsMultipleSelections() {
		t.Fatalf("multi-selection contract = %#v / %v", spec, err)
	}

	t.Setenv("QVOS_ACTION_SELECTION_TITLE", "")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("selection without a title passed validation")
	}
}

func TestTaskSpecLoadsActionChoiceWithOnePrivilegedBranch(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "font-cascadia-mono")
	t.Setenv("QVOS_ACTION_OPERATION", "task")
	t.Setenv("QVOS_ACTION_TITLE", "Cascadia Mono")
	t.Setenv("QVOS_ACTION_SUMMARY", "Apply Cascadia Mono across qvOS")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "0")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_PRIMARY", "Apply")
	t.Setenv("QVOS_ACTION_ACTIVE", "Applying")
	t.Setenv("QVOS_ACTION_COMPLETE", "Applied")
	t.Setenv("QVOS_ACTION_SELECTION_MODE", "action")
	t.Setenv("QVOS_ACTION_SELECTION_TITLE", "Cascadia Mono")
	t.Setenv("QVOS_ACTION_SUMMARY_SELECTION", "Uninstall")
	t.Setenv("QVOS_ACTION_SELECTION_SUMMARY", "Remove Cascadia Mono from the system")
	t.Setenv("QVOS_ACTION_SELECTION_REQUIRES_SUDO", "1")

	spec, err := FromEnvironment()
	if err != nil {
		t.Fatalf("action-choice spec: %v", err)
	}
	if !spec.IsActionSelection() || spec.RequiresSudo ||
		spec.ForSelection("Apply Now").RequiresSudo ||
		!spec.ForSelection("Uninstall").RequiresSudo ||
		spec.ForSelection("Apply Now").RollbackProtocol != "" ||
		spec.ForSelection("Uninstall").RollbackProtocol != "" {
		t.Fatalf("action-choice contract = %#v", spec)
	}

	t.Setenv("QVOS_ACTION_SELECTION_SUMMARY", "")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("action choice without privileged summary passed validation")
	}
}

func TestUninstallSpecLoadsPrivilegedScopeChoices(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "steam")
	t.Setenv("QVOS_ACTION_OPERATION", "uninstall")
	t.Setenv("QVOS_ACTION_TITLE", "Steam")
	t.Setenv(
		"QVOS_ACTION_SUMMARY",
		"Remove Steam while keeping game libraries, settings, and caches",
	)
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "1")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_SELECTION_MODE", "action")
	t.Setenv("QVOS_ACTION_SELECTION_TITLE", "Remove Steam")
	t.Setenv("QVOS_ACTION_SELECTION_EMPTY", "No Steam removal choices are available.")
	t.Setenv("QVOS_ACTION_SUMMARY_SELECTION", "Remove Local Game Libraries")
	t.Setenv(
		"QVOS_ACTION_SELECTION_SUMMARY",
		"Remove Steam, local game libraries, settings, and caches",
	)
	t.Setenv("QVOS_ACTION_SELECTION_REQUIRES_SUDO", "1")

	spec, err := FromEnvironment()
	if err != nil {
		t.Fatalf("privileged scope spec: %v", err)
	}
	keep := spec.ForSelection("Keep Game Libraries")
	remove := spec.ForSelection("Remove Local Game Libraries")
	if !keep.RequiresSudo || !remove.RequiresSudo ||
		keep.Operation != "uninstall" || remove.Operation != "uninstall" ||
		keep.Summary != "Remove Steam while keeping game libraries, settings, and caches" ||
		remove.Summary != "Remove Steam, local game libraries, settings, and caches" {
		t.Fatalf("privileged scope choices = %#v / %#v", keep, remove)
	}
}

func TestInstallSpecLoadsOwnerFormBeforeAuthorization(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "windows")
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	t.Setenv("QVOS_ACTION_TITLE", "Windows")
	t.Setenv("QVOS_ACTION_SUMMARY", "Configure a private Windows VM")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "1")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_FORM", "owner-json-v1")
	t.Setenv("QVOS_ACTION_ROLLBACK", "owner-state-v1")

	spec, err := FromEnvironment()
	if err != nil || !spec.HasForm() || !spec.RequiresSudo ||
		spec.RollbackProtocol != "owner-state-v1" {
		t.Fatalf("Windows form contract = %#v, %v", spec, err)
	}

	t.Setenv("QVOS_ACTION_FORM", "unknown")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("unknown action form contract passed validation")
	}
}

func TestUnprivilegedRemovalChoiceCanChangeSummaryWithoutAddingSudo(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "windows")
	t.Setenv("QVOS_ACTION_OPERATION", "uninstall")
	t.Setenv("QVOS_ACTION_TITLE", "Windows")
	t.Setenv("QVOS_ACTION_SUMMARY", "Remove Windows while keeping its virtual disk")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "0")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_SELECTION_MODE", "action")
	t.Setenv("QVOS_ACTION_SELECTION_TITLE", "Remove Windows")
	t.Setenv("QVOS_ACTION_SELECTION_EMPTY", "No Windows removal choices are available.")
	t.Setenv("QVOS_ACTION_SUMMARY_SELECTION", "Delete Virtual Disk")
	t.Setenv("QVOS_ACTION_SELECTION_SUMMARY", "Remove Windows and its virtual disk")
	t.Setenv("QVOS_ACTION_SELECTION_REQUIRES_SUDO", "0")

	spec, err := FromEnvironment()
	if err != nil {
		t.Fatalf("Windows removal contract: %v", err)
	}
	keep := spec.ForSelection("Keep Virtual Disk")
	remove := spec.ForSelection("Delete Virtual Disk")
	if keep.RequiresSudo || remove.RequiresSudo ||
		keep.Summary != "Remove Windows while keeping its virtual disk" ||
		remove.Summary != "Remove Windows and its virtual disk" {
		t.Fatalf("Windows scope choices = %#v / %#v", keep, remove)
	}
}

func TestSpecLoadsOnlySingleLineMutationSuccessGuidance(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "chromium-account")
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	t.Setenv("QVOS_ACTION_TITLE", "Chromium Account")
	t.Setenv("QVOS_ACTION_SUMMARY", "Configure Chromium account support")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "0")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv(
		"QVOS_ACTION_NEXT_STEP",
		"Restart Chromium, then open Settings > You and Google to sign in.",
	)

	spec, err := FromEnvironment()
	if err != nil {
		t.Fatalf("success guidance spec: %v", err)
	}
	if spec.NextStep != "Restart Chromium, then open Settings > You and Google to sign in." {
		t.Fatalf("success guidance = %q", spec.NextStep)
	}

	t.Setenv("QVOS_ACTION_NEXT_STEP", "first line\nsecond line")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("multi-line success guidance passed validation")
	}

	t.Setenv("QVOS_ACTION_NEXT_STEP", "Irrelevant next step")
	t.Setenv("QVOS_ACTION_OPERATION", "task")
	t.Setenv("QVOS_ACTION_PRIMARY", "Inspect")
	t.Setenv("QVOS_ACTION_ACTIVE", "Inspecting")
	t.Setenv("QVOS_ACTION_COMPLETE", "Inspected")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "information")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("information action accepted a transactional next step")
	}
}

func TestInstallSpecLoadsOnlyCompleteOwnerPostAction(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "windows")
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	t.Setenv("QVOS_ACTION_TITLE", "Windows")
	t.Setenv("QVOS_ACTION_SUMMARY", "Configure Windows")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "1")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_POST_LABEL", "launch")
	t.Setenv("QVOS_ACTION_POST_SUCCESS", "owner-v1")

	spec, err := FromEnvironment()
	if err != nil || !spec.HasPostAction() || spec.PostActionLabel != "launch" {
		t.Fatalf("post-success action = %#v, %v", spec, err)
	}
	postSpec, err := spec.ForPostAction()
	if err != nil || postSpec.HasPostAction() || postSpec.HasForm() ||
		postSpec.Primary != "Launch" || postSpec.Active != "Launching" ||
		postSpec.Complete != "Launched" ||
		postSpec.Summary != "Download Windows and start the VM" {
		t.Fatalf("streamed post-success action = %#v, %v", postSpec, err)
	}

	t.Setenv("QVOS_ACTION_POST_LABEL", "")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("post-success action without a label passed validation")
	}
	t.Setenv("QVOS_ACTION_POST_LABEL", "launch")
	t.Setenv("QVOS_ACTION_OPERATION", "uninstall")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("uninstall accepted an install post-success action")
	}
}

func TestPostSuccessResumeUsesSharedLifecycleCopy(t *testing.T) {
	t.Setenv("QVOS_ACTION_SLUG", "windows")
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	t.Setenv("QVOS_ACTION_TITLE", "Windows")
	t.Setenv("QVOS_ACTION_SUMMARY", "Configure Windows")
	t.Setenv("QVOS_ACTION_REQUIRES_SUDO", "0")
	t.Setenv("QVOS_ACTION_RINGS", "2")
	t.Setenv("QVOS_ACTION_BEHAVIOR", "mutation")
	t.Setenv("QVOS_ACTION_POST_LABEL", "launch")
	t.Setenv("QVOS_ACTION_POST_SUCCESS", "owner-v1")
	t.Setenv("QVOS_ACTION_POST_RESUME", "1")

	spec, err := FromEnvironment()
	if err != nil || spec.Primary != "Launch" || spec.Active != "Launching" ||
		spec.Complete != "Launched" || spec.Summary != "Download Windows and start the VM" ||
		spec.HasPostAction() {
		t.Fatalf("resumed post-success copy = %#v, %v", spec, err)
	}

	t.Setenv("QVOS_ACTION_POST_RESUME", "unknown")
	if _, err := FromEnvironment(); err == nil {
		t.Fatal("invalid post-success resume contract passed validation")
	}
}
