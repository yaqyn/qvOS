package update

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPreflightUsesTheReadOnlyAdapterMode(t *testing.T) {
	script := filepath.Join(t.TempDir(), "update")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
[[ ${1:-} == "--check" ]] || exit 9
`), 0o755); err != nil {
		t.Fatal(err)
	}

	if err := Preflight(script); err != nil {
		t.Fatalf("preflight failed: %v", err)
	}
}

func TestPreflightPreservesActionableFailureText(t *testing.T) {
	script := filepath.Join(t.TempDir(), "update")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
echo "qvOS update requires branch OS" >&2
exit 1
`), 0o755); err != nil {
		t.Fatal(err)
	}

	err := Preflight(script)
	if err == nil || err.Error() != "qvOS update requires branch OS" {
		t.Fatalf("preflight error = %v", err)
	}
}
