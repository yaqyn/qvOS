package main

import (
	"testing"

	actionflow "github.com/Yaqyn-qvOS/qvOS/action"
)

func TestFlowRequirementsCentralizeDomainCapabilities(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() {
		currentActionSpec = previousSpec
	})

	update := requirementsForAction(actionUpdate)
	if update.Model != modelThreeRings || update.Confirmation || !update.Preflight ||
		!update.Authorization || !update.ProgressBar {
		t.Fatalf("update requirements = %#v", update)
	}

	currentActionSpec.RequiresSudo = false
	software := requirementsForAction(actionGeneric)
	if software.Model != modelTwoRings || !software.Confirmation || !software.Preflight ||
		software.Authorization || !software.ProgressBar {
		t.Fatalf("unprivileged software requirements = %#v", software)
	}

	currentActionSpec.RequiresSudo = true
	if software = requirementsForAction(actionGeneric); software.Confirmation ||
		!software.Authorization {
		t.Fatalf("privileged software requirements = %#v", software)
	}

	currentActionSpec.SelectionMode = "single"
	if software = requirementsForAction(actionGeneric); !software.Selection ||
		software.Confirmation {
		t.Fatalf("privileged selectable software requirements = %#v", software)
	}

	build := requirementsForAction(actionBuild)
	if build.Model != modelThreeRings || !build.Confirmation || build.Preflight ||
		build.Authorization || !build.ProgressBar {
		t.Fatalf("build requirements = %#v", build)
	}
}

func TestGenericActionModelFollowsTheClassifiedRingTier(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previousSpec })

	tests := []struct {
		rings       int
		information bool
		progress    bool
		want        modelRole
	}{
		{1, true, false, modelOneRing},
		{1, false, true, modelOneRing},
		{2, false, true, modelTwoRings},
		{3, false, true, modelThreeRings},
	}
	for _, test := range tests {
		currentActionSpec = actionflow.Spec{
			Rings:       test.rings,
			Information: test.information,
		}
		requirements := requirementsForAction(actionGeneric)
		if got := requirements.Model; got != test.want {
			t.Fatalf("%d-ring task model = %d, want %d", test.rings, got, test.want)
		}
		if got := requirements.ProgressBar; got != test.progress {
			t.Fatalf("%d-ring progress bar = %t", test.rings, got)
		}
	}
}

func TestStartConfirmationFollowsPrivilegeAndMutationSemantics(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previousSpec })

	currentActionSpec = actionflow.Spec{Rings: 1, Information: true}
	if requirementsForAction(actionGeneric).Confirmation {
		t.Fatal("read-only information received a start confirmation")
	}

	currentActionSpec = actionflow.Spec{Rings: 3, RequiresSudo: true}
	if requirementsForAction(actionGeneric).Confirmation {
		t.Fatal("privileged mutation received a confirmation before sudo")
	}

	currentActionSpec = actionflow.Spec{Rings: 3}
	if !requirementsForAction(actionGeneric).Confirmation {
		t.Fatal("unprivileged mutation lost its start confirmation")
	}

	currentActionSpec.SelectionMode = "action"
	if requirementsForAction(actionGeneric).Confirmation {
		t.Fatal("action choice received a duplicate confirmation")
	}
}

func TestOnlyGuardedActionsRequireStopConfirmation(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previousSpec })

	currentActionSpec = actionflow.Spec{Information: true, Operation: "task"}
	if requiresStopConfirmation(actionGeneric) {
		t.Fatal("information action received transaction stop confirmation")
	}
	currentActionSpec = actionflow.Spec{Operation: "install"}
	if !requiresStopConfirmation(actionGeneric) || !canCancelRunningAction(actionGeneric) ||
		!requiresStopConfirmation(actionUpdate) ||
		!requiresStopConfirmation(actionBuild) {
		t.Fatal("guarded action lost its safe stop confirmation")
	}
	for _, operation := range []string{"task", "uninstall"} {
		currentActionSpec = actionflow.Spec{Operation: operation}
		if requiresStopConfirmation(actionGeneric) || canCancelRunningAction(actionGeneric) {
			t.Fatalf("generic %s action retained Stop", operation)
		}
	}
}
