package main

import (
	"fmt"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestDomainPackagesDoNotOwnTUIPresentation(t *testing.T) {
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		err := filepath.WalkDir(entry.Name(), func(path string, entry fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if entry.IsDir() || filepath.Ext(path) != ".go" {
				return nil
			}
			parsed, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
			if err != nil {
				return fmt.Errorf("parse %s: %w", path, err)
			}
			for _, imported := range parsed.Imports {
				name, err := strconv.Unquote(imported.Path.Value)
				if err != nil {
					return fmt.Errorf("unquote import in %s: %w", path, err)
				}
				if strings.Contains(name, "bubbletea") || strings.Contains(name, "lipgloss") {
					return fmt.Errorf(
						"%s imports presentation library %q; shared UI belongs at qv/tui root",
						path,
						name,
					)
				}
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}
