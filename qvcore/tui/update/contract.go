package update

import "strings"

const (
	Summary            = "Update qvOS and system packages"
	StopPromptTitle    = "STOP UPDATE?"
	StopPromptNotice   = "Update keeps running until you confirm"
	KeepUpdatingAction = "Keep Updating"
	StopUpdateAction   = "Stop Update"
	ScriptPath         = "update/run"
	ScriptEnvironment  = "QVOS_UPDATE_SCRIPT"
	RunningStatus      = "updating qvOS"
	CancelingStatus    = "stopping update"
	CanceledStatus     = "update stopped"
	CompleteStatus     = "update complete"
)

type stage struct {
	token    string
	status   string
	progress float64
}

var stages = []stage{
	{"Update qvOS", "updating qvOS source", 0.10},
	{"Update Arch signing keys", "updating signing keys", 0.20},
	{"Update system packages", "updating system packages", 0.38},
	{"Running migration (", "running migrations", 0.56},
	{"Update AUR packages", "updating AUR packages", 0.68},
	{"Remove orphan system packages", "removing package orphans", 0.82},
	{"qvOS update is complete.", CompleteStatus, 1.00},
}

// ProgressFromLine maps known owner milestones to stage-based progress.
// Unknown output belongs in the log and must not replace the active stage.
func ProgressFromLine(line string) (string, float64) {
	line = strings.TrimSpace(line)
	for _, stage := range stages {
		if strings.HasPrefix(line, stage.token) {
			return stage.status, stage.progress
		}
	}
	return "", -1
}
