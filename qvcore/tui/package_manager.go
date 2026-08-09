package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

type cancelCleanup uint16

const (
	cancelCleanupNone              cancelCleanup = 0
	cancelCleanupPacmanLockRemoved cancelCleanup = 1 << iota
	cancelCleanupPacmanLockRetained
	cancelCleanupPacmanPartialsRemoved
	cancelCleanupPacmanPartialsRetained
	cancelCleanupMiseRestored
	cancelCleanupMiseRetained
	cancelCleanupPacmanPackagesRemoved
	cancelCleanupPacmanPackagesRetained
	cancelCleanupPacmanCacheRemoved
	cancelCleanupPacmanCacheRetained
	cancelCleanupAURRemoved
	cancelCleanupAURRetained
	cancelCleanupOwnerRestored
	cancelCleanupOwnerRetained
)

type pacmanPartialSnapshot struct {
	cacheDirs []string
	paths     map[string]pathSnapshot
	reliable  bool
}

type pacmanPackageSnapshot struct {
	packages map[string]string
	reliable bool
}

type pacmanCacheSnapshot struct {
	cacheDirs []string
	paths     map[string]pathSnapshot
	reliable  bool
}

type managerEvidence struct {
	owned    bool
	foreign  bool
	reliable bool
}

func (evidence managerEvidence) exclusive() bool {
	return evidence.owned && !evidence.foreign && evidence.reliable
}

var (
	pacmanDBLockPath       = "/var/lib/pacman/db.lck"
	pacmanDBLockOwnerUID   = uint32(0)
	packageManagerStatus   = packageManagerRunning
	removePacmanDBLockFile = removePacmanDBLockWithSudo
	pacmanCacheDirectories = configuredPacmanCacheDirectories
	removePacmanCacheFiles = removePacmanCacheFilesWithSudo
	pacmanPackageInventory = installedPacmanPackages
	removePacmanPackages   = removePacmanPackagesWithSudo
	procRoot               = "/proc"
)

var packageManagerCommands = map[string]struct{}{
	"makepkg":     {},
	"pacman":      {},
	"pamac":       {},
	"paru":        {},
	"pikaur":      {},
	"repo-add":    {},
	"repo-remove": {},
	"trizen":      {},
	"yay":         {},
}

var aurManagerCommands = map[string]struct{}{
	"makepkg": {},
	"paru":    {},
	"pikaur":  {},
	"trizen":  {},
	"yay":     {},
}

var miseManagerCommands = map[string]struct{}{
	"mise": {},
	"mix":  {},
}

type managerProcessScan struct {
	ownedPacman   bool
	ownedMise     bool
	ownedAUR      bool
	foreignPacman bool
	foreignMise   bool
	reliable      bool
}

type procProcessStat struct {
	name   string
	state  byte
	parent int
	group  int
}

func pathExistsOrUnknown(path string) bool {
	_, err := os.Lstat(path)
	return err == nil || !errors.Is(err, os.ErrNotExist)
}

func (cleanup cancelCleanup) includes(flag cancelCleanup) bool {
	return cleanup&flag != 0
}

func configuredPacmanCacheDirectories() ([]string, bool) {
	output, err := exec.Command("pacman-conf", "CacheDir").Output()
	if err != nil {
		return nil, false
	}

	seen := make(map[string]struct{})
	var directories []string
	for directory := range strings.Lines(string(output)) {
		directory = filepath.Clean(strings.TrimSpace(directory))
		if directory == "." || !filepath.IsAbs(directory) {
			return nil, false
		}
		if _, exists := seen[directory]; exists {
			continue
		}
		seen[directory] = struct{}{}
		directories = append(directories, directory)
	}
	return directories, len(directories) > 0
}

func isPacmanPartialName(name string) bool {
	return strings.HasSuffix(name, ".part") || strings.HasSuffix(name, ".partial")
}

func snapshotPacmanPackages() pacmanPackageSnapshot {
	packages, reliable := pacmanPackageInventory()
	return pacmanPackageSnapshot{packages: packages, reliable: reliable}
}

func installedPacmanPackages() (map[string]string, bool) {
	output, err := exec.Command("pacman", "-Q").Output()
	if err != nil {
		return nil, false
	}
	packages := make(map[string]string)
	for line := range strings.Lines(string(output)) {
		fields := strings.Fields(line)
		if len(fields) != 2 || strings.ContainsAny(fields[0], "/\r\n") {
			return nil, false
		}
		packages[fields[0]] = fields[1]
	}
	return packages, true
}

func cleanupCanceledPacmanPackages(
	snapshot pacmanPackageSnapshot,
	evidence managerEvidence,
) cancelCleanup {
	if !snapshot.reliable {
		if evidence.owned {
			return cancelCleanupPacmanPackagesRetained
		}
		return cancelCleanupNone
	}
	current, reliable := pacmanPackageInventory()
	if !reliable {
		return cancelCleanupPacmanPackagesRetained
	}
	var added []string
	changed := false
	for name, version := range current {
		if _, existed := snapshot.packages[name]; !existed {
			added = append(added, name)
		} else if snapshot.packages[name] != version {
			changed = true
		}
	}
	for name := range snapshot.packages {
		if _, remains := current[name]; !remains {
			changed = true
		}
	}
	if len(added) == 0 {
		if changed && evidence.owned {
			return cancelCleanupPacmanPackagesRetained
		}
		return cancelCleanupNone
	}
	if !evidence.exclusive() {
		return cancelCleanupPacmanPackagesRetained
	}
	packageManagerActive, processScanReliable := packageManagerStatus()
	if !processScanReliable || packageManagerActive {
		return cancelCleanupPacmanPackagesRetained
	}
	sort.Strings(added)
	if err := removePacmanPackages(added); err != nil {
		return cancelCleanupPacmanPackagesRetained
	}
	after, reliable := pacmanPackageInventory()
	if !reliable {
		return cancelCleanupPacmanPackagesRetained
	}
	for _, name := range added {
		if _, remains := after[name]; remains {
			return cancelCleanupPacmanPackagesRetained
		}
	}
	cleanup := cancelCleanupPacmanPackagesRemoved
	if changed {
		cleanup |= cancelCleanupPacmanPackagesRetained
	}
	return cleanup
}

func scanPacmanCacheEntries(
	cacheDirs []string,
	include func(string) bool,
) (map[string]pathSnapshot, bool) {
	paths := make(map[string]pathSnapshot)
	for _, cacheDir := range cacheDirs {
		info, err := os.Lstat(cacheDir)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return nil, false
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || stat.Uid != pacmanDBLockOwnerUID {
			return nil, false
		}

		entries, err := os.ReadDir(cacheDir)
		if err != nil {
			return nil, false
		}
		for _, entry := range entries {
			if include(entry.Name()) {
				path := filepath.Join(cacheDir, entry.Name())
				snapshot, err := snapshotPath(path)
				if err != nil {
					return nil, false
				}
				paths[path] = snapshot
			}
		}
	}
	return paths, true
}

func snapshotPacmanPartials() pacmanPartialSnapshot {
	cacheDirs, reliable := pacmanCacheDirectories()
	if !reliable {
		return pacmanPartialSnapshot{}
	}
	paths, reliable := scanPacmanCacheEntries(cacheDirs, isPacmanPartialName)
	return pacmanPartialSnapshot{
		cacheDirs: cacheDirs,
		paths:     paths,
		reliable:  reliable,
	}
}

func snapshotPacmanCache() pacmanCacheSnapshot {
	cacheDirs, reliable := pacmanCacheDirectories()
	if !reliable {
		return pacmanCacheSnapshot{}
	}
	paths, reliable := scanPacmanCacheEntries(cacheDirs, func(string) bool { return true })
	return pacmanCacheSnapshot{
		cacheDirs: cacheDirs,
		paths:     paths,
		reliable:  reliable,
	}
}

func changedPacmanCacheEntries(
	before map[string]pathSnapshot,
	after map[string]pathSnapshot,
) ([]string, bool) {
	var created []string
	changed := false
	for path, current := range after {
		previous, existed := before[path]
		if !existed {
			created = append(created, path)
			continue
		}
		if !previous.sameContent(current) {
			changed = true
		}
	}
	for path := range before {
		if _, remains := after[path]; !remains {
			changed = true
		}
	}
	return created, changed
}

func cleanupCanceledPacmanPartials(
	snapshot pacmanPartialSnapshot,
	evidence managerEvidence,
) cancelCleanup {
	if !snapshot.reliable {
		if evidence.owned {
			return cancelCleanupPacmanPartialsRetained
		}
		return cancelCleanupNone
	}

	current, reliable := scanPacmanCacheEntries(snapshot.cacheDirs, isPacmanPartialName)
	if !reliable {
		return cancelCleanupPacmanPartialsRetained
	}
	candidates, changed := changedPacmanCacheEntries(snapshot.paths, current)
	if len(candidates) == 0 {
		if changed && evidence.owned {
			return cancelCleanupPacmanPartialsRetained
		}
		return cancelCleanupNone
	}
	if !evidence.exclusive() {
		return cancelCleanupPacmanPartialsRetained
	}
	packageManagerActive, processScanReliable := packageManagerStatus()
	if !processScanReliable || packageManagerActive {
		return cancelCleanupPacmanPartialsRetained
	}

	allowedDirs := make(map[string]struct{}, len(snapshot.cacheDirs))
	for _, cacheDir := range snapshot.cacheDirs {
		allowedDirs[cacheDir] = struct{}{}
	}
	cleanup := cancelCleanupNone
	var removable []string
	for _, path := range candidates {
		info, err := os.Lstat(path)
		_, allowed := allowedDirs[filepath.Dir(path)]
		stat, ownerOK := infoSysStat(info)
		if err != nil || !allowed || !info.Mode().IsRegular() ||
			!ownerOK || stat.Uid != pacmanDBLockOwnerUID {
			cleanup |= cancelCleanupPacmanPartialsRetained
			continue
		}
		removable = append(removable, path)
	}
	if len(removable) == 0 {
		return cleanup | cancelCleanupPacmanPartialsRetained
	}
	if err := removePacmanCacheFiles(removable); err != nil {
		cleanup |= cancelCleanupPacmanPartialsRetained
	}
	for _, path := range removable {
		if pathExistsOrUnknown(path) {
			cleanup |= cancelCleanupPacmanPartialsRetained
		} else {
			cleanup |= cancelCleanupPacmanPartialsRemoved
		}
	}
	if changed {
		cleanup |= cancelCleanupPacmanPartialsRetained
	}
	return cleanup
}

func cleanupCanceledPacmanCache(
	snapshot pacmanCacheSnapshot,
	evidence managerEvidence,
) cancelCleanup {
	if !snapshot.reliable {
		if evidence.owned {
			return cancelCleanupPacmanCacheRetained
		}
		return cancelCleanupNone
	}
	current, reliable := scanPacmanCacheEntries(
		snapshot.cacheDirs,
		func(string) bool { return true },
	)
	if !reliable {
		return cancelCleanupPacmanCacheRetained
	}
	candidates, changed := changedPacmanCacheEntries(snapshot.paths, current)
	if len(candidates) == 0 {
		if changed && evidence.owned {
			return cancelCleanupPacmanCacheRetained
		}
		return cancelCleanupNone
	}
	if !evidence.exclusive() {
		return cancelCleanupPacmanCacheRetained
	}
	packageManagerActive, processScanReliable := packageManagerStatus()
	if !processScanReliable || packageManagerActive {
		return cancelCleanupPacmanCacheRetained
	}

	allowedDirs := make(map[string]struct{}, len(snapshot.cacheDirs))
	for _, cacheDir := range snapshot.cacheDirs {
		allowedDirs[cacheDir] = struct{}{}
	}
	cleanup := cancelCleanupNone
	var removable []string
	for _, path := range candidates {
		info, err := os.Lstat(path)
		_, allowed := allowedDirs[filepath.Dir(path)]
		stat, ownerOK := infoSysStat(info)
		if err != nil || !allowed || !info.Mode().IsRegular() ||
			!ownerOK || stat.Uid != pacmanDBLockOwnerUID {
			cleanup |= cancelCleanupPacmanCacheRetained
			continue
		}
		removable = append(removable, path)
	}
	if len(removable) == 0 {
		return cleanup | cancelCleanupPacmanCacheRetained
	}
	sort.Strings(removable)
	if err := removePacmanCacheFiles(removable); err != nil {
		cleanup |= cancelCleanupPacmanCacheRetained
	}
	for _, path := range removable {
		if pathExistsOrUnknown(path) {
			cleanup |= cancelCleanupPacmanCacheRetained
		} else {
			cleanup |= cancelCleanupPacmanCacheRemoved
		}
	}
	if changed {
		cleanup |= cancelCleanupPacmanCacheRetained
	}
	return cleanup
}

func infoSysStat(info os.FileInfo) (*syscall.Stat_t, bool) {
	if info == nil {
		return nil, false
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	return stat, ok
}

func packageManagerRunning() (bool, bool) {
	return anyProcProcess(func(_, _ int, name string, arguments []string) bool {
		_, ok := packageManagerCommands[name]
		return ok && managerCommandMutates(name, arguments)
	})
}

func scanManagerProcesses(ownerProcess int) managerProcessScan {
	scan := managerProcessScan{reliable: true}
	ownershipReliable := true
	processScanReliable := walkProcProcesses(func(pid, parent, group int, names, arguments []string) bool {
		for _, name := range names {
			_, packageManager := packageManagerCommands[name]
			_, aurManager := aurManagerCommands[name]
			_, miseManager := miseManagerCommands[name]
			if packageManager && !managerCommandMutates(name, arguments) {
				continue
			}
			owned, reliable := processBelongsToOwner(pid, parent, group, ownerProcess)
			ownershipReliable = ownershipReliable && reliable
			if owned {
				scan.ownedPacman = scan.ownedPacman || name == "pacman"
				scan.ownedAUR = scan.ownedAUR || aurManager
				scan.ownedMise = scan.ownedMise || miseManager
				continue
			}
			scan.foreignPacman = scan.foreignPacman || packageManager
			scan.foreignMise = scan.foreignMise || miseManager
		}
		return false
	})
	scan.reliable = processScanReliable && ownershipReliable
	return scan
}

func processBelongsToOwner(pid, parent, group, ownerProcess int) (bool, bool) {
	if ownerProcess <= 0 {
		return false, false
	}
	if pid == ownerProcess || parent == ownerProcess || group == ownerProcess {
		return true, true
	}

	seen := map[int]struct{}{pid: {}}
	for parent > 1 {
		if _, exists := seen[parent]; exists {
			return false, false
		}
		seen[parent] = struct{}{}
		nextParent, nextGroup, _, _, ok := procProcessIdentity(parent)
		if !ok {
			return false, false
		}
		if parent == ownerProcess || nextParent == ownerProcess || nextGroup == ownerProcess {
			return true, true
		}
		parent = nextParent
	}
	return false, true
}

func managerCommandMutates(name string, arguments []string) bool {
	if name != "pacman" {
		return true
	}
	if len(arguments) < 2 {
		return true
	}

	for _, argument := range arguments[1:] {
		switch argument {
		case "--query", "--files", "--deptest", "--help", "--version":
			return false
		case "--database", "--remove", "--sync", "--upgrade":
			return true
		}
		if len(argument) < 2 || argument[0] != '-' || argument == "--" {
			continue
		}
		options := strings.TrimLeft(argument, "-")
		if strings.ContainsAny(options, "DRSU") {
			return true
		}
		if strings.ContainsAny(options, "QFTVh") {
			return false
		}
	}
	return true
}

func anyProcProcess(matches func(pid, group int, name string, arguments []string) bool) (bool, bool) {
	found := false
	reliable := walkProcProcesses(func(pid, _, group int, names, arguments []string) bool {
		for _, name := range names {
			if matches(pid, group, name, arguments) {
				found = true
				return true
			}
		}
		return false
	})
	return found, reliable
}

func walkProcProcesses(visit func(pid, parent, group int, names, arguments []string) bool) bool {
	entries, err := os.ReadDir(procRoot)
	if err != nil {
		return false
	}
	reliable := true
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		parent, group, names, arguments, ok := procProcessIdentity(pid)
		if !ok {
			reliable = false
			continue
		}
		if visit(pid, parent, group, names, arguments) {
			return reliable
		}
	}
	return reliable
}

func processGroupRunning(processGroup int) (bool, bool) {
	if processGroup <= 0 {
		return false, false
	}
	entries, err := os.ReadDir(procRoot)
	if err != nil {
		return false, false
	}
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		process, exists, reliable := readProcProcessStat(pid)
		if !reliable {
			return false, false
		}
		if exists && process.group == processGroup && process.state != 'Z' {
			return true, true
		}
	}
	return false, true
}

func procProcessIdentity(pid int) (int, int, []string, []string, bool) {
	processDir := filepath.Join(procRoot, strconv.Itoa(pid))
	process, exists, reliable := readProcProcessStat(pid)
	if !reliable {
		return 0, 0, nil, nil, false
	}
	if !exists {
		return 0, 0, nil, nil, true
	}

	names := []string{process.name}
	var arguments []string
	cmdline, err := os.ReadFile(filepath.Join(processDir, "cmdline"))
	if err == nil {
		for _, argument := range strings.Split(string(cmdline), "\x00") {
			if argument != "" {
				arguments = append(arguments, argument)
			}
		}
		if len(arguments) > 0 {
			commandName := filepath.Base(arguments[0])
			if commandName != names[0] {
				names = append(names, commandName)
			}
		}
	}
	return process.parent, process.group, names, arguments, true
}

func readProcProcessStat(pid int) (procProcessStat, bool, bool) {
	stat, err := os.ReadFile(filepath.Join(procRoot, strconv.Itoa(pid), "stat"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return procProcessStat{}, false, true
		}
		return procProcessStat{}, false, false
	}
	statText := string(stat)
	openParen := strings.IndexByte(statText, '(')
	closeParen := strings.LastIndexByte(statText, ')')
	if openParen < 0 || closeParen <= openParen {
		return procProcessStat{}, true, false
	}
	fields := strings.Fields(statText[closeParen+1:])
	if len(fields) < 3 || len(fields[0]) != 1 {
		return procProcessStat{}, true, false
	}
	parent, err := strconv.Atoi(fields[1])
	if err != nil {
		return procProcessStat{}, true, false
	}
	group, err := strconv.Atoi(fields[2])
	if err != nil {
		return procProcessStat{}, true, false
	}
	return procProcessStat{
		name:   statText[openParen+1 : closeParen],
		state:  fields[0][0],
		parent: parent,
		group:  group,
	}, true, true
}

func cleanupCanceledPacmanLock(existedBefore bool, evidence managerEvidence) cancelCleanup {
	if existedBefore {
		return cancelCleanupNone
	}

	info, err := os.Lstat(pacmanDBLockPath)
	if errors.Is(err, os.ErrNotExist) {
		return cancelCleanupNone
	}
	if !evidence.exclusive() {
		return cancelCleanupPacmanLockRetained
	}
	packageManagerActive, processScanReliable := packageManagerStatus()
	if err != nil || !info.Mode().IsRegular() || info.Size() != 0 ||
		!processScanReliable || packageManagerActive {
		return cancelCleanupPacmanLockRetained
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); !ok ||
		stat.Uid != pacmanDBLockOwnerUID {
		return cancelCleanupPacmanLockRetained
	}
	if err := removePacmanDBLockFile(pacmanDBLockPath); err != nil {
		return cancelCleanupPacmanLockRetained
	}
	if pathExistsOrUnknown(pacmanDBLockPath) {
		return cancelCleanupPacmanLockRetained
	}
	return cancelCleanupPacmanLockRemoved
}

func removePacmanDBLockWithSudo(path string) error {
	if path != pacmanDBLockPath {
		return fmt.Errorf("refusing unexpected Pacman lock path")
	}
	cmd := exec.Command("sudo", "-n", "rm", "--", path)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run()
}

func removePacmanCacheFilesWithSudo(paths []string) error {
	if len(paths) == 0 {
		return nil
	}
	arguments := append([]string{"-n", "rm", "--"}, paths...)
	cmd := exec.Command("sudo", arguments...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run()
}

func removePacmanPackagesWithSudo(packages []string) error {
	if len(packages) == 0 {
		return nil
	}
	arguments := append([]string{"-n", "pacman", "-Rn", "--noconfirm", "--"}, packages...)
	cmd := exec.Command("sudo", arguments...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run()
}
