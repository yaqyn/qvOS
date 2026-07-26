package main

import "testing"

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
}
