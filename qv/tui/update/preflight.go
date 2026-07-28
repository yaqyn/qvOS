package update

import (
	"errors"
	"os"
	"os/exec"
	"strings"
)

// Preflight delegates to the update adapter's read-only check before the TUI
// requests sudo authorization.
func Preflight(script string) error {
	cmd := exec.Command("/bin/bash", script, "--check")
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}

	message := strings.Join(strings.Fields(string(output)), " ")
	if message != "" {
		return errors.New(message)
	}
	return err
}
