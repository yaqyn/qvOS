package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestCanceledMiseProcessRestoresItsCreatedRuntimeAndConfig(t *testing.T) {
	previousReshim := reshimMise
	t.Cleanup(func() {
		reshimMise = previousReshim
	})

	home := t.TempDir()
	dataDir := filepath.Join(home, ".local", "share", "mise")
	configPath := filepath.Join(home, ".config", "mise", "config.toml")
	t.Setenv("HOME", home)
	t.Setenv("MISE_DATA_DIR", dataDir)
	t.Setenv("MISE_GLOBAL_CONFIG_FILE", configPath)
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	reshimMise = func() error { return nil }

	createdInstall := filepath.Join(dataDir, "installs", "elixir", "1.20.2-otp-29")
	createdDownload := filepath.Join(dataDir, "downloads", "elixir", "1.20.2-otp-29")
	t.Setenv("QVOS_TEST_MISE_INSTALL", createdInstall)
	t.Setenv("QVOS_TEST_MISE_DOWNLOAD", createdDownload)
	t.Setenv("QVOS_TEST_MISE_CONFIG", configPath)
	script := filepath.Join(t.TempDir(), "install-mise-fixture")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
set -e
case ${1:-} in
--cancel-status)
  printf 'target-not-detected\n'
  exit
  ;;
esac
mkdir -p "$QVOS_TEST_MISE_INSTALL" "$QVOS_TEST_MISE_DOWNLOAD" "$(dirname "$QVOS_TEST_MISE_CONFIG")"
printf 'partial\n' >"$QVOS_TEST_MISE_DOWNLOAD/runtime.zip.partial"
printf '[tools]\nelixir = "latest"\n' >"$QVOS_TEST_MISE_CONFIG"
bash -c 'exec -a mise sleep 30' &
echo ready
wait
`), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan scriptEvent, 32)
	go runRootScriptStream(ctx, actionGeneric, script, nil, "", events)

	cleanup := cancelCleanupNone
	for event := range events {
		if event.line == "ready" {
			cancel()
		}
		if event.done {
			if !errors.Is(event.err, errScriptCanceled) {
				t.Fatalf("mise cancellation error = %v", event.err)
			}
			cleanup = event.cancelCleanup
		}
	}
	if !cleanup.includes(cancelCleanupMiseRestored) ||
		cleanup.includes(cancelCleanupMiseRetained) {
		t.Fatalf("mise process cleanup = %v", cleanup)
	}
	for _, path := range []string{createdInstall, createdDownload, configPath} {
		if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("canceled mise state remains: %s (%v)", path, err)
		}
	}
	for _, path := range []string{dataDir, filepath.Dir(configPath)} {
		if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("canceled mise left an empty root: %s (%v)", path, err)
		}
	}
}

func TestStopCanRollbackMiseAfterTheOwnerAlreadyCompleted(t *testing.T) {
	previousReshim := reshimMise
	t.Cleanup(func() {
		reshimMise = previousReshim
	})

	home := t.TempDir()
	dataDir := filepath.Join(home, ".local", "share", "mise")
	configPath := filepath.Join(home, ".config", "mise", "config.toml")
	createdInstall := filepath.Join(dataDir, "installs", "elixir", "1.20.2-otp-29")
	t.Setenv("HOME", home)
	t.Setenv("MISE_DATA_DIR", dataDir)
	t.Setenv("MISE_GLOBAL_CONFIG_FILE", configPath)
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("QVOS_ACTION_OPERATION", "install")
	t.Setenv("QVOS_TEST_MISE_INSTALL", createdInstall)
	t.Setenv("QVOS_TEST_MISE_CONFIG", configPath)
	reshimMise = func() error { return nil }

	script := filepath.Join(t.TempDir(), "completed-mise-fixture")
	if err := os.WriteFile(script, []byte(`#!/bin/bash
set -e
case ${1:-} in
--cancel-status)
  if [[ -d $QVOS_TEST_MISE_INSTALL ]]; then
    printf 'target-reached\n'
  else
    printf 'target-not-detected\n'
  fi
  exit
  ;;
esac
mkdir -p "$QVOS_TEST_MISE_INSTALL" "$(dirname "$QVOS_TEST_MISE_CONFIG")"
printf '[tools]\nelixir = "latest"\n' >"$QVOS_TEST_MISE_CONFIG"
bash -c 'exec -a mise sleep 0.2'
`), 0o755); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(context.Background(), actionGeneric, script, nil, "", events)
	var completed scriptEvent
	for event := range events {
		if event.done {
			completed = event
		}
	}
	if completed.err != nil || completed.rollback == nil {
		t.Fatalf("completed mise result has no rollback: err=%v", completed.err)
	}
	if _, err := os.Stat(createdInstall); err != nil {
		t.Fatalf("completed fixture did not install its runtime: %v", err)
	}

	cleanup, probe := completed.rollback()
	if !cleanup.includes(cancelCleanupMiseRestored) ||
		cleanup.includes(cancelCleanupMiseRetained) ||
		probe != cancelProbeTargetNotDetected {
		t.Fatalf("completed mise rollback = cleanup %v, probe %v", cleanup, probe)
	}
	for _, path := range []string{createdInstall, configPath} {
		if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("completed mise state remains after Stop: %s (%v)", path, err)
		}
	}
}

func TestCanceledMiseActionRestoresPreActionState(t *testing.T) {
	previousStatus := miseProcessStatus
	previousRemove := removeMisePaths
	previousRestore := restoreMiseFile
	previousReshim := reshimMise
	t.Cleanup(func() {
		miseProcessStatus = previousStatus
		removeMisePaths = previousRemove
		restoreMiseFile = previousRestore
		reshimMise = previousReshim
	})

	dataDir := filepath.Join(t.TempDir(), "mise-data")
	configPath := filepath.Join(t.TempDir(), "mise-config", "config.toml")
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("MISE_DATA_DIR", dataDir)
	t.Setenv("MISE_GLOBAL_CONFIG_FILE", configPath)
	miseProcessStatus = func() (bool, bool) { return false, true }
	removeMisePaths = removeManagedPaths
	restoreMiseFile = restoreManagedFile
	reshimCalls := 0
	reshimMise = func() error {
		reshimCalls++
		return nil
	}

	preexistingInstall := filepath.Join(dataDir, "installs", "node", "24.0.0")
	preexistingDownload := filepath.Join(dataDir, "downloads", "node", "24.0.0")
	for _, path := range []string{preexistingInstall, preexistingDownload, filepath.Dir(configPath)} {
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(configPath, []byte("[tools]\nnode = \"lts\"\n"), 0o640); err != nil {
		t.Fatal(err)
	}
	snapshot := snapshotMiseState()
	if !snapshot.reliable {
		t.Fatal("mise pre-action state was not reliable")
	}

	newInstall := filepath.Join(dataDir, "installs", "erlang", "29.0.4")
	newDownload := filepath.Join(dataDir, "downloads", "elixir", "1.20.2-otp-29")
	partialInExistingVersion := filepath.Join(preexistingDownload, "node.tar.gz.partial")
	newMixArchive := filepath.Join(home, ".mix", "archives", "phx_new-1.8.0", "ebin")
	newHexRoot := filepath.Join(home, ".hex")
	for _, path := range []string{newInstall, newDownload, newMixArchive, newHexRoot} {
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for path, contents := range map[string]string{
		filepath.Join(newDownload, "elixir.zipABC123"):       "partial",
		partialInExistingVersion:                             "partial",
		filepath.Join(newMixArchive, "phx_new.beam"):         "archive",
		filepath.Join(newHexRoot, "cache.ets"):               "hex state",
		configPath:                                           "[tools]\nnode = \"lts\"\nerlang = \"latest\"\n",
		filepath.Join(filepath.Dir(configPath), "mise.lock"): "generated lock",
	} {
		if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	cleanup := cleanupCanceledMise(snapshot, managerEvidence{owned: true, reliable: true})
	if !cleanup.includes(cancelCleanupMiseRestored) ||
		cleanup.includes(cancelCleanupMiseRetained) {
		t.Fatalf("mise cleanup = %v", cleanup)
	}
	for _, path := range []string{
		newInstall,
		newDownload,
		partialInExistingVersion,
		filepath.Join(home, ".mix"),
		filepath.Join(home, ".hex"),
	} {
		if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("new mise path remains after Stop: %s (%v)", path, err)
		}
	}
	for _, path := range []string{preexistingInstall, preexistingDownload} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("pre-existing mise path was removed: %s (%v)", path, err)
		}
	}
	config, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(config) != "[tools]\nnode = \"lts\"\n" {
		t.Fatalf("mise config was not restored: %q", config)
	}
	if mode := fileMode(t, configPath); mode != 0o640 {
		t.Fatalf("restored mise config mode = %o", mode)
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(configPath), "mise.lock")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("new mise lock remains: %v", err)
	}
	if reshimCalls != 1 {
		t.Fatalf("mise reshim calls = %d, want 1", reshimCalls)
	}
}

func TestCanceledMiseActionPreservesUnownedOrActiveChanges(t *testing.T) {
	previousStatus := miseProcessStatus
	previousReshim := reshimMise
	t.Cleanup(func() {
		miseProcessStatus = previousStatus
		reshimMise = previousReshim
	})

	dataDir := filepath.Join(t.TempDir(), "mise-data")
	configPath := filepath.Join(t.TempDir(), "mise-config", "config.toml")
	t.Setenv("HOME", t.TempDir())
	t.Setenv("MISE_DATA_DIR", dataDir)
	t.Setenv("MISE_GLOBAL_CONFIG_FILE", configPath)
	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configPath, []byte("[tools]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	reshimMise = func() error {
		t.Fatal("retained mise state must not be reshimmed")
		return nil
	}

	for _, test := range []struct {
		name   string
		owned  bool
		active bool
	}{
		{"unowned", false, false},
		{"active", true, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			snapshot := snapshotMiseState()
			created := filepath.Join(dataDir, "installs", test.name, "1.0.0")
			if err := os.MkdirAll(created, 0o755); err != nil {
				t.Fatal(err)
			}
			miseProcessStatus = func() (bool, bool) { return test.active, true }
			cleanup := cleanupCanceledMise(snapshot, managerEvidence{
				owned:    test.owned,
				reliable: true,
			})
			if !cleanup.includes(cancelCleanupMiseRetained) ||
				cleanup.includes(cancelCleanupMiseRestored) {
				t.Fatalf("retained mise cleanup = %v", cleanup)
			}
			if _, err := os.Stat(created); err != nil {
				t.Fatalf("unverified mise path was removed: %v", err)
			}
		})
	}
}

func TestCanceledMiseActionReportsModifiedPreexistingRuntime(t *testing.T) {
	previousStatus := miseProcessStatus
	previousReshim := reshimMise
	t.Cleanup(func() {
		miseProcessStatus = previousStatus
		reshimMise = previousReshim
	})

	home := t.TempDir()
	dataDir := filepath.Join(home, ".local", "share", "mise")
	configPath := filepath.Join(home, ".config", "mise", "config.toml")
	runtimeDir := filepath.Join(dataDir, "installs", "elixir", "1.20.2")
	runtimeFile := filepath.Join(runtimeDir, "bin", "elixir")
	t.Setenv("HOME", home)
	t.Setenv("MISE_DATA_DIR", dataDir)
	t.Setenv("MISE_GLOBAL_CONFIG_FILE", configPath)
	if err := os.MkdirAll(filepath.Dir(runtimeFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(runtimeFile, []byte("before"), 0o700); err != nil {
		t.Fatal(err)
	}
	snapshot := snapshotMiseState()
	if err := os.WriteFile(filepath.Join(runtimeDir, "partial"), []byte("new"), 0o600); err != nil {
		t.Fatal(err)
	}
	miseProcessStatus = func() (bool, bool) { return false, true }
	reshimMise = func() error {
		t.Fatal("retained runtime must not be reshimmed")
		return nil
	}

	cleanup := cleanupCanceledMise(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupMiseRetained {
		t.Fatalf("modified runtime cleanup = %v", cleanup)
	}
	if _, err := os.Stat(filepath.Join(runtimeDir, "partial")); err != nil {
		t.Fatalf("pre-existing runtime contents were removed: %v", err)
	}
}

func TestRestoreMiseFileRefusesAReplacedSymlink(t *testing.T) {
	configDir := t.TempDir()
	configPath := filepath.Join(configDir, "config.toml")
	if err := os.WriteFile(configPath, []byte("before"), 0o600); err != nil {
		t.Fatal(err)
	}
	snapshot := snapshotManagedFile(configPath)
	if err := os.Remove(configPath); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(t.TempDir(), "target")
	if err := os.WriteFile(target, []byte("do not replace"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, configPath); err != nil {
		t.Fatal(err)
	}

	if err := restoreManagedFile(configPath, snapshot); err == nil {
		t.Fatal("mise restore replaced an unexpected symlink")
	}
	data, err := os.ReadFile(target)
	if err != nil || string(data) != "do not replace" {
		t.Fatalf("symlink target changed: %q, %v", data, err)
	}
}

func TestCanceledMiseActionRemovesNewEmptyRuntimeRoots(t *testing.T) {
	previousStatus := miseProcessStatus
	previousReshim := reshimMise
	t.Cleanup(func() {
		miseProcessStatus = previousStatus
		reshimMise = previousReshim
	})

	home := t.TempDir()
	dataDir := filepath.Join(home, ".local", "share", "mise")
	configPath := filepath.Join(home, ".config", "mise", "config.toml")
	t.Setenv("HOME", home)
	t.Setenv("MISE_DATA_DIR", dataDir)
	t.Setenv("MISE_GLOBAL_CONFIG_FILE", configPath)
	snapshot := snapshotMiseState()
	if err := os.MkdirAll(filepath.Join(dataDir, "installs"), 0o755); err != nil {
		t.Fatal(err)
	}
	miseProcessStatus = func() (bool, bool) { return false, true }
	reshimMise = func() error { return nil }

	cleanup := cleanupCanceledMise(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupMiseRestored {
		t.Fatalf("empty mise root cleanup = %v", cleanup)
	}
	if _, err := os.Lstat(dataDir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("new empty mise data root remains: %v", err)
	}
}

func fileMode(t *testing.T, path string) os.FileMode {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	return info.Mode().Perm()
}
