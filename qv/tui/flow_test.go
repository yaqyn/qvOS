package main

import "testing"

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
	if software.Model != modelTwoRings || !software.Preflight ||
		!software.Confirmation || software.Authorization || !software.ProgressBar {
		t.Fatalf("unprivileged software requirements = %#v", software)
	}

	currentActionSpec.RequiresSudo = true
	if software = requirementsForAction(actionGeneric); software.Confirmation ||
		!software.Authorization {
		t.Fatalf("privileged software requirements = %#v", software)
	}

	build := requirementsForAction(actionBuild)
	if build.Model != modelThreeRings || build.Confirmation || build.Preflight ||
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

func TestStartConfirmationExistsOnlyWithoutInformationOrSudoGate(t *testing.T) {
	previousSpec := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previousSpec })

	tests := []struct {
		name         string
		rings        int
		requiresSudo bool
		want         bool
	}{
		{"one-ring information", 1, false, false},
		{"one-ring privileged information", 1, true, false},
		{"two-ring unprivileged transaction", 2, false, true},
		{"two-ring privileged transaction", 2, true, false},
		{"three-ring unprivileged transaction", 3, false, true},
		{"three-ring privileged transaction", 3, true, false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			currentActionSpec.Rings = test.rings
			currentActionSpec.RequiresSudo = test.requiresSudo
			if got := requirementsForAction(actionGeneric).Confirmation; got != test.want {
				t.Fatalf(
					"confirmation = %t, want %t for rings=%d sudo=%t",
					got,
					test.want,
					test.rings,
					test.requiresSudo,
				)
			}
		})
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
