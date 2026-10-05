// Package hub owns the public hub's read-only content. Presentation and
// navigation belong to the shared TUI information flow.
package hub

type Page struct {
	Title string
	Lines []string
}

func Information(action string) Page {
	switch action {
	case "qvos.about.creator":
		return Page{Title: "Developer", Lines: []string{
			"Name: Abdulrahman M. Yaqyn",
			"Website: https://yaqyn.dev",
			"I’m Abdulrahman M. Yaqyn, the developer behind qvOS. My work brings together Linux system development and interface design, from the desktop experience to the tools that install, configure, and maintain it.",
			"With qvOS, I’m building a standalone Arch Linux distribution with a consistent identity and clear ownership of its components. The project covers native commands, terminal interfaces, desktop integration, and a verified installation and release workflow.",
			"Explore my portfolio at yaqyn.dev, or follow qvOS development and its source code on GitHub.",
		}}
	case "qvos.about.project":
		return Page{Title: "About qvOS", Lines: []string{
			"Project: qvOS",
			"Base: Arch Linux",
			"Source: https://github.com/yaqyn/qvOS",
			"A standalone Arch Linux distribution with its own desktop, command system, and installation experience.",
			"Build an installation image from source, or download a verified release when available.",
		}}
	case "qvos.iso.download":
		return Page{Title: "Download qvOS", Lines: []string{
			"No verified ISO is available yet.",
			"Check back for the latest working-confirmed release.",
		}}
	default:
		return Page{}
	}
}
