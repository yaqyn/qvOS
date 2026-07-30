package update

import "testing"

func TestProgressFromLineUsesRealUpdateMilestones(t *testing.T) {
	tests := []struct {
		line         string
		status       string
		progress     float64
		wantProgress bool
	}{
		{"Update Omarchy", "updating qvOS source", 0.10, true},
		{"Update Arch signing keys", "updating signing keys", 0.20, true},
		{"Update system packages", "updating system packages", 0.38, true},
		{"Running migration (1780000000)", "running migrations", 0.56, true},
		{"Update AUR packages", "updating AUR packages", 0.68, true},
		{"Remove orphan system packages", "removing package orphans", 0.82, true},
		{"qvOS update is complete.", CompleteStatus, 1.00, true},
		{"downloading linux-6.16.pkg.tar.zst", "", -1, false},
	}

	for _, test := range tests {
		t.Run(test.line, func(t *testing.T) {
			status, progress := ProgressFromLine(test.line)
			if status != test.status {
				t.Fatalf("status = %q, want %q", status, test.status)
			}
			if progress != test.progress {
				t.Fatalf("progress = %f, want %f", progress, test.progress)
			}
			if got := progress >= 0; got != test.wantProgress {
				t.Fatalf("known progress = %t, want %t", got, test.wantProgress)
			}
		})
	}
}

func TestUpdateCopyKeepsCancellationExplicit(t *testing.T) {
	if CancelingStatus != "stopping update" || CanceledStatus != "update stopped" {
		t.Fatalf("cancellation copy = %q / %q", CancelingStatus, CanceledStatus)
	}
	if KeepUpdatingAction != "Keep Updating" || StopUpdateAction != "Stop Update" {
		t.Fatalf("stop confirmation actions = %q / %q", KeepUpdatingAction, StopUpdateAction)
	}
	if StopPromptNotice != "Update keeps running until you confirm" {
		t.Fatalf("stop confirmation notice = %q", StopPromptNotice)
	}
}
