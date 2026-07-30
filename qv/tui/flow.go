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
			Model:         modelTwoRings,
			Preflight:     true,
			Authorization: currentActionSpec.RequiresSudo,
			ProgressBar:   true,
		}
	case actionBuild:
		return flowRequirements{
			Model:       modelTwoRings,
			ProgressBar: true,
		}
	default:
		return flowRequirements{Model: modelCore}
	}
}
