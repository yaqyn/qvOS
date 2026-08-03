package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestCanceledInstallRemovesOnlyNewAURBuildTrees(t *testing.T) {
	previousRemove := removeAURCachePaths
	previousStatus := packageManagerStatus
	t.Cleanup(func() {
		removeAURCachePaths = previousRemove
		packageManagerStatus = previousStatus
	})

	cacheHome := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cacheHome)
	removeAURCachePaths = removeManagedPaths
	packageManagerStatus = func() (bool, bool) { return false, true }
	preexisting := filepath.Join(cacheHome, "yay", "existing-package")
	if err := os.MkdirAll(preexisting, 0o755); err != nil {
		t.Fatal(err)
	}
	snapshot := snapshotAURCache()
	created := []string{
		filepath.Join(cacheHome, "yay", "new-package"),
		filepath.Join(cacheHome, "paru", "clone", "new-package"),
	}
	for _, path := range created {
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(path, "partial-source"), []byte("partial"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	cleanup := cleanupCanceledAURCache(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupAURRemoved {
		t.Fatalf("AUR cleanup = %v", cleanup)
	}
	for _, path := range created {
		if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("new AUR tree remains: %s (%v)", path, err)
		}
	}
	if _, err := os.Stat(preexisting); err != nil {
		t.Fatalf("pre-existing AUR tree was removed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(cacheHome, "paru")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("new empty paru cache root remains: %v", err)
	}
}

func TestCanceledInstallPreservesUnownedAURBuildTree(t *testing.T) {
	previousRemove := removeAURCachePaths
	t.Cleanup(func() {
		removeAURCachePaths = previousRemove
	})

	cacheHome := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cacheHome)
	removeAURCachePaths = func([]string) error {
		t.Fatal("unowned AUR cache must not be removed")
		return nil
	}
	snapshot := snapshotAURCache()
	created := filepath.Join(cacheHome, "yay", "unowned-package")
	if err := os.MkdirAll(created, 0o755); err != nil {
		t.Fatal(err)
	}
	cleanup := cleanupCanceledAURCache(snapshot, managerEvidence{reliable: true})
	if cleanup != cancelCleanupAURRetained {
		t.Fatalf("unowned AUR cleanup = %v", cleanup)
	}
	if _, err := os.Stat(created); err != nil {
		t.Fatalf("unowned AUR tree was removed: %v", err)
	}
}

func TestCanceledInstallReportsModifiedPreexistingAURBuildTree(t *testing.T) {
	previousStatus := packageManagerStatus
	t.Cleanup(func() { packageManagerStatus = previousStatus })

	cacheHome := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cacheHome)
	preexisting := filepath.Join(cacheHome, "yay", "existing-package")
	if err := os.MkdirAll(preexisting, 0o755); err != nil {
		t.Fatal(err)
	}
	snapshot := snapshotAURCache()
	partial := filepath.Join(preexisting, "partial-source")
	if err := os.WriteFile(partial, []byte("partial"), 0o600); err != nil {
		t.Fatal(err)
	}
	packageManagerStatus = func() (bool, bool) { return false, true }

	cleanup := cleanupCanceledAURCache(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupAURRetained {
		t.Fatalf("modified AUR cache cleanup = %v", cleanup)
	}
	if _, err := os.Stat(partial); err != nil {
		t.Fatalf("pre-existing AUR tree was removed: %v", err)
	}
}

func TestCanceledInstallRemovesANewEmptyAURCacheRoot(t *testing.T) {
	previousStatus := packageManagerStatus
	t.Cleanup(func() { packageManagerStatus = previousStatus })
	cacheHome := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cacheHome)
	snapshot := snapshotAURCache()
	yayRoot := filepath.Join(cacheHome, "yay")
	if err := os.Mkdir(yayRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	packageManagerStatus = func() (bool, bool) { return false, true }

	cleanup := cleanupCanceledAURCache(snapshot, managerEvidence{owned: true, reliable: true})
	if cleanup != cancelCleanupAURRemoved {
		t.Fatalf("empty AUR root cleanup = %v", cleanup)
	}
	if _, err := os.Lstat(yayRoot); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("new empty AUR root remains: %v", err)
	}
}
