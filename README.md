![qvOS System — animated red and grayscale pixel gradient](docs/readme/cover.gif)

# qvOS

**Standalone Arch Linux. Hyprland desktop. Native system tools.**

Developed by [Abdulrahman M. Yaqyn](https://yaqyn.dev), qvOS combines a
keyboard-first desktop with its own installer, command system, and recovery
workflow.

## <img src="docs/readme/icons/start.svg" width="24" height="24" alt=""> Get qvOS

![Start section](docs/readme/sections/start.png)

```sh
curl -fsSL qvos.yaqyn.dev | sh
```

Opens the **compiled terminal launcher** on Linux x86_64. Choose **Build** to
create an ISO, or explore **About → Developer / Project**. Requires `curl`,
`tar`, and `sha256sum`; the download is checksum-verified.

**ISO Download is not available yet.** It will be enabled when a release passes
the installation and lifecycle checks.

## <img src="docs/readme/icons/desktop.svg" width="24" height="24" alt=""> Desktop

![Desktop section](docs/readme/sections/desktop.png)

- **Hyprland** — Wayland window management and keyboard controls.
- **Waybar** — workspaces and system status.
- **Walker + Elephant** — application launching and search.
- Native controls for monitors, audio, brightness, power, lock, and idle behavior.

## <img src="docs/readme/icons/wallpaper.svg" width="24" height="24" alt=""> Wallpaper & appearance

![Wallpaper section](docs/readme/sections/wallpaper.png)

![The bundled qvOS wallpaper: official white wordmark on solid charcoal](qvcore/theme/yaqyn/preview.png)

The bundled **Yaqyn** theme uses black, grayscale, and red across supported
applications. Change wallpapers, select fonts, or install compatible user themes.

[Explore the bundled Yaqyn theme](qvcore/theme/yaqyn/).

## <img src="docs/readme/icons/gaming.svg" width="24" height="24" alt=""> Gaming

![Gaming section](docs/readme/sections/gaming-symbol.png)

![Gaming artwork supplied for qvOS, showing a red-lit industrial game scene](docs/readme/gaming-scene.png)

A gaming runtime is part of the base system. Choose the launchers you want:
**Steam · Heroic · Lutris · Moonlight · RetroArch · Minecraft**.
Native installation flows select graphics support for detected hardware where
applicable.

## <img src="docs/readme/icons/tools.svg" width="24" height="24" alt=""> Tools

![Tools section](docs/readme/sections/tools-wrench.png)

- Screenshots, screen recording, region OCR, and clipboard color picking.
- Picture, video, and terminal-art conversion.
- File and clipboard sharing with LocalSend; Thunar desktop actions.
- Reminders, weather, and user-created Web Apps.
- Optional browsers, editors, terminals, VPN tools, and a managed Windows VM.

<p>
  <img src="docs/readme/cards/capture.png" width="128" height="85" alt="Capture">
  <img src="docs/readme/cards/media.png" width="128" height="85" alt="Media">
  <img src="docs/readme/cards/thunar.png" width="128" height="85" alt="Thunar — file-manager illustration">
  <img src="docs/readme/cards/webapps.png" width="128" height="85" alt="Web Apps">
  <img src="docs/readme/cards/windows.png" width="128" height="85" alt="Windows VM — desktop illustration">
</p>

Explore the native commands on an installed system:

```bash
qv --help
qv menu
qv menu keybindings
```

## <img src="docs/readme/icons/recovery.svg" width="24" height="24" alt=""> System & recovery

![Recovery section](docs/readme/sections/recovery.png)

- **Encrypted Btrfs** installation and the signed standard Arch kernel.
- **Snapper + Limine** snapshots and boot recovery.
- qvOS source updates, signed package updates, and restart guidance.
- Configuration refresh with private backups; local diagnostics without uploads.
- Battery charge protection and hibernation on supported hardware.
- Optional FIDO2, fingerprint, DNS, and Cloudflare WARP setup.

<p>
  <img src="docs/readme/cards/snapshots.png" width="128" height="85" alt="Snapshots and recovery">
  <img src="docs/readme/cards/security.png" width="128" height="85" alt="Security">
  <img src="docs/readme/cards/power.png" width="128" height="85" alt="Battery and power">
</p>

## <img src="docs/readme/icons/extensions.svg" width="24" height="24" alt=""> Optional integrations

![Extensions section](docs/readme/sections/extensions.png)

**Services · [Proton](https://proton.me)** — Pass, Drive, Mail Bridge, and VPN tools.

**Development · Devel** — compilers, build tools, debuggers, profilers, and
language tooling.

<p>
  <img src="docs/readme/cards/devel.png" width="128" height="85" alt="Devel — development illustration">
</p>

Both have independent installation and removal workflows. The base system
remains complete without them.

## <img src="docs/readme/icons/build.svg" width="24" height="24" alt=""> Build & install

![Build section](docs/readme/sections/build.png)

Select **Build** in the launcher. Have **Git**, an accessible **Docker daemon**,
**40 GiB free space**, and an Internet connection ready. Images are saved to
**`~/qvISO`** by default; verified download caches are reused.

<p>
  <img src="docs/readme/cards/git.png" width="128" height="85" alt="Git">
</p>

Boot the image to enter **Region → Account → Drive**. Building an ISO and
installing it are separate steps. T2 Macs are currently unsupported.

[Build and release requirements](release/iso/README.md) · [Launcher documentation](release/launcher/README.md)

## <img src="docs/readme/icons/developer.svg" width="24" height="24" alt=""> Developer

![Developer section](docs/readme/sections/developer.png)

**Abdulrahman M. Yaqyn** works across Linux system development and interface
design. qvOS brings that work together, from desktop presentation and terminal
tools to installation, maintenance, and recovery.

Explore his projects and portfolio at **[yaqyn.dev](https://yaqyn.dev)**.

## <img src="docs/readme/icons/project.svg" width="24" height="24" alt=""> Project

![Project section](docs/readme/sections/project.png)

[qvCORE architecture](qvcore/README.md) · [Source](https://github.com/yaqyn/qvOS) · [MIT license](LICENSE)

qvOS owns its product, defaults, integration, and releases. Selected capabilities
are reviewed from [Omarchy](https://github.com/basecamp/omarchy); its credited
signed Stable package infrastructure supplies the package-provider boundary.
Third-party components retain their respective licenses and copyright notices.
