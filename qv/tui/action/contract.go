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
	Rings        int
	Information  bool
	Primary      string
	Active       string
	Complete     string
}

func FromEnvironment() (Spec, error) {
	spec := Spec{
		Slug:      strings.TrimSpace(os.Getenv("QVOS_ACTION_SLUG")),
		Operation: strings.TrimSpace(os.Getenv("QVOS_ACTION_OPERATION")),
		Title:     strings.TrimSpace(os.Getenv("QVOS_ACTION_TITLE")),
		Summary:   strings.TrimSpace(os.Getenv("QVOS_ACTION_SUMMARY")),
		Primary:   strings.TrimSpace(os.Getenv("QVOS_ACTION_PRIMARY")),
		Active:    strings.TrimSpace(os.Getenv("QVOS_ACTION_ACTIVE")),
		Complete:  strings.TrimSpace(os.Getenv("QVOS_ACTION_COMPLETE")),
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
		if spec.Primary == "" || spec.Active == "" || spec.Complete == "" {
			return Spec{}, fmt.Errorf("incomplete qvOS task copy contract")
		}
	default:
		return Spec{}, fmt.Errorf("invalid qvOS action operation")
	}
	return spec, nil
}

func (spec Spec) Heading() string {
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
