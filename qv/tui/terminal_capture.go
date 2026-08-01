package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/charmbracelet/x/ansi"
	"golang.org/x/sys/unix"
)

const (
	defaultCapturedTerminalWidth  = 120
	defaultCapturedTerminalHeight = 40
	capturedTerminalDrainGrace    = time.Second
	capturedTerminalPreviewEvery  = 50 * time.Millisecond
)

type capturedTerminal struct {
	master *os.File
	slave  *os.File
}

func openCapturedTerminal() (*capturedTerminal, error) {
	master, err := os.OpenFile("/dev/ptmx", os.O_RDWR|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open terminal multiplexer: %w", err)
	}
	closeMaster := true
	defer func() {
		if closeMaster {
			_ = master.Close()
		}
	}()

	terminalNumber, err := unix.IoctlGetInt(int(master.Fd()), unix.TIOCGPTN)
	if err != nil {
		return nil, fmt.Errorf("resolve terminal: %w", err)
	}
	if err := unix.IoctlSetPointerInt(int(master.Fd()), unix.TIOCSPTLCK, 0); err != nil {
		return nil, fmt.Errorf("unlock terminal: %w", err)
	}

	slavePath := filepath.Join("/dev/pts", fmt.Sprintf("%d", terminalNumber))
	slave, err := os.OpenFile(slavePath, os.O_RDWR|unix.O_NOCTTY|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open terminal: %w", err)
	}
	closeSlave := true
	defer func() {
		if closeSlave {
			_ = slave.Close()
		}
	}()
	width, height := capturedTerminalSize()
	window := &unix.Winsize{Col: uint16(width), Row: uint16(height)}
	if err := unix.IoctlSetWinsize(int(slave.Fd()), unix.TIOCSWINSZ, window); err != nil {
		return nil, fmt.Errorf("size terminal: %w", err)
	}

	closeMaster = false
	closeSlave = false
	return &capturedTerminal{master: master, slave: slave}, nil
}

func capturedTerminalSize() (int, int) {
	for _, file := range []*os.File{os.Stdout, os.Stderr, os.Stdin} {
		window, err := unix.IoctlGetWinsize(int(file.Fd()), unix.TIOCGWINSZ)
		if err == nil && window.Col > 0 && window.Row > 0 {
			return int(window.Col), int(window.Row)
		}
	}
	return defaultCapturedTerminalWidth, defaultCapturedTerminalHeight
}

func (terminal *capturedTerminal) attach(cmd *exec.Cmd) {
	cmd.Stdout = terminal.slave
	cmd.Stderr = terminal.slave
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid:   true,
		Pdeathsig: syscall.SIGTERM,
	}
}

func (terminal *capturedTerminal) closeSlave() {
	if terminal == nil || terminal.slave == nil {
		return
	}
	_ = terminal.slave.Close()
	terminal.slave = nil
}

func (terminal *capturedTerminal) close() {
	if terminal == nil {
		return
	}
	terminal.closeSlave()
	terminal.closeMaster()
}

func (terminal *capturedTerminal) closeMaster() {
	if terminal == nil || terminal.master == nil {
		return
	}
	_ = terminal.master.Close()
	terminal.master = nil
}

func (terminal *capturedTerminal) interrupt(processID int) error {
	return interruptOwnedProcessGroup(processID)
}

type terminalFrame struct {
	line   string
	update bool
	redraw bool
	commit bool
	move   int
	clear  bool
}

type capturedTerminalScreen struct {
	parser        *ansi.Parser
	lines         [][]rune
	row           int
	column        int
	savedRow      int
	savedColumn   int
	dirty         bool
	lastPreviewAt time.Time
	yield         func(terminalFrame) error
	err           error
}

func newCapturedTerminalScreen(yield func(terminalFrame) error) *capturedTerminalScreen {
	screen := &capturedTerminalScreen{
		lines: make([][]rune, 1),
		yield: yield,
	}
	parser := ansi.NewParser()
	parser.SetHandler(ansi.Handler{
		Print:     screen.printRune,
		Execute:   screen.execute,
		HandleCsi: screen.handleCSI,
		HandleEsc: screen.handleEscape,
	})
	screen.parser = parser
	return screen
}

func (screen *capturedTerminalScreen) emit(frame terminalFrame) {
	if screen.err != nil {
		return
	}
	screen.err = screen.yield(frame)
}

func (screen *capturedTerminalScreen) ensureRow(row int) {
	for len(screen.lines) <= row {
		screen.lines = append(screen.lines, nil)
	}
}

func (screen *capturedTerminalScreen) currentLine() string {
	screen.ensureRow(screen.row)
	return strings.TrimRight(string(screen.lines[screen.row]), " ")
}

func (screen *capturedTerminalScreen) emitCurrent(commit bool) {
	screen.emit(terminalFrame{
		line:   screen.currentLine(),
		update: true,
		redraw: !commit,
		commit: commit,
	})
	screen.dirty = false
	screen.lastPreviewAt = time.Now()
}

func (screen *capturedTerminalScreen) flushPreview(force bool) {
	if !screen.dirty || screen.err != nil {
		return
	}
	if !force && !screen.lastPreviewAt.IsZero() &&
		time.Since(screen.lastPreviewAt) < capturedTerminalPreviewEvery {
		return
	}
	screen.emitCurrent(false)
}

func (screen *capturedTerminalScreen) moveRows(delta int) {
	if delta == 0 {
		return
	}
	screen.flushPreview(true)
	target := max(0, screen.row+delta)
	actual := target - screen.row
	if actual == 0 {
		return
	}
	screen.row = target
	screen.ensureRow(screen.row)
	screen.emit(terminalFrame{move: actual})
}

func (screen *capturedTerminalScreen) printRune(character rune) {
	screen.ensureRow(screen.row)
	line := screen.lines[screen.row]
	for len(line) < screen.column {
		line = append(line, ' ')
	}
	if screen.column < len(line) {
		line[screen.column] = character
	} else {
		line = append(line, character)
	}
	screen.lines[screen.row] = line
	screen.column++
	screen.dirty = true
}

func (screen *capturedTerminalScreen) execute(character byte) {
	switch character {
	case '\r':
		screen.column = 0
	case '\n':
		screen.emitCurrent(true)
		screen.row++
		screen.column = 0
		screen.ensureRow(screen.row)
	case '\b':
		screen.column = max(0, screen.column-1)
	case '\t':
		next := (screen.column/8 + 1) * 8
		for screen.column < next {
			screen.printRune(' ')
		}
	}
}

func terminalParameter(params ansi.Params, index, fallback int) int {
	value, _, ok := params.Param(index, fallback)
	if !ok || value < 1 {
		return fallback
	}
	return value
}

func (screen *capturedTerminalScreen) eraseLine(mode int) {
	screen.ensureRow(screen.row)
	line := screen.lines[screen.row]
	switch mode {
	case 1:
		limit := min(len(line), screen.column+1)
		for index := 0; index < limit; index++ {
			line[index] = ' '
		}
	case 2:
		line = nil
	default:
		if screen.column < len(line) {
			line = line[:screen.column]
		}
	}
	screen.lines[screen.row] = line
	screen.dirty = true
}

func (screen *capturedTerminalScreen) clearScreen() {
	screen.lines = make([][]rune, 1)
	screen.row = 0
	screen.column = 0
	screen.dirty = false
	screen.emit(terminalFrame{clear: true})
}

func (screen *capturedTerminalScreen) handleCSI(command ansi.Cmd, params ansi.Params) {
	switch command.Final() {
	case 'A':
		screen.moveRows(-terminalParameter(params, 0, 1))
	case 'B':
		screen.moveRows(terminalParameter(params, 0, 1))
	case 'C':
		screen.column += terminalParameter(params, 0, 1)
	case 'D':
		screen.column = max(0, screen.column-terminalParameter(params, 0, 1))
	case 'E':
		screen.moveRows(terminalParameter(params, 0, 1))
		screen.column = 0
	case 'F':
		screen.moveRows(-terminalParameter(params, 0, 1))
		screen.column = 0
	case 'G', '`':
		screen.column = terminalParameter(params, 0, 1) - 1
	case 'H', 'f':
		targetRow := terminalParameter(params, 0, 1) - 1
		screen.moveRows(targetRow - screen.row)
		screen.column = terminalParameter(params, 1, 1) - 1
	case 'J':
		mode, _, _ := params.Param(0, 0)
		if mode == 2 || mode == 3 {
			screen.clearScreen()
		}
	case 'K':
		mode, _, _ := params.Param(0, 0)
		screen.eraseLine(mode)
	case 'd':
		targetRow := terminalParameter(params, 0, 1) - 1
		screen.moveRows(targetRow - screen.row)
	case 's':
		screen.savedRow = screen.row
		screen.savedColumn = screen.column
	case 'u':
		screen.moveRows(screen.savedRow - screen.row)
		screen.column = screen.savedColumn
	}
}

func (screen *capturedTerminalScreen) handleEscape(command ansi.Cmd) {
	switch command.Final() {
	case 'D':
		screen.moveRows(1)
	case 'M':
		screen.moveRows(-1)
	case '7':
		screen.savedRow = screen.row
		screen.savedColumn = screen.column
	case '8':
		screen.moveRows(screen.savedRow - screen.row)
		screen.column = screen.savedColumn
	case 'c':
		screen.clearScreen()
	}
}

func readTerminalFrames(reader io.Reader, yield func(terminalFrame) error) error {
	buffer := make([]byte, 32*1024)
	screen := newCapturedTerminalScreen(yield)
	for {
		count, readErr := reader.Read(buffer)
		for _, character := range buffer[:count] {
			screen.parser.Advance(character)
			if screen.err != nil {
				return screen.err
			}
		}
		screen.flushPreview(false)
		if screen.err != nil {
			return screen.err
		}

		if readErr == nil {
			continue
		}
		screen.flushPreview(true)
		if screen.err != nil {
			return screen.err
		}
		if errors.Is(readErr, io.EOF) || errors.Is(readErr, syscall.EIO) {
			return nil
		}
		return readErr
	}
}
