package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCanceledInstallRemovesOnlyPackagesAddedByItsPacmanTransaction(t *testing.T) {
	previousInventory := pacmanPackageInventory
	previousRemove := removePacmanPackages
	previousStatus := packageManagerStatus
	t.Cleanup(func() {
		pacmanPackageInventory = previousInventory
		removePacmanPackages = previousRemove
		packageManagerStatus = previousStatus
	})

	installed := map[string]string{
		"base":        "1.0-1",
		"preexisting": "2.0-1",
	}
	pacmanPackageInventory = func() (map[string]string, bool) {
		copy := make(map[string]string, len(installed))
		for name, version := range installed {
			copy[name] = version
		}
		return copy, true
	}
	packageManagerStatus = func() (bool, bool) { return false, true }
	removed := make([]string, 0, 2)
	removePacmanPackages = func(packages []string) error {
		removed = append(removed, packages...)
		for _, name := range packages {
			delete(installed, name)
		}
		return nil
	}

	snapshot := snapshotPacmanPackages()
	installed["dependency"] = "1.0-1"
	installed["target"] = "1.0-1"
	cleanup := cleanupCanceledPacmanPackages(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupPacmanPackagesRemoved {
		t.Fatalf("package rollback = %v", cleanup)
	}
	if len(removed) != 2 || removed[0] != "dependency" || removed[1] != "target" {
		t.Fatalf("removed packages = %q", removed)
	}
	for _, name := range []string{"base", "preexisting"} {
		if _, remains := installed[name]; !remains {
			t.Fatalf("pre-existing package was removed: %s", name)
		}
	}
}

func TestCanceledInstallRetainsUnownedOrActivePackageChanges(t *testing.T) {
	previousInventory := pacmanPackageInventory
	previousRemove := removePacmanPackages
	previousStatus := packageManagerStatus
	t.Cleanup(func() {
		pacmanPackageInventory = previousInventory
		removePacmanPackages = previousRemove
		packageManagerStatus = previousStatus
	})

	installed := map[string]string{"base": "1.0-1"}
	pacmanPackageInventory = func() (map[string]string, bool) {
		copy := make(map[string]string, len(installed))
		for name, version := range installed {
			copy[name] = version
		}
		return copy, true
	}
	removePacmanPackages = func([]string) error {
		t.Fatal("unverified packages must not be removed")
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
			snapshot := snapshotPacmanPackages()
			installed[test.name] = "1.0-1"
			packageManagerStatus = func() (bool, bool) { return test.active, true }
			cleanup := cleanupCanceledPacmanPackages(snapshot, managerEvidence{
				owned:    test.owned,
				reliable: true,
			})
			if cleanup != cancelCleanupPacmanPackagesRetained {
				t.Fatalf("retained package rollback = %v", cleanup)
			}
			if _, remains := installed[test.name]; !remains {
				t.Fatalf("unverified package was removed: %s", test.name)
			}
		})
	}
}

func TestCanceledInstallRemovesOnlyCacheEntriesCreatedByItsPacmanTransaction(t *testing.T) {
	previousUID := pacmanDBLockOwnerUID
	previousDirectories := pacmanCacheDirectories
	previousRemove := removePacmanCacheFiles
	previousStatus := packageManagerStatus
	t.Cleanup(func() {
		pacmanDBLockOwnerUID = previousUID
		pacmanCacheDirectories = previousDirectories
		removePacmanCacheFiles = previousRemove
		packageManagerStatus = previousStatus
	})

	cacheDir := t.TempDir()
	pacmanDBLockOwnerUID = uint32(os.Getuid())
	pacmanCacheDirectories = func() ([]string, bool) {
		return []string{cacheDir}, true
	}
	packageManagerStatus = func() (bool, bool) { return false, true }
	removePacmanCacheFiles = func(paths []string) error {
		for _, path := range paths {
			if err := os.Remove(path); err != nil {
				return err
			}
		}
		return nil
	}

	preexisting := filepath.Join(cacheDir, "preexisting.pkg.tar.zst")
	if err := os.WriteFile(preexisting, []byte("cached"), 0o600); err != nil {
		t.Fatal(err)
	}
	snapshot := snapshotPacmanCache()
	created := []string{
		filepath.Join(cacheDir, "target.pkg.tar.zst"),
		filepath.Join(cacheDir, "target.pkg.tar.zst.sig"),
		filepath.Join(cacheDir, "target.pkg.tar.zst.part"),
	}
	for _, path := range created {
		if err := os.WriteFile(path, []byte("created"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	cleanup := cleanupCanceledPacmanCache(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupPacmanCacheRemoved {
		t.Fatalf("package cache rollback = %v", cleanup)
	}
	for _, path := range created {
		if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("new cache entry remains: %s (%v)", path, err)
		}
	}
	if _, err := os.Stat(preexisting); err != nil {
		t.Fatalf("pre-existing cache entry was removed: %v", err)
	}
}

func TestCanceledInstallReportsModifiedPreexistingPackageCache(t *testing.T) {
	previousUID := pacmanDBLockOwnerUID
	previousDirectories := pacmanCacheDirectories
	previousStatus := packageManagerStatus
	t.Cleanup(func() {
		pacmanDBLockOwnerUID = previousUID
		pacmanCacheDirectories = previousDirectories
		packageManagerStatus = previousStatus
	})

	cacheDir := t.TempDir()
	pacmanDBLockOwnerUID = uint32(os.Getuid())
	pacmanCacheDirectories = func() ([]string, bool) { return []string{cacheDir}, true }
	packageManagerStatus = func() (bool, bool) { return false, true }
	partial := filepath.Join(cacheDir, "preexisting.pkg.tar.zst.part")
	if err := os.WriteFile(partial, []byte("before"), 0o600); err != nil {
		t.Fatal(err)
	}
	snapshot := snapshotPacmanCache()
	if err := os.WriteFile(partial, []byte("continued download"), 0o600); err != nil {
		t.Fatal(err)
	}

	cleanup := cleanupCanceledPacmanCache(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupPacmanCacheRetained {
		t.Fatalf("modified cache cleanup = %v", cleanup)
	}
	data, err := os.ReadFile(partial)
	if err != nil || string(data) != "continued download" {
		t.Fatalf("pre-existing cache entry was altered: %q, %v", data, err)
	}
}

func TestCanceledInstallPreservesChangesWhenAnotherPackageManagerWasObserved(t *testing.T) {
	previousInventory := pacmanPackageInventory
	previousRemove := removePacmanPackages
	t.Cleanup(func() {
		pacmanPackageInventory = previousInventory
		removePacmanPackages = previousRemove
	})

	installed := map[string]string{"base": "1.0-1"}
	pacmanPackageInventory = func() (map[string]string, bool) {
		copy := make(map[string]string, len(installed))
		for name, version := range installed {
			copy[name] = version
		}
		return copy, true
	}
	removePacmanPackages = func([]string) error {
		t.Fatal("concurrent package state must not be removed")
		return nil
	}

	snapshot := snapshotPacmanPackages()
	installed["concurrent"] = "1.0-1"
	cleanup := cleanupCanceledPacmanPackages(snapshot, managerEvidence{
		owned:    true,
		foreign:  true,
		reliable: true,
	})
	if cleanup != cancelCleanupPacmanPackagesRetained {
		t.Fatalf("concurrent package cleanup = %v", cleanup)
	}
	if _, remains := installed["concurrent"]; !remains {
		t.Fatal("concurrent package was removed")
	}
}

func TestCanceledInstallReportsChangedPreexistingPackageVersions(t *testing.T) {
	previousInventory := pacmanPackageInventory
	previousRemove := removePacmanPackages
	previousStatus := packageManagerStatus
	t.Cleanup(func() {
		pacmanPackageInventory = previousInventory
		removePacmanPackages = previousRemove
		packageManagerStatus = previousStatus
	})

	installed := map[string]string{"base": "1.0-1"}
	pacmanPackageInventory = func() (map[string]string, bool) {
		copy := make(map[string]string, len(installed))
		for name, version := range installed {
			copy[name] = version
		}
		return copy, true
	}
	packageManagerStatus = func() (bool, bool) { return false, true }
	removePacmanPackages = func(packages []string) error {
		for _, name := range packages {
			delete(installed, name)
		}
		return nil
	}

	snapshot := snapshotPacmanPackages()
	installed["base"] = "1.1-1"
	installed["target"] = "2.0-1"
	cleanup := cleanupCanceledPacmanPackages(snapshot, managerEvidence{owned: true, reliable: true})
	if !cleanup.includes(cancelCleanupPacmanPackagesRemoved) ||
		!cleanup.includes(cancelCleanupPacmanPackagesRetained) {
		t.Fatalf("version-changing package rollback = %v", cleanup)
	}
	if installed["base"] != "1.1-1" {
		t.Fatal("rollback modified a pre-existing package version")
	}
	if _, remains := installed["target"]; remains {
		t.Fatal("rollback retained a package added by the attempt")
	}
}

func TestCanceledInstallReportsARemovedPreexistingPackage(t *testing.T) {
	previousInventory := pacmanPackageInventory
	t.Cleanup(func() { pacmanPackageInventory = previousInventory })
	installed := map[string]string{"base": "1.0-1"}
	pacmanPackageInventory = func() (map[string]string, bool) {
		copy := make(map[string]string, len(installed))
		for name, version := range installed {
			copy[name] = version
		}
		return copy, true
	}

	snapshot := snapshotPacmanPackages()
	delete(installed, "base")
	cleanup := cleanupCanceledPacmanPackages(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupPacmanPackagesRetained {
		t.Fatalf("removed pre-existing package cleanup = %v", cleanup)
	}
}

func TestPacmanRollbackRemovesExactlyTheAddedPackages(t *testing.T) {
	binDir := t.TempDir()
	argumentsPath := filepath.Join(t.TempDir(), "sudo-arguments")
	sudo := filepath.Join(binDir, "sudo")
	if err := os.WriteFile(sudo, []byte("#!/bin/bash\nprintf '%s\\n' \"$@\" >\"$QVOS_TEST_SUDO_ARGUMENTS\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("QVOS_TEST_SUDO_ARGUMENTS", argumentsPath)

	if err := removePacmanPackagesWithSudo([]string{"new-dependency", "new-target"}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(argumentsPath)
	if err != nil {
		t.Fatal(err)
	}
	arguments := strings.Fields(string(data))
	want := []string{"-n", "pacman", "-Rn", "--noconfirm", "--", "new-dependency", "new-target"}
	if strings.Join(arguments, " ") != strings.Join(want, " ") {
		t.Fatalf("Pacman rollback arguments = %q, want %q", arguments, want)
	}
}
