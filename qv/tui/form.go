package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"unicode"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

const (
	actionFormMaxFields  = 8
	actionFormMaxOptions = 12
	actionFormValueWidth = 20
)

type actionFormSchema struct {
	Title  string            `json:"title"`
	Fields []actionFormField `json:"fields"`
}

type actionFormField struct {
	Key       string   `json:"key"`
	Label     string   `json:"label"`
	Kind      string   `json:"kind"`
	Value     string   `json:"value"`
	Options   []string `json:"options,omitempty"`
	MinLength int      `json:"min_length,omitempty"`
	MaxLength int      `json:"max_length,omitempty"`
	Minimum   int      `json:"min,omitempty"`
	Maximum   int      `json:"max,omitempty"`
}

type actionFormLoadedMsg struct {
	action actionMode
	script string
	schema actionFormSchema
	err    error
}

func loadActionFormCmd(action actionMode, script string) tea.Cmd {
	return func() tea.Msg {
		if action != actionGeneric {
			return actionFormLoadedMsg{
				action: action,
				script: script,
				err:    fmt.Errorf("action %d does not support forms", action),
			}
		}

		cmd := exec.Command("/bin/bash", script, "--form")
		cmd.Env = os.Environ()
		output, err := cmd.CombinedOutput()
		if err != nil {
			message := strings.Join(strings.Fields(string(output)), " ")
			if message == "" {
				message = err.Error()
			}
			return actionFormLoadedMsg{
				action: action,
				script: script,
				err:    fmt.Errorf("%s", message),
			}
		}

		schema, err := parseActionForm(output)
		return actionFormLoadedMsg{action: action, script: script, schema: schema, err: err}
	}
}

func parseActionForm(output []byte) (actionFormSchema, error) {
	var schema actionFormSchema
	decoder := json.NewDecoder(strings.NewReader(string(output)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&schema); err != nil {
		return actionFormSchema{}, fmt.Errorf("invalid action form: %w", err)
	}
	if strings.TrimSpace(schema.Title) == "" || unsafeFormText(schema.Title) ||
		len(schema.Fields) == 0 || len(schema.Fields) > actionFormMaxFields {
		return actionFormSchema{}, fmt.Errorf("invalid action form schema")
	}

	seen := make(map[string]bool, len(schema.Fields))
	for index := range schema.Fields {
		field := &schema.Fields[index]
		if !validFormKey(field.Key) || seen[field.Key] ||
			strings.TrimSpace(field.Label) == "" || unsafeFormText(field.Label) {
			return actionFormSchema{}, fmt.Errorf("invalid action form field")
		}
		seen[field.Key] = true
		if field.MaxLength == 0 {
			field.MaxLength = 64
		}
		if field.MinLength == 0 {
			field.MinLength = 1
		}
		if field.MinLength < 1 || field.MinLength > field.MaxLength ||
			field.MaxLength > 256 ||
			len([]rune(field.Value)) > field.MaxLength || unsafeFormText(field.Value) {
			return actionFormSchema{}, fmt.Errorf("invalid action form value")
		}

		switch field.Kind {
		case "input", "password":
			if len(field.Options) != 0 {
				return actionFormSchema{}, fmt.Errorf("text action form field has options")
			}
		case "select":
			if len(field.Options) == 0 || len(field.Options) > actionFormMaxOptions {
				return actionFormSchema{}, fmt.Errorf("invalid action form options")
			}
			found := false
			optionSeen := make(map[string]bool, len(field.Options))
			for _, option := range field.Options {
				if strings.TrimSpace(option) == "" || unsafeFormText(option) || optionSeen[option] {
					return actionFormSchema{}, fmt.Errorf("invalid action form option")
				}
				optionSeen[option] = true
				found = found || option == field.Value
			}
			if !found {
				return actionFormSchema{}, fmt.Errorf("action form default is not an option")
			}
		case "number":
			value, err := strconv.Atoi(field.Value)
			if len(field.Options) != 0 || err != nil ||
				field.Minimum < 1 || field.Maximum < field.Minimum || field.Maximum > 1024 ||
				value < field.Minimum || value > field.Maximum {
				return actionFormSchema{}, fmt.Errorf("invalid action form number")
			}
		default:
			return actionFormSchema{}, fmt.Errorf("invalid action form field kind")
		}
	}
	return schema, nil
}

func validFormKey(value string) bool {
	if value == "" {
		return false
	}
	for index, r := range value {
		if (r >= 'a' && r <= 'z') || (index > 0 && (r == '_' || (r >= '0' && r <= '9'))) {
			continue
		}
		return false
	}
	return true
}

func unsafeFormText(value string) bool {
	return strings.ContainsAny(value, "\r\n") || strings.IndexFunc(value, unicode.IsControl) >= 0
}

func (m *model) resetActionForm() {
	m.formLoading = false
	m.formActive = false
	m.formComplete = false
	m.formTitle = ""
	for index := range m.formFields {
		m.formFields[index].Value = ""
	}
	m.formFields = nil
	m.formCursor = 0
	m.formErr = ""
}

func (m model) actionFormValues() map[string]string {
	values := make(map[string]string, len(m.formFields))
	for _, field := range m.formFields {
		values[field.Key] = field.Value
	}
	return values
}

func (m model) handleActionFormKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if len(m.formFields) == 0 {
		return m.cancelRootAction()
	}

	field := &m.formFields[m.formCursor]
	switch msg.String() {
	case "esc", "ctrl+c", "ctrl+z":
		return m.cancelRootAction()
	case "up":
		if m.formCursor > 0 {
			m.formCursor--
		}
	case "down", "tab":
		if m.formCursor < len(m.formFields)-1 {
			m.formCursor++
		}
	case "left":
		m.moveActionFormValue(-1)
	case "right":
		m.moveActionFormValue(1)
	case "backspace", "ctrl+h":
		if field.Kind != "select" && field.Kind != "number" && len([]rune(field.Value)) > 0 {
			value := []rune(field.Value)
			value[len(value)-1] = 0
			field.Value = string(value[:len(value)-1])
			m.formErr = ""
		}
	case "ctrl+u":
		if field.Kind != "select" && field.Kind != "number" {
			field.Value = ""
			m.formErr = ""
		}
	case "enter":
		if len([]rune(field.Value)) < field.MinLength {
			m.formErr = actionFormLengthError(*field)
			return m, nil
		}
		if m.formCursor < len(m.formFields)-1 {
			m.formCursor++
			m.formErr = ""
			return m, nil
		}
		return m.completeActionForm()
	default:
		if field.Kind != "select" && field.Kind != "number" {
			text := msg.Key().Text
			if text != "" && !unsafeFormText(text) &&
				len([]rune(field.Value+text)) <= field.MaxLength {
				field.Value += text
				m.formErr = ""
			}
		}
	}
	return m, nil
}

func (m *model) moveActionFormValue(direction int) {
	field := &m.formFields[m.formCursor]
	if field.Kind == "number" {
		current, err := strconv.Atoi(field.Value)
		if err != nil {
			return
		}
		field.Value = strconv.Itoa(min(field.Maximum, max(field.Minimum, current+direction)))
		m.formErr = ""
		return
	}
	if field.Kind != "select" || len(field.Options) == 0 {
		return
	}
	current := 0
	for index, option := range field.Options {
		if option == field.Value {
			current = index
			break
		}
	}
	current = (current + direction + len(field.Options)) % len(field.Options)
	field.Value = field.Options[current]
	m.formErr = ""
}

func (m model) completeActionForm() (model, tea.Cmd) {
	for _, field := range m.formFields {
		if len([]rune(field.Value)) < field.MinLength {
			m.formErr = actionFormLengthError(field)
			return m, nil
		}
	}
	m.formActive = false
	m.formComplete = true
	m.formErr = ""
	return m.continueRootActionFlow()
}

func actionFormLengthError(field actionFormField) string {
	if field.MinLength <= 1 {
		return field.Label + " is required"
	}
	return fmt.Sprintf("%s needs at least %d characters", field.Label, field.MinLength)
}

func (m model) renderActionFormFor(mode layoutMode) string {
	title := centerCanvas(sWhite.Render(strings.ToUpper(m.formTitle)))
	labelWidth := 0
	for _, field := range m.formFields {
		labelWidth = max(labelWidth, lipgloss.Width(field.Label))
	}
	valueWidth := min(actionFormValueWidth, max(12, canvasW-labelWidth-6))
	gridWidth := 6 + labelWidth + valueWidth
	rows := make([]string, 0, len(m.formFields))
	for index, field := range m.formFields {
		active := index == m.formCursor
		marker := sDim.Render("  ")
		labelStyle := sMid
		valueStyle := sGray
		if field.Kind == "input" || field.Kind == "password" {
			valueStyle = sRed
		}
		if active {
			marker = sRed.Render("• ")
			labelStyle = sWhite
			if field.Kind != "input" && field.Kind != "password" {
				valueStyle = sWhite
			}
		}
		label := lipgloss.PlaceHorizontal(labelWidth, lipgloss.Left, labelStyle.Render(field.Label))
		value := trimDisplay(field.Value, valueWidth)
		alignment := lipgloss.Left
		if field.Kind == "password" {
			value = strings.Repeat("•", len([]rune(field.Value)))
			value = trimDisplay(value, valueWidth)
		}
		value = lipgloss.PlaceHorizontal(valueWidth, alignment, valueStyle.Render(value))
		rows = append(rows, marker+label+sDim.Render("    ")+value)
	}
	rows = centerLinesWithWidth(rows, gridWidth)

	lines := []string{title, ""}
	lines = append(lines, rows...)
	if m.formErr != "" {
		lines = append(lines, "", centerCanvas(sRed.Render(m.formErr)))
	}
	return appendTUIHints(strings.Join(lines, "\n"), canvasW, m.rootPersistentHints()...)
}
