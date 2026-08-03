package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

type aurCacheTreeSnapshot struct {
	root        string
	maxDepth    int
	paths       map[string]managedPathSnapshot
	rootExisted bool
	reliable    bool
}

type aurCacheSnapshot struct {
	trees    []aurCacheTreeSnapshot
	reliable bool
}

var removeAURCachePaths = removeManagedPaths

func snapshotAURCache() aurCacheSnapshot {
	cacheHome, reliable := userCacheHome()
	if !reliable {
		return aurCacheSnapshot{}
	}
	treesToSnapshot := []struct {
		root     string
		maxDepth int
	}{
		{filepath.Join(cacheHome, "yay"), 1},
		{filepath.Join(cacheHome, "paru"), 2},
	}
	trees := make([]aurCacheTreeSnapshot, 0, len(treesToSnapshot))
	for _, tree := range treesToSnapshot {
		_, err := os.Lstat(tree.root)
		rootExisted := err == nil
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return aurCacheSnapshot{}
		}
		paths, treeReliable := snapshotManagedTree(tree.root, tree.maxDepth)
		if !treeReliable {
			return aurCacheSnapshot{}
		}
		trees = append(trees, aurCacheTreeSnapshot{
			root:        tree.root,
			maxDepth:    tree.maxDepth,
			paths:       paths,
			rootExisted: rootExisted,
			reliable:    true,
		})
	}
	return aurCacheSnapshot{trees: trees, reliable: true}
}

func userCacheHome() (string, bool) {
	home, err := os.UserHomeDir()
	if err != nil || !filepath.IsAbs(home) {
		return "", false
	}
	cacheHome := strings.TrimSpace(os.Getenv("XDG_CACHE_HOME"))
	if cacheHome == "" {
		cacheHome = filepath.Join(home, ".cache")
	}
	cacheHome = filepath.Clean(cacheHome)
	return cacheHome, filepath.IsAbs(cacheHome)
}

func cleanupCanceledAURCache(
	snapshot aurCacheSnapshot,
	evidence managerEvidence,
) cancelCleanup {
	if !snapshot.reliable {
		if evidence.owned {
			return cancelCleanupAURRetained
		}
		return cancelCleanupNone
	}
	var candidates []string
	existingChanged := false
	rootCreated := false
	for _, tree := range snapshot.trees {
		current, reliable := snapshotManagedTree(tree.root, tree.maxDepth)
		if !tree.reliable || !reliable {
			return cancelCleanupAURRetained
		}
		created, changed := changedManagedPaths(tree.paths, current)
		candidates = append(candidates, created...)
		existingChanged = existingChanged || changed
		rootCreated = rootCreated || !tree.rootExisted && pathExistsOrUnknown(tree.root)
	}
	if len(candidates) == 0 && !rootCreated {
		if existingChanged && evidence.owned {
			return cancelCleanupAURRetained
		}
		return cancelCleanupNone
	}
	if !evidence.exclusive() {
		return cancelCleanupAURRetained
	}
	managerActive, processScanReliable := packageManagerStatus()
	if !processScanReliable || managerActive {
		return cancelCleanupAURRetained
	}
	cleanup := cancelCleanupNone
	if err := removeAURCachePaths(candidates); err != nil {
		cleanup |= cancelCleanupAURRetained
	}
	for _, path := range candidates {
		if pathExistsOrUnknown(path) {
			cleanup |= cancelCleanupAURRetained
		} else {
			cleanup |= cancelCleanupAURRemoved
		}
	}
	var roots []managedDirectorySnapshot
	for _, tree := range snapshot.trees {
		roots = append(roots, managedDirectorySnapshot{
			path:     tree.root,
			existed:  tree.rootExisted,
			reliable: tree.reliable,
		})
	}
	rootsRemoved, rootsRetained := removeNewEmptyManagedDirectories(roots)
	if rootsRemoved {
		cleanup |= cancelCleanupAURRemoved
	}
	if rootsRetained {
		cleanup |= cancelCleanupAURRetained
	}
	if existingChanged {
		cleanup |= cancelCleanupAURRetained
	}
	return cleanup
}
