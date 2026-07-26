package main

import "testing"

func TestInstallMenuContainsOnlySupportedLifecycleActions(t *testing.T) {
	got := sections[0].items
	want := []item{
		{"00", "UPDATE", "Sync qvOS"},
		{"01", "REPAIR", "Repair qvOS"},
		{"02", "BUILD", "Build qvOS ISO"},
	}

	if len(got) != len(want) {
		t.Fatalf("install action count = %d, want %d", len(got), len(want))
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("install action %d = %#v, want %#v", index, got[index], want[index])
		}
	}
}

func TestRepairActionUsesTheQvOSMaintenanceOwner(t *testing.T) {
	script, environment, err := rootScriptSpec(actionRepair)
	if err != nil {
		t.Fatalf("repair action spec: %v", err)
	}
	if script != "bin/qvos-repair" {
		t.Fatalf("repair script = %q", script)
	}
	if environment != "QVOS_REPAIR_SCRIPT" {
		t.Fatalf("repair environment = %q", environment)
	}
	if rootActionName(actionRepair) != "REPAIR" {
		t.Fatalf("repair action name = %q", rootActionName(actionRepair))
	}
	if rootActionCompleteStatus(actionRepair) != "repair complete" {
		t.Fatalf("repair completion = %q", rootActionCompleteStatus(actionRepair))
	}

	status, progress := scriptProgressFromLine(actionRepair, "qvOS repair: Runtime")
	if status != "runtime" || progress <= 0 {
		t.Fatalf("repair progress = %q, %f", status, progress)
	}

	status, progress = scriptProgressFromLine(
		actionRepair,
		"qvOS repair: Enabled optional qvCORE setups",
	)
	if status != "enabled optional qvcore setups" || progress <= 0 {
		t.Fatalf("optional qvCORE repair progress = %q, %f", status, progress)
	}
}

func TestUpdateActionUsesTheQvOSMaintenanceOwner(t *testing.T) {
	script, environment, err := rootScriptSpec(actionUpdate)
	if err != nil {
		t.Fatalf("update action spec: %v", err)
	}
	if script != "bin/qvos-update" {
		t.Fatalf("update script = %q", script)
	}
	if environment != "QVOS_UPDATE_SCRIPT" {
		t.Fatalf("update environment = %q", environment)
	}

	status, progress := scriptProgressFromLine(actionUpdate, "Update system packages")
	if status != "updating system packages" || progress <= 0 {
		t.Fatalf("update progress = %q, %f", status, progress)
	}

	status, progress = scriptProgressFromLine(actionUpdate, "qvOS update is complete.")
	if status != "update complete" || progress != 1 {
		t.Fatalf("update completion = %q, %f", status, progress)
	}
}
