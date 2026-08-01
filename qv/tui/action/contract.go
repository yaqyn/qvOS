package action

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const (
	ScriptPath        = "action/run"
	ScriptEnvironment = "QVOS_ACTION_SCRIPT"
	CancelAction      = "Cancel"
)

type Spec struct {
	Slug             string
	Operation        string
	Title            string
	Summary          string
	RequiresSudo     bool
	Rings            int
	Information      bool
	Primary          string
	Active           string
	Complete         string
	NextStep         string
	SelectionMode    string
	SelectionTitle   string
	SelectionEmpty   string
	SummarySelection string
	SelectionSummary string
	SelectionSudo    bool
	ChoiceResolved   bool
	FormProtocol     string
	RollbackProtocol string
	PostActionLabel  string
	PostAction       string
}

func FromEnvironment() (Spec, error) {
	resumePostAction := false
	spec := Spec{
		Slug:      strings.TrimSpace(os.Getenv("QVOS_ACTION_SLUG")),
		Operation: strings.TrimSpace(os.Getenv("QVOS_ACTION_OPERATION")),
		Title:     strings.TrimSpace(os.Getenv("QVOS_ACTION_TITLE")),
		Summary:   strings.TrimSpace(os.Getenv("QVOS_ACTION_SUMMARY")),
		Primary:   strings.TrimSpace(os.Getenv("QVOS_ACTION_PRIMARY")),
		Active:    strings.TrimSpace(os.Getenv("QVOS_ACTION_ACTIVE")),
		Complete:  strings.TrimSpace(os.Getenv("QVOS_ACTION_COMPLETE")),
		NextStep:  strings.TrimSpace(os.Getenv("QVOS_ACTION_NEXT_STEP")),
	}
	if strings.ContainsAny(spec.NextStep, "\r\n") {
		return Spec{}, fmt.Errorf("invalid qvOS action next-step contract")
	}

	switch os.Getenv("QVOS_ACTION_REQUIRES_SUDO") {
	case "0":
	case "1":
		spec.RequiresSudo = true
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action sudo contract")
	}
	if spec.Slug == "" || spec.Title == "" || spec.Summary == "" {
		return Spec{}, fmt.Errorf("incomplete qvOS action contract")
	}
	switch strings.TrimSpace(os.Getenv("QVOS_ACTION_POST_RESUME")) {
	case "":
	case "1":
		resumePostAction = true
	default:
		return Spec{}, fmt.Errorf("invalid qvOS post-success resume contract")
	}
	switch rings := strings.TrimSpace(os.Getenv("QVOS_ACTION_RINGS")); rings {
	case "", "2":
		spec.Rings = 2
	case "1":
		spec.Rings = 1
	case "3":
		spec.Rings = 3
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action ring contract")
	}
	switch strings.TrimSpace(os.Getenv("QVOS_ACTION_BEHAVIOR")) {
	case "information":
		spec.Information = true
	case "mutation":
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action behavior contract")
	}
	if spec.Information && spec.NextStep != "" {
		return Spec{}, fmt.Errorf("information action cannot use next-step guidance")
	}
	spec.SelectionMode = strings.TrimSpace(os.Getenv("QVOS_ACTION_SELECTION_MODE"))
	spec.SelectionTitle = strings.TrimSpace(os.Getenv("QVOS_ACTION_SELECTION_TITLE"))
	spec.SelectionEmpty = strings.TrimSpace(os.Getenv("QVOS_ACTION_SELECTION_EMPTY"))
	spec.SummarySelection = strings.TrimSpace(os.Getenv("QVOS_ACTION_SUMMARY_SELECTION"))
	spec.SelectionSummary = strings.TrimSpace(os.Getenv("QVOS_ACTION_SELECTION_SUMMARY"))
	spec.FormProtocol = strings.TrimSpace(os.Getenv("QVOS_ACTION_FORM"))
	spec.RollbackProtocol = strings.TrimSpace(os.Getenv("QVOS_ACTION_ROLLBACK"))
	spec.PostActionLabel = strings.TrimSpace(os.Getenv("QVOS_ACTION_POST_LABEL"))
	spec.PostAction = strings.TrimSpace(os.Getenv("QVOS_ACTION_POST_SUCCESS"))
	if strings.ContainsAny(spec.SelectionSummary, "\r\n") {
		return Spec{}, fmt.Errorf("invalid qvOS selection summary")
	}
	switch value := strings.TrimSpace(os.Getenv("QVOS_ACTION_SELECTION_REQUIRES_SUDO")); value {
	case "":
	case "0":
	case "1":
		spec.SelectionSudo = true
	default:
		return Spec{}, fmt.Errorf("invalid qvOS selection sudo contract")
	}
	switch spec.FormProtocol {
	case "", "owner-json-v1":
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action form contract")
	}
	switch spec.RollbackProtocol {
	case "", "owner-state-v1":
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action rollback contract")
	}
	if strings.ContainsAny(spec.PostActionLabel, "\r\n") {
		return Spec{}, fmt.Errorf("invalid qvOS post-success action label")
	}
	switch spec.PostAction {
	case "":
		if spec.PostActionLabel != "" {
			return Spec{}, fmt.Errorf("post-success label has no action")
		}
	case "owner-v1":
		if spec.PostActionLabel == "" || spec.Information {
			return Spec{}, fmt.Errorf("incomplete qvOS post-success action")
		}
	default:
		return Spec{}, fmt.Errorf("invalid qvOS post-success action")
	}
	switch spec.SelectionMode {
	case "":
		if spec.SelectionTitle != "" || spec.SelectionEmpty != "" ||
			spec.SummarySelection != "" || spec.SelectionSummary != "" ||
			spec.SelectionSudo {
			return Spec{}, fmt.Errorf("action selection copy has no mode")
		}
	case "single", "multi":
		if spec.SelectionTitle == "" {
			return Spec{}, fmt.Errorf("action selection has no title")
		}
		if spec.SummarySelection != "" || spec.SelectionSummary != "" ||
			spec.SelectionSudo {
			return Spec{}, fmt.Errorf("searchable action selection cannot branch behavior")
		}
	case "action":
		conditionalChoice := spec.SummarySelection != "" ||
			spec.SelectionSummary != "" || spec.SelectionSudo
		if spec.SelectionTitle == "" || spec.Information ||
			conditionalChoice != (spec.SummarySelection != "" &&
				spec.SelectionSummary != "") ||
			(!spec.RequiresSudo && !conditionalChoice) {
			return Spec{}, fmt.Errorf("incomplete qvOS action-choice contract")
		}
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action selection mode")
	}
	switch spec.Operation {
	case "install":
		if spec.Information {
			return Spec{}, fmt.Errorf("software action cannot use information behavior")
		}
		spec.Primary = "Install"
		spec.Active = "Installing"
		spec.Complete = "Installed"
	case "uninstall":
		if spec.Information {
			return Spec{}, fmt.Errorf("software action cannot use information behavior")
		}
		spec.Primary = "Uninstall"
		spec.Active = "Uninstalling"
		spec.Complete = "Uninstalled"
	case "task":
		if spec.Information {
			if spec.Primary != "" || spec.Active != "" || spec.Complete != "" {
				return Spec{}, fmt.Errorf("information action cannot use transaction copy")
			}
		} else if spec.Primary == "" || spec.Active == "" || spec.Complete == "" {
			return Spec{}, fmt.Errorf("incomplete qvOS task copy contract")
		}
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action operation")
	}
	if spec.RollbackProtocol != "" && spec.Operation != "install" {
		return Spec{}, fmt.Errorf("only install actions can declare rollback")
	}
	if spec.PostAction != "" && spec.Operation != "install" {
		return Spec{}, fmt.Errorf("only install actions can declare post-success behavior")
	}
	if resumePostAction {
		return spec.ForPostAction()
	}
	return spec, nil
}

func (spec Spec) HasSelection() bool {
	return spec.SelectionMode == "single" || spec.SelectionMode == "multi" ||
		spec.SelectionMode == "action"
}

func (spec Spec) HasForm() bool {
	return spec.FormProtocol == "owner-json-v1"
}

func (spec Spec) HasPostAction() bool {
	return spec.PostAction == "owner-v1"
}

func (spec Spec) ForPostAction() (Spec, error) {
	if !spec.HasPostAction() {
		return Spec{}, fmt.Errorf("action has no post-success contract")
	}
	switch spec.PostActionLabel {
	case "launch":
		spec.Summary = "Download Windows and start the VM"
		spec.Primary = "Launch"
		spec.Active = "Launching"
		spec.Complete = "Launched"
	default:
		return Spec{}, fmt.Errorf("unsupported post-success action: %s", spec.PostActionLabel)
	}
	spec.SelectionMode = ""
	spec.SelectionTitle = ""
	spec.SelectionEmpty = ""
	spec.SummarySelection = ""
	spec.SelectionSummary = ""
	spec.SelectionSudo = false
	spec.ChoiceResolved = false
	spec.FormProtocol = ""
	spec.PostActionLabel = ""
	spec.PostAction = ""
	spec.NextStep = ""
	return spec, nil
}

func (spec Spec) AllowsMultipleSelections() bool {
	return spec.SelectionMode == "multi"
}

func (spec Spec) IsActionSelection() bool {
	return spec.SelectionMode == "action"
}

func (spec Spec) ForSelection(choice string) Spec {
	if !spec.IsActionSelection() {
		return spec
	}
	conditional := choice == spec.SummarySelection
	baseRequiresSudo := spec.RequiresSudo
	spec.ChoiceResolved = true
	spec.SelectionMode = ""
	spec.SelectionTitle = ""
	spec.SelectionEmpty = ""
	spec.SummarySelection = ""
	if conditional {
		spec.Summary = spec.SelectionSummary
		spec.RequiresSudo = baseRequiresSudo || spec.SelectionSudo
		if spec.Operation == "task" && !baseRequiresSudo && spec.SelectionSudo {
			spec.Operation = "uninstall"
			spec.Primary = ""
			spec.Active = ""
			spec.Complete = ""
		}
		spec.RollbackProtocol = ""
	}
	spec.SelectionSummary = ""
	spec.SelectionSudo = false
	return spec
}

func (spec Spec) Heading() string {
	if spec.IsActionSelection() {
		return strings.ToUpper("Manage " + spec.Title)
	}
	return strings.ToUpper(spec.PrimaryAction() + " " + spec.Title)
}

func (spec Spec) PrimaryAction() string {
	if spec.Primary != "" {
		return spec.Primary
	}
	return titleCase(spec.Operation)
}

func (spec Spec) ActiveTitle() string {
	if spec.Active != "" {
		return strings.ToUpper(spec.Active)
	}
	if spec.Operation == "install" {
		return "INSTALLING"
	}
	return "UNINSTALLING"
}

func (spec Spec) PastTense() string {
	if spec.Complete != "" {
		return strings.ToUpper(spec.Complete)
	}
	if spec.Operation == "install" {
		return "INSTALLED"
	}
	return "UNINSTALLED"
}

func (spec Spec) RunningStatus() string {
	return strings.ToLower(spec.activeCopy()) + " " + spec.Title
}

func (spec Spec) CompleteStatus() string {
	return spec.Title + " " + strings.ToLower(spec.completeCopy())
}

func (spec Spec) CancelingStatus() string {
	return "stopping " + strings.ToLower(spec.PrimaryAction())
}

func (spec Spec) CanceledStatus() string {
	return strings.ToLower(spec.PrimaryAction()) + " stopped"
}

func (spec Spec) StopPromptTitle() string {
	return "STOP " + strings.ToUpper(spec.PrimaryAction()) + "?"
}

func (spec Spec) StopPromptNotice() string {
	return spec.Title + " keeps running until you confirm"
}

func (spec Spec) KeepRunningAction() string {
	return "Keep " + spec.activeCopy()
}

func (spec Spec) StopAction() string {
	return "Stop " + spec.PrimaryAction()
}

func ProgressFromLine(line string, spec Spec) (string, float64) {
	switch strings.TrimSpace(line) {
	case "qvOS action: preparing":
		return "preparing " + spec.Title, 0.08
	case "qvOS action: applying":
		return spec.RunningStatus(), 0.18
	case "qvOS action: verifying":
		return "verifying " + spec.Title, 0.88
	case "qvOS action: complete":
		return spec.CompleteStatus(), 1
	default:
		return "", -1
	}
}

func IsProtocolLine(line string) bool {
	switch strings.TrimSpace(line) {
	case "qvOS action: preparing",
		"qvOS action: applying",
		"qvOS action: verifying",
		"qvOS action: complete":
		return true
	default:
		return false
	}
}

func Preflight(script string) error {
	cmd := exec.Command("/bin/bash", script, "--check")
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}
	message := strings.Join(strings.Fields(string(output)), " ")
	if message == "" {
		message = err.Error()
	}
	return fmt.Errorf("%s", message)
}

func titleCase(value string) string {
	if value == "" {
		return ""
	}
	return strings.ToUpper(value[:1]) + value[1:]
}

func (spec Spec) activeCopy() string {
	if spec.Active != "" {
		return spec.Active
	}
	if spec.Operation == "install" {
		return "Installing"
	}
	return "Uninstalling"
}

func (spec Spec) completeCopy() string {
	if spec.Complete != "" {
		return spec.Complete
	}
	if spec.Operation == "install" {
		return "Installed"
	}
	return "Uninstalled"
}
