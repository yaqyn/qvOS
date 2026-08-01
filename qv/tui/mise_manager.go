package main

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

type managedFileSnapshot struct {
	data     []byte
	mode     fs.FileMode
	existed  bool
	reliable bool
}

type miseStateSnapshot struct {
	dataDir       string
	installPaths  map[string]managedPathSnapshot
	installOK     bool
	downloadPaths map[string]managedPathSnapshot
	downloadOK    bool
	configPath    string
	config        managedFileSnapshot
	lockPath      string
	lock          managedFileSnapshot
	auxiliary     []miseAuxiliaryTreeSnapshot
	emptyRoots    []managedDirectorySnapshot
	reliable      bool
}

type miseAuxiliaryTreeSnapshot struct {
	root        string
	maxDepth    int
	paths       map[string]managedPathSnapshot
	rootExisted bool
	reliable    bool
}

type managedPathSnapshot struct {
	state    pathSnapshot
	terminal bool
}

type managedDirectorySnapshot struct {
	path     string
	existed  bool
	reliable bool
}

var (
	miseProcessStatus = func() (bool, bool) {
		return commandRunning("mise")
	}
	removeMisePaths = removeManagedPaths
	restoreMiseFile = restoreManagedFile
	reshimMise      = runMiseReshim
)

func snapshotMiseState() miseStateSnapshot {
	dataDir, configPath, reliable := miseManagedPaths()
	if !reliable {
		return miseStateSnapshot{}
	}
	installRoot := filepath.Join(dataDir, "installs")
	downloadRoot := filepath.Join(dataDir, "downloads")
	installPaths, installReliable := snapshotManagedTree(installRoot, 2)
	downloadPaths, downloadReliable := snapshotManagedTree(downloadRoot, 3)
	config := snapshotManagedFile(configPath)
	lockPath := filepath.Join(filepath.Dir(configPath), "mise.lock")
	lock := snapshotManagedFile(lockPath)
	emptyRoots := []managedDirectorySnapshot{
		snapshotManagedDirectory(installRoot),
		snapshotManagedDirectory(downloadRoot),
		snapshotManagedDirectory(dataDir),
		snapshotManagedDirectory(filepath.Dir(configPath)),
	}
	rootsReliable := true
	for _, root := range emptyRoots {
		rootsReliable = rootsReliable && root.reliable
	}
	home, homeErr := os.UserHomeDir()
	auxiliary := make([]miseAuxiliaryTreeSnapshot, 0, 2)
	auxiliaryReliable := homeErr == nil && filepath.IsAbs(home)
	if auxiliaryReliable {
		for _, tree := range []struct {
			root     string
			maxDepth int
		}{
			{filepath.Join(home, ".mix"), 5},
			{filepath.Join(home, ".hex"), 4},
		} {
			_, err := os.Lstat(tree.root)
			rootExisted := err == nil
			if err != nil && !errors.Is(err, os.ErrNotExist) {
				auxiliaryReliable = false
				break
			}
			paths, treeReliable := snapshotManagedTree(tree.root, tree.maxDepth)
			if !treeReliable {
				auxiliaryReliable = false
				break
			}
			auxiliary = append(auxiliary, miseAuxiliaryTreeSnapshot{
				root:        tree.root,
				maxDepth:    tree.maxDepth,
				paths:       paths,
				rootExisted: rootExisted,
				reliable:    true,
			})
		}
	}

	return miseStateSnapshot{
		dataDir:       dataDir,
		installPaths:  installPaths,
		installOK:     installReliable,
		downloadPaths: downloadPaths,
		downloadOK:    downloadReliable,
		configPath:    configPath,
		config:        config,
		lockPath:      lockPath,
		lock:          lock,
		auxiliary:     auxiliary,
		emptyRoots:    emptyRoots,
		reliable: installReliable && downloadReliable &&
			config.reliable && lock.reliable && auxiliaryReliable && rootsReliable,
	}
}

func miseManagedPaths() (string, string, bool) {
	home, err := os.UserHomeDir()
	if err != nil || !filepath.IsAbs(home) {
		return "", "", false
	}

	dataDir := strings.TrimSpace(os.Getenv("MISE_DATA_DIR"))
	if dataDir == "" {
		dataHome := strings.TrimSpace(os.Getenv("XDG_DATA_HOME"))
		if dataHome == "" {
			dataHome = filepath.Join(home, ".local", "share")
		}
		dataDir = filepath.Join(dataHome, "mise")
	}
	configPath := strings.TrimSpace(os.Getenv("MISE_GLOBAL_CONFIG_FILE"))
	if configPath == "" {
		configHome := strings.TrimSpace(os.Getenv("XDG_CONFIG_HOME"))
		if configHome == "" {
			configHome = filepath.Join(home, ".config")
		}
		configPath = filepath.Join(configHome, "mise", "config.toml")
	}
	dataDir = filepath.Clean(dataDir)
	configPath = filepath.Clean(configPath)
	if !filepath.IsAbs(dataDir) || !filepath.IsAbs(configPath) {
		return "", "", false
	}
	return dataDir, configPath, true
}

func snapshotManagedDirectory(path string) managedDirectorySnapshot {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return managedDirectorySnapshot{path: path, reliable: true}
	}
	return managedDirectorySnapshot{
		path:     path,
		existed:  err == nil,
		reliable: err == nil && safeOwnedDirectory(info),
	}
}

func snapshotManagedTree(root string, maxDepth int) (map[string]managedPathSnapshot, bool) {
	paths := make(map[string]managedPathSnapshot)
	info, err := os.Lstat(root)
	if errors.Is(err, os.ErrNotExist) {
		return paths, true
	}
	if err != nil || !safeOwnedDirectory(info) {
		return nil, false
	}

	var walk func(string, int) bool
	walk = func(current string, depth int) bool {
		entries, err := os.ReadDir(current)
		if err != nil {
			return false
		}
		for _, entry := range entries {
			path := filepath.Join(current, entry.Name())
			state, err := snapshotPath(path)
			if err != nil || state.uid != uint32(os.Getuid()) {
				return false
			}
			terminal := depth >= maxDepth
			paths[path] = managedPathSnapshot{state: state, terminal: terminal}
			if terminal || !entry.IsDir() {
				continue
			}
			info, err := os.Lstat(path)
			if err != nil || !safeOwnedDirectory(info) || !walk(path, depth+1) {
				return false
			}
		}
		return true
	}
	if !walk(root, 1) {
		return nil, false
	}
	return paths, true
}

func safeOwnedDirectory(info os.FileInfo) bool {
	stat, ok := infoSysStat(info)
	return ok && info.IsDir() && info.Mode()&os.ModeSymlink == 0 &&
		stat.Uid == uint32(os.Getuid())
}

func snapshotManagedFile(path string) managedFileSnapshot {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return managedFileSnapshot{reliable: true}
	}
	stat, ownerOK := infoSysStat(info)
	if err != nil || !info.Mode().IsRegular() || !ownerOK ||
		stat.Uid != uint32(os.Getuid()) {
		return managedFileSnapshot{}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return managedFileSnapshot{}
	}
	return managedFileSnapshot{
		data:     data,
		mode:     info.Mode().Perm(),
		existed:  true,
		reliable: true,
	}
}

func cleanupCanceledMise(snapshot miseStateSnapshot, evidence managerEvidence) cancelCleanup {
	if snapshot.dataDir == "" {
		if evidence.owned {
			return cancelCleanupMiseRetained
		}
		return cancelCleanupNone
	}

	cleanup := cancelCleanupNone
	var newPaths []string
	existingChanged := false
	for _, tree := range []struct {
		root     string
		maxDepth int
		before   map[string]managedPathSnapshot
		reliable bool
	}{
		{filepath.Join(snapshot.dataDir, "installs"), 2, snapshot.installPaths, snapshot.installOK},
		{filepath.Join(snapshot.dataDir, "downloads"), 3, snapshot.downloadPaths, snapshot.downloadOK},
	} {
		current, reliable := snapshotManagedTree(tree.root, tree.maxDepth)
		if !tree.reliable || !reliable {
			cleanup |= cancelCleanupMiseRetained
			continue
		}
		created, changed := changedManagedPaths(tree.before, current)
		newPaths = append(newPaths, created...)
		existingChanged = existingChanged || changed
	}
	for _, tree := range snapshot.auxiliary {
		current, reliable := snapshotManagedTree(tree.root, tree.maxDepth)
		if !tree.reliable || !reliable {
			cleanup |= cancelCleanupMiseRetained
			continue
		}
		created, changed := changedManagedPaths(tree.paths, current)
		newPaths = append(newPaths, created...)
		existingChanged = existingChanged || changed
	}
	configChanged := managedFileChanged(snapshot.configPath, snapshot.config)
	lockChanged := managedFileChanged(snapshot.lockPath, snapshot.lock)
	if existingChanged {
		cleanup |= cancelCleanupMiseRetained
	}
	rootCreated := false
	for _, root := range snapshot.emptyRoots {
		rootCreated = rootCreated || !root.existed && pathExistsOrUnknown(root.path)
	}
	for _, tree := range snapshot.auxiliary {
		rootCreated = rootCreated || !tree.rootExisted && pathExistsOrUnknown(tree.root)
	}
	if len(newPaths) == 0 && !configChanged && !lockChanged &&
		cleanup == cancelCleanupNone && !rootCreated {
		return cancelCleanupNone
	}
	if !evidence.exclusive() {
		return cleanup | cancelCleanupMiseRetained
	}
	miseActive, processScanReliable := miseProcessStatus()
	if !processScanReliable || miseActive {
		return cleanup | cancelCleanupMiseRetained
	}

	if len(newPaths) > 0 {
		if err := removeMisePaths(newPaths); err != nil {
			cleanup |= cancelCleanupMiseRetained
		}
		for _, path := range newPaths {
			if pathExistsOrUnknown(path) {
				cleanup |= cancelCleanupMiseRetained
			} else {
				cleanup |= cancelCleanupMiseRestored
			}
		}
	}
	for _, file := range []struct {
		path     string
		snapshot managedFileSnapshot
		changed  bool
	}{
		{snapshot.configPath, snapshot.config, configChanged},
		{snapshot.lockPath, snapshot.lock, lockChanged},
	} {
		if !file.changed {
			continue
		}
		if !file.snapshot.reliable {
			cleanup |= cancelCleanupMiseRetained
			continue
		}
		if err := restoreMiseFile(file.path, file.snapshot); err != nil ||
			managedFileChanged(file.path, file.snapshot) {
			cleanup |= cancelCleanupMiseRetained
		} else {
			cleanup |= cancelCleanupMiseRestored
		}
	}
	emptyRoots := append([]managedDirectorySnapshot(nil), snapshot.emptyRoots...)
	for _, tree := range snapshot.auxiliary {
		emptyRoots = append(emptyRoots, managedDirectorySnapshot{
			path:     tree.root,
			existed:  tree.rootExisted,
			reliable: tree.reliable,
		})
	}
	rootsRemoved, rootsRetained := removeNewEmptyManagedDirectories(emptyRoots)
	if rootsRemoved {
		cleanup |= cancelCleanupMiseRestored
	}
	if rootsRetained {
		cleanup |= cancelCleanupMiseRetained
	}
	if cleanup.includes(cancelCleanupMiseRestored) {
		if err := reshimMise(); err != nil {
			cleanup |= cancelCleanupMiseRetained
		}
	}
	return cleanup
}

func changedManagedPaths(
	before map[string]managedPathSnapshot,
	after map[string]managedPathSnapshot,
) ([]string, bool) {
	var candidates []string
	changed := false
	for path, current := range after {
		previous, existed := before[path]
		if !existed {
			candidates = append(candidates, path)
			continue
		}
		if !previous.state.sameIdentity(current.state) ||
			(previous.terminal || !previous.state.mode.IsDir()) &&
				!previous.state.sameContent(current.state) {
			changed = true
		}
	}
	for path := range before {
		if _, remains := after[path]; !remains {
			changed = true
		}
	}
	sort.Slice(candidates, func(i, j int) bool {
		leftDepth := strings.Count(candidates[i], string(os.PathSeparator))
		rightDepth := strings.Count(candidates[j], string(os.PathSeparator))
		if leftDepth == rightDepth {
			return candidates[i] < candidates[j]
		}
		return leftDepth < rightDepth
	})

	var topLevel []string
	for _, candidate := range candidates {
		contained := false
		for _, parent := range topLevel {
			if pathWithin(parent, candidate) {
				contained = true
				break
			}
		}
		if !contained {
			topLevel = append(topLevel, candidate)
		}
	}
	return topLevel, changed
}

func pathWithin(parent, child string) bool {
	relative, err := filepath.Rel(parent, child)
	return err == nil && relative != "." && relative != ".." &&
		!strings.HasPrefix(relative, ".."+string(os.PathSeparator))
}

func removeManagedPaths(paths []string) error {
	var failures []error
	for _, path := range paths {
		info, err := os.Lstat(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		stat, ownerOK := infoSysStat(info)
		if err != nil || !ownerOK || stat.Uid != uint32(os.Getuid()) {
			failures = append(failures, fmt.Errorf("refusing unowned managed path: %s", path))
			continue
		}
		if err := os.RemoveAll(path); err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}

func removeNewEmptyManagedDirectories(
	snapshots []managedDirectorySnapshot,
) (bool, bool) {
	seen := make(map[string]struct{})
	var candidates []managedDirectorySnapshot
	retained := false
	for _, snapshot := range snapshots {
		if !snapshot.reliable {
			retained = true
			continue
		}
		if snapshot.existed {
			continue
		}
		if _, exists := seen[snapshot.path]; exists {
			continue
		}
		seen[snapshot.path] = struct{}{}
		candidates = append(candidates, snapshot)
	}
	sort.Slice(candidates, func(i, j int) bool {
		return strings.Count(candidates[i].path, string(os.PathSeparator)) >
			strings.Count(candidates[j].path, string(os.PathSeparator))
	})
	removed := false
	for _, candidate := range candidates {
		entries, err := os.ReadDir(candidate.path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		info, infoErr := os.Lstat(candidate.path)
		if err != nil || infoErr != nil || len(entries) != 0 ||
			!safeOwnedDirectory(info) || os.Remove(candidate.path) != nil {
			retained = true
			continue
		}
		removed = true
	}
	return removed, retained
}

func managedFileChanged(path string, snapshot managedFileSnapshot) bool {
	current := snapshotManagedFile(path)
	if !current.reliable {
		return true
	}
	return current.existed != snapshot.existed ||
		current.mode != snapshot.mode ||
		!bytes.Equal(current.data, snapshot.data)
}

func restoreManagedFile(path string, snapshot managedFileSnapshot) error {
	if !snapshot.reliable {
		return fmt.Errorf("unreliable mise file snapshot")
	}
	if !snapshot.existed {
		info, err := os.Lstat(path)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		stat, ownerOK := infoSysStat(info)
		if err != nil || !info.Mode().IsRegular() || !ownerOK ||
			stat.Uid != uint32(os.Getuid()) {
			return fmt.Errorf("refusing unexpected mise file: %s", path)
		}
		return os.Remove(path)
	}
	if info, err := os.Lstat(path); err == nil {
		stat, ownerOK := infoSysStat(info)
		if !info.Mode().IsRegular() || !ownerOK || stat.Uid != uint32(os.Getuid()) {
			return fmt.Errorf("refusing unexpected mise file: %s", path)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}

	parent := filepath.Dir(path)
	parentInfo, err := os.Lstat(parent)
	if err != nil || !safeOwnedDirectory(parentInfo) {
		return fmt.Errorf("refusing unsafe mise config directory: %s", parent)
	}
	temporary, err := os.CreateTemp(parent, ".qvos-mise-restore-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(snapshot.mode); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(snapshot.data); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}

func runMiseReshim() error {
	cmd := exec.Command("mise", "reshim")
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

func commandRunning(command string) (bool, bool) {
	return anyProcProcess(func(_, _ int, name string, _ []string) bool {
		return name == command
	})
}
