package main

import "testing"

func TestFullscreenStateMatchesTheTerminalProcessTree(t *testing.T) {
	data := []byte(`[
		{"pid": 120, "fullscreen": 0},
		{"pid": 240, "fullscreen": 2}
	]`)

	fullscreen, err := fullscreenFromHyprlandClients(data, map[int]struct{}{240: {}})
	if err != nil {
		t.Fatal(err)
	}
	if !fullscreen {
		t.Fatal("fullscreen terminal ancestor was not detected")
	}

	fullscreen, err = fullscreenFromHyprlandClients(data, map[int]struct{}{120: {}})
	if err != nil {
		t.Fatal(err)
	}
	if fullscreen {
		t.Fatal("floating terminal ancestor was reported as fullscreen")
	}
}
