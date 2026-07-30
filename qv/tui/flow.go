package main

type flowRequirements struct {
	Model         modelRole
	Preflight     bool
	Authorization bool
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
		return flowRequirements{
			Model:         modelRoleForRings(currentActionSpec.Rings),
			Preflight:     true,
			Authorization: currentActionSpec.RequiresSudo,
			ProgressBar:   true,
		}
	case actionBuild:
		return flowRequirements{
			Model:       modelThreeRings,
			ProgressBar: true,
		}
	default:
		return flowRequirements{Model: modelCore}
	}
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
