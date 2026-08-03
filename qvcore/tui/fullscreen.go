package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
)

type fullscreenStateMsg struct {
	fullscreen bool
}

type hyprlandClientState struct {
	PID        int `json:"pid"`
	Fullscreen int `json:"fullscreen"`
}

const fullscreenDetectionTimeout = 500 * time.Millisecond

func detectFullscreenCmd() tea.Cmd {
	return func() tea.Msg {
		if os.Getenv("QVOS_TUI_FULLSCREEN") == "1" {
			return fullscreenStateMsg{fullscreen: true}
		}
		if os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") == "" {
			return fullscreenStateMsg{}
		}

		ctx, cancel := context.WithTimeout(context.Background(), fullscreenDetectionTimeout)
		defer cancel()
		output, err := exec.CommandContext(ctx, "hyprctl", "-j", "clients").Output()
		if err != nil {
			return fullscreenStateMsg{}
		}
		fullscreen, err := fullscreenFromHyprlandClients(output, ancestorProcessIDs(os.Getpid()))
		if err != nil {
			return fullscreenStateMsg{}
		}
		return fullscreenStateMsg{fullscreen: fullscreen}
	}
}

func fullscreenFromHyprlandClients(data []byte, processIDs map[int]struct{}) (bool, error) {
	var clients []hyprlandClientState
	if err := json.Unmarshal(data, &clients); err != nil {
		return false, err
	}
	for _, client := range clients {
		if _, ok := processIDs[client.PID]; ok {
			return client.Fullscreen > 0, nil
		}
	}
	return false, nil
}

func ancestorProcessIDs(pid int) map[int]struct{} {
	processIDs := make(map[int]struct{})
	for range 32 {
		if pid < 1 {
			break
		}
		if _, seen := processIDs[pid]; seen {
			break
		}
		processIDs[pid] = struct{}{}

		parent, err := parentProcessID(pid)
		if err != nil || parent == pid {
			break
		}
		pid = parent
	}
	return processIDs
}

func parentProcessID(pid int) (int, error) {
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return 0, err
	}
	stat := string(data)
	end := strings.LastIndexByte(stat, ')')
	if end < 0 {
		return 0, fmt.Errorf("invalid process stat")
	}
	fields := strings.Fields(stat[end+1:])
	if len(fields) < 2 {
		return 0, fmt.Errorf("invalid process stat fields")
	}
	return strconv.Atoi(fields[1])
}
