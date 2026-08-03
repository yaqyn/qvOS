package main

import (
	"runtime"
	"testing"
)

func TestModelRendererAllocationBudget(t *testing.T) {
	previousWidth, previousHeight := canvasW, canvasH
	canvasW, canvasH = maxCanvasW, maxCanvasW/2
	t.Cleanup(func() {
		canvasW, canvasH = previousWidth, previousHeight
	})

	shapes := []struct {
		name   string
		render func(int) string
	}{
		{"bloom", renderBloom},
		{"knot", renderKnot},
		{"hopf", renderHopf},
		{"torus", renderTorus},
	}
	for _, shape := range shapes {
		t.Run(shape.name, func(t *testing.T) {
			frame := 0
			allocations := testing.AllocsPerRun(5, func() {
				frame++
				rendered := shape.render(frame)
				runtime.KeepAlive(rendered)
			})
			if allocations > 32 {
				t.Fatalf("renderer allocations = %.0f, want at most 32", allocations)
			}
		})
	}
}

func BenchmarkRenderShapes(b *testing.B) {
	shapes := []struct {
		name   string
		render func(int) string
	}{
		{"bloom", renderBloom},
		{"knot", renderKnot},
		{"hopf", renderHopf},
		{"torus", renderTorus},
	}

	previousWidth, previousHeight := canvasW, canvasH
	canvasW, canvasH = maxCanvasW, maxCanvasW/2
	b.Cleanup(func() {
		canvasW, canvasH = previousWidth, previousHeight
	})

	for _, shape := range shapes {
		b.Run(shape.name, func(b *testing.B) {
			outputBytes := len(shape.render(0))
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				rendered := shape.render(i)
				runtime.KeepAlive(rendered)
			}
			b.ReportMetric(float64(outputBytes), "output-B")
		})
	}
}

func BenchmarkHubView(b *testing.B) {
	sizes := []struct {
		name          string
		width, height int
		fullscreen    bool
	}{
		{"side_without_model", 156, 20, false},
		{"side_with_model", 156, 24, false},
		{"centered_square", 98, 40, false},
		{"fullscreen_cinematic", 270, 61, true},
	}

	for _, size := range sizes {
		b.Run(size.name, func(b *testing.B) {
			m := model{
				width:      size.width,
				height:     size.height,
				fullscreen: size.fullscreen,
			}
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				m.frame = i
				view := m.View()
				runtime.KeepAlive(view.Content)
			}
		})
	}
}
