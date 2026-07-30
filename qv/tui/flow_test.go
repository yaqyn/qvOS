package main

import "testing"

func TestFlowRequirementsCentralizeDomainCapabilities(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() {
		currentActionSpec = previousSpec
	})

	update := requirementsForAction(actionUpdate)
	if update.Model != modelThreeRings || !update.Preflight ||
		!update.Authorization || !update.ProgressBar {
		t.Fatalf("update requirements = %#v", update)
	}

	currentActionSpec.RequiresSudo = false
	software := requirementsForAction(actionGeneric)
	if software.Model != modelTwoRings || !software.Preflight ||
		software.Authorization || !software.ProgressBar {
		t.Fatalf("unprivileged software requirements = %#v", software)
	}

	currentActionSpec.RequiresSudo = true
	if software = requirementsForAction(actionGeneric); !software.Authorization {
		t.Fatalf("privileged software requirements = %#v", software)
	}

	build := requirementsForAction(actionBuild)
	if build.Model != modelThreeRings || build.Preflight ||
		build.Authorization || !build.ProgressBar {
		t.Fatalf("build requirements = %#v", build)
	}
}

func TestGenericActionModelFollowsTheClassifiedRingTier(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previousSpec })

	tests := []struct {
		rings int
		want  modelRole
	}{
		{1, modelOneRing},
		{2, modelTwoRings},
		{3, modelThreeRings},
	}
	for _, test := range tests {
		currentActionSpec.Rings = test.rings
		requirements := requirementsForAction(actionGeneric)
		if got := requirements.Model; got != test.want {
			t.Fatalf("%d-ring task model = %d, want %d", test.rings, got, test.want)
		}
		if got := requirements.ProgressBar; got != (test.rings != 1) {
			t.Fatalf("%d-ring progress bar = %t", test.rings, got)
		}
	}
}

func TestOnlyGuardedActionsRequireStopConfirmation(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previousSpec })

	currentActionSpec.Rings = 1
	if requiresStopConfirmation(actionGeneric) {
		t.Fatal("one-ring information action received transaction stop confirmation")
	}
	currentActionSpec.Rings = 2
	if !requiresStopConfirmation(actionGeneric) ||
		!requiresStopConfirmation(actionUpdate) {
		t.Fatal("guarded action lost its safe stop confirmation")
	}
}
