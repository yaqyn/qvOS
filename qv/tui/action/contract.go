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
	Slug         string
	Operation    string
	Title        string
	Summary      string
	RequiresSudo bool
}

func FromEnvironment() (Spec, error) {
	spec := Spec{
		Slug:      strings.TrimSpace(os.Getenv("QVOS_ACTION_SLUG")),
		Operation: strings.TrimSpace(os.Getenv("QVOS_ACTION_OPERATION")),
		Title:     strings.TrimSpace(os.Getenv("QVOS_ACTION_TITLE")),
		Summary:   strings.TrimSpace(os.Getenv("QVOS_ACTION_SUMMARY")),
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
	if spec.Operation != "install" && spec.Operation != "uninstall" {
		return Spec{}, fmt.Errorf("invalid qvOS action operation")
	}
	return spec, nil
}

func (spec Spec) Heading() string {
	return strings.ToUpper(spec.Operation + " " + spec.Title)
}

func (spec Spec) PrimaryAction() string {
	return titleCase(spec.Operation)
}

func (spec Spec) ActiveTitle() string {
	if spec.Operation == "install" {
		return "INSTALLING"
	}
	return "UNINSTALLING"
}

func (spec Spec) PastTense() string {
	if spec.Operation == "install" {
		return "INSTALLED"
	}
	return "UNINSTALLED"
}

func (spec Spec) RunningStatus() string {
	return spec.Operation + "ing " + spec.Title
}

func (spec Spec) CompleteStatus() string {
	return spec.Title + " " + spec.PastTense()
}

func (spec Spec) CancelingStatus() string {
	return "stopping " + spec.Operation
}

func (spec Spec) CanceledStatus() string {
	return spec.Operation + " stopped"
}

func (spec Spec) StopPromptTitle() string {
	return "STOP " + strings.ToUpper(spec.Operation) + "?"
}

func (spec Spec) StopPromptNotice() string {
	return spec.Title + " keeps running until you confirm"
}

func (spec Spec) KeepRunningAction() string {
	return "Keep " + titleCase(spec.Operation) + "ing"
}

func (spec Spec) StopAction() string {
	return "Stop " + titleCase(spec.Operation)
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
