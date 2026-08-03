package main

import (
	"os"
	"path/filepath"
	"strings"
)

func resolveUserPath(value string) (string, error) {
	if strings.HasPrefix(value, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		value = filepath.Join(home, strings.TrimPrefix(value, "~/"))
	}
	if !filepath.IsAbs(value) {
		wd, err := os.Getwd()
		if err != nil {
			return "", err
		}
		value = filepath.Join(wd, value)
	}
	return filepath.Clean(value), nil
}

func omarchySourcePath() string {
	if configured := strings.TrimSpace(os.Getenv("OMARCHY_PATH")); configured != "" {
		if path, err := resolveUserPath(configured); err == nil {
			return path
		}
	}

	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	return filepath.Join(home, ".local", "share", "omarchy")
}
