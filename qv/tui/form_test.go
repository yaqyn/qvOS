package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	actionflow "github.com/Yaqyn-qvOS/qvOS/action"
)

func TestActionFormSchemaIsBoundedAndTyped(t *testing.T) {
	schema, err := parseActionForm([]byte(`{
  "title":"Configure Windows VM",
  "fields":[
    {"key":"ram","label":"Memory","kind":"select","value":"4G","options":["2G","4G"]},
    {"key":"cpus","label":"CPU cores","kind":"number","value":"2","min":1,"max":8},
    {"key":"username","label":"Windows user","kind":"input","value":"docker","max_length":32},
    {"key":"password","label":"Windows password","kind":"password","value":"","max_length":64}
  ]
}`))
	if err != nil || len(schema.Fields) != 4 || schema.Fields[0].MaxLength != 64 {
		t.Fatalf("valid action form = %#v, %v", schema, err)
	}

	for _, invalid := range []string{
		`{"title":"","fields":[]}`,
		`{"title":"Test","fields":[{"key":"Bad-Key","label":"Bad","kind":"input","value":""}]}`,
		`{"title":"Test","fields":[{"key":"mode","label":"Mode","kind":"select","value":"missing","options":["safe"]}]}`,
		`{"title":"Test","fields":[{"key":"count","label":"Count","kind":"number","value":"9","min":1,"max":8}]}`,
		`{"title":"Test","fields":[{"key":"secret","label":"Secret","kind":"password","value":"","extra":true}]}`,
	} {
		if _, err := parseActionForm([]byte(invalid)); err == nil {
			t.Fatalf("invalid form passed: %s", invalid)
		}
	}
}

func TestActionFormCompletesBeforeAuthorizationAndMasksPassword(t *testing.T) {
	previous := currentActionSpec
	t.Cleanup(func() { currentActionSpec = previous })
	currentActionSpec = actionflow.Spec{
		Slug:         "windows",
		Operation:    "install",
		Title:        "Windows",
		Summary:      "Configure Windows",
		RequiresSudo: true,
		Rings:        2,
		FormProtocol: "owner-json-v1",
	}
	m := model{
		width:      120,
		height:     42,
		loading:    true,
		action:     actionGeneric,
		scriptPath: filepath.Join(t.TempDir(), "windows-action"),
		formActive: true,
		formTitle:  "Configure Windows VM",
		formCursor: 1,
		formFields: []actionFormField{
			{Key: "ram", Label: "Memory", Kind: "select", Value: "4G", Options: []string{"2G", "4G"}, MaxLength: 64},
			{Key: "password", Label: "Windows password", Kind: "password", Value: "private-pass", MaxLength: 64},
		},
	}

	content := stripANSI(m.renderActionFormFor(layoutDesktop))
	if strings.Contains(content, "private-pass") || !strings.Contains(content, "••••••••••••") {
		t.Fatalf("password form was not masked: %q", content)
	}
	next, command := m.handleActionFormKey(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	if command != nil || m.formActive || !m.formComplete || !m.sudoPrompt {
		t.Fatalf("form did not lead directly to authorization: %#v", m)
	}
}

func TestActionFormUsesOneCompactValueColumn(t *testing.T) {
	previousWidth := canvasW
	canvasW = 48
	t.Cleanup(func() { canvasW = previousWidth })

	m := model{
		formTitle:  "Configure Windows VM",
		formCursor: 2,
		formFields: []actionFormField{
			{Key: "ram", Label: "Memory", Kind: "select", Value: "4G", Options: []string{"2G", "4G"}},
			{Key: "cpu", Label: "CPU cores", Kind: "number", Value: "2", Minimum: 1, Maximum: 8},
			{Key: "disk", Label: "Virtual disk", Kind: "select", Value: "64G", Options: []string{"64G", "128G"}},
			{Key: "username", Label: "Windows user", Kind: "input", Value: "docker"},
			{Key: "password", Label: "Windows password", Kind: "password", Value: "private-pass"},
		},
	}

	rendered := m.renderActionFormFor(layoutDesktop)
	content := stripANSI(rendered)
	if strings.ContainsAny(content, "‹›") {
		t.Fatalf("form selectors retained angle marks: %q", content)
	}
	starts := make([]int, 0, len(m.formFields))
	for _, match := range []string{"4G", "2", "64G", "docker", "••••••••••••"} {
		for _, line := range strings.Split(content, "\n") {
			if start := strings.Index(line, match); start >= 0 {
				starts = append(starts, lipgloss.Width(line[:start]))
				break
			}
		}
	}
	if len(starts) != len(m.formFields) {
		t.Fatalf("form values missing from render: %q", content)
	}
	for _, start := range starts[1:] {
		if start != starts[0] {
			t.Fatalf("form values do not share a column: starts=%v\n%s", starts, content)
		}
	}
	activeLine := ""
	for _, line := range strings.Split(content, "\n") {
		if strings.Contains(line, "64G") {
			activeLine = line
			break
		}
	}
	if !strings.Contains(activeLine, "• Virtual disk") {
		t.Fatalf("active marker is not beside the label column: %q", activeLine)
	}
	passwordLine := ""
	for _, line := range strings.Split(content, "\n") {
		if strings.Contains(line, "Windows password") {
			passwordLine = line
			break
		}
	}
	labelStart := strings.Index(passwordLine, "Windows password")
	valueStart := strings.Index(passwordLine, "••••••••••••")
	if labelStart < 0 || valueStart < 0 ||
		valueStart-(labelStart+lipgloss.Width("Windows password")) != 4 {
		t.Fatalf("form columns do not use the wider gap: %q", passwordLine)
	}
	if !strings.Contains(rendered, sRed.Render("docker")) ||
		!strings.Contains(rendered, sRed.Render("••••••••••••")) {
		t.Fatalf("editable values do not use the accent style: %q", rendered)
	}
}

func TestActionFormNumberUsesBoundedArrowSelection(t *testing.T) {
	m := model{
		formActive: true,
		formFields: []actionFormField{
			{Key: "cpu", Label: "CPU cores", Kind: "number", Value: "2", Minimum: 1, Maximum: 3},
		},
	}

	next, _ := m.handleActionFormKey(tea.KeyPressMsg{Code: '9', Text: "9"})
	m = next.(model)
	if m.formFields[0].Value != "2" {
		t.Fatalf("number field accepted typed text: %#v", m.formFields[0])
	}
	next, _ = m.handleActionFormKey(tea.KeyPressMsg{Code: tea.KeyRight})
	m = next.(model)
	next, _ = m.handleActionFormKey(tea.KeyPressMsg{Code: tea.KeyRight})
	m = next.(model)
	if m.formFields[0].Value != "3" {
		t.Fatalf("number field exceeded its maximum: %#v", m.formFields[0])
	}
	next, _ = m.handleActionFormKey(tea.KeyPressMsg{Code: tea.KeyLeft})
	m = next.(model)
	if m.formFields[0].Value != "2" {
		t.Fatalf("number field did not decrement: %#v", m.formFields[0])
	}
}

func TestActionFormValuesUsePrivateCapturedFile(t *testing.T) {
	runtimeDir := t.TempDir()
	resultDir := t.TempDir()
	resultPath := filepath.Join(resultDir, "result")
	script := filepath.Join(t.TempDir(), "action")
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	t.Setenv("QVOS_TEST_FORM_RESULT", resultPath)
	if err := os.WriteFile(script, []byte(`#!/bin/bash
{
  stat -c '%a' "$QVOS_ACTION_FORM_VALUES"
  jq -r '.username' "$QVOS_ACTION_FORM_VALUES"
  jq -r '.password' "$QVOS_ACTION_FORM_VALUES"
} >"$QVOS_TEST_FORM_RESULT"
`), 0o700); err != nil {
		t.Fatal(err)
	}

	events := make(chan scriptEvent, 32)
	go runRootScriptStream(
		context.Background(),
		actionGeneric,
		script,
		nil,
		"",
		events,
		map[string]string{"username": "docker", "password": "private-pass"},
	)
	for event := range events {
		if event.done && event.err != nil {
			t.Fatalf("form action failed: %v", event.err)
		}
	}
	result, err := os.ReadFile(resultPath)
	if err != nil || string(result) != "600\ndocker\nprivate-pass\n" {
		t.Fatalf("private form result = %q, %v", result, err)
	}
	runs, err := filepath.Glob(filepath.Join(runtimeDir, "qvos-tui-run-*"))
	if err != nil || len(runs) != 0 {
		t.Fatalf("captured form residue = %v, %v", runs, err)
	}
}
