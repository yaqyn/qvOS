package main

type flowRequirements struct {
	Model         modelRole
	Confirmation  bool
	Preflight     bool
	Authorization bool
	Selection     bool
	Form          bool
	ProgressBar   bool
}

func requirementsForAction(action actionMode) flowRequirements {
	switch action {
	case actionUpdate:
		return flowRequirements{
			Model:         modelThreeRings,
			Preflight:     true,
			Authorization: true,
			ProgressBar:   true,
		}
	case actionGeneric:
		transaction := !currentActionSpec.Information
		return flowRequirements{
			Model: modelRoleForRings(currentActionSpec.Rings),
			Confirmation: transaction && !currentActionSpec.RequiresSudo &&
				!currentActionSpec.IsActionSelection() && !currentActionSpec.ChoiceResolved,
			Preflight:     true,
			Authorization: currentActionSpec.RequiresSudo,
			Selection:     currentActionSpec.HasSelection(),
			Form:          currentActionSpec.HasForm(),
			ProgressBar:   transaction,
		}
	case actionBuild:
		return flowRequirements{
			Model:        modelThreeRings,
			Confirmation: true,
			ProgressBar:  true,
		}
	default:
		return flowRequirements{Model: modelCore}
	}
}

func isInformationAction(action actionMode) bool {
	return action == actionGeneric && currentActionSpec.Information
}

func requiresStopConfirmation(action actionMode) bool {
	return action == actionUpdate || action == actionBuild ||
		(action == actionGeneric && currentActionSpec.Operation == "install")
}

func canCancelRunningAction(action actionMode) bool {
	if action == actionGeneric {
		return currentActionSpec.Information ||
			currentActionSpec.Operation == "install"
	}
	return action == actionUpdate || action == actionBuild
}

func modelRoleForRings(rings int) modelRole {
	switch rings {
	case 1:
		return modelOneRing
	case 3:
		return modelThreeRings
	default:
		return modelTwoRings
	}
}
