"""Render section bars and product cards using the cover's shared pixel gradient."""

import base64
import html
from pathlib import Path
import subprocess
import tempfile

from pixel_art import pixel_gradient, pixel_label

OWNER = Path(__file__).resolve().parent
SECTIONS = [
  ('start', 'GET QVOS', 'icons/start.svg'),
  ('desktop', 'DESKTOP', 'logos/hyprland.png'),
  ('wallpaper', 'WALLPAPER & APPEARANCE', 'icons/wallpaper.svg'),
  ('gaming', 'GAMING', 'logos/steam.svg'),
  ('tools', 'TOOLS', 'logos/localsend.png'),
  ('recovery', 'SYSTEM & RECOVERY', 'icons/recovery.svg'),
  ('extensions', 'OPTIONAL INTEGRATIONS', 'logos/proton-proton.svg'),
  ('build', 'BUILD & INSTALL', 'logos/git.png'),
  ('developer', 'DEVELOPER', 'icons/developer.svg'),
  ('project', 'PROJECT', 'icons/project.svg'),
]
CARDS = [
  ('hyprland', 'HYPRLAND', 'logos/hyprland.png'),
  ('waybar', 'WAYBAR', 'icons/desktop.svg'),
  ('walker', 'WALKER', 'icons/start.svg'),
  ('elephant', 'ELEPHANT', 'icons/project.svg'),
  ('steam', 'STEAM', 'logos/steam.svg'),
  ('heroic', 'HEROIC', 'logos/heroic.svg'),
  ('lutris', 'LUTRIS', 'logos/lutris.png'),
  ('moonlight', 'MOONLIGHT', 'logos/moonlight.svg'),
  ('retroarch', 'RETROARCH', 'logos/retroarch.svg'),
  ('minecraft', 'MINECRAFT', 'icons/voxel.svg'),
  ('capture', 'CAPTURE', 'icons/wallpaper.svg'),
  ('media', 'MEDIA', 'icons/gaming.svg'),
  ('localsend', 'LOCALSEND', 'logos/localsend.png'),
  ('thunar', 'THUNAR', 'icons/folder.svg'),
  ('reminders', 'REMINDERS', 'icons/recovery.svg'),
  ('webapps', 'WEB APPS', 'icons/desktop.svg'),
  ('arch', 'ARCH LINUX', 'logos/arch.svg'),
  ('snapshots', 'SNAPSHOTS', 'icons/recovery.svg'),
  ('security', 'SECURITY', 'icons/shield.svg'),
  ('power', 'POWER', 'icons/battery.svg'),
  ('windows', 'WINDOWS VM', 'icons/desktop.svg'),
  ('pass', 'PASS', 'logos/proton-pass.svg'),
  ('drive', 'DRIVE', 'logos/proton-drive.svg'),
  ('mail', 'MAIL BRIDGE', 'logos/proton-mail.svg'),
  ('vpn', 'VPN', 'logos/proton-vpn.svg'),
  ('devel', 'DEVEL', 'icons/code.svg'),
  ('git', 'GIT', 'logos/git.png'),
  ('docker', 'DOCKER', 'logos/docker.svg'),
]


def picture(source, x, y, width, height):
  path = OWNER / source
  mime = 'image/svg+xml' if path.suffix == '.svg' else 'image/png'
  data = base64.b64encode(path.read_bytes()).decode()
  backdrop = (f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="#e6e6e6"/>'
              if path.name == "retroarch.svg" else "")
  return backdrop + f'<image x="{x}" y="{y}" width="{width}" height="{height}" href="data:{mime};base64,{data}"/>'


def svg(title, width, height, contents):
  return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
          f'viewBox="0 0 {width} {height}" role="img" aria-label="{html.escape(title)}">'
          f'{pixel_gradient(width, height)}{contents}</svg>')


def main():
  (OWNER / 'sections').mkdir(exist_ok=True)
  (OWNER / 'cards').mkdir(exist_ok=True)
  with tempfile.TemporaryDirectory(prefix='qvos-sections-') as scratch:
    stage = Path(scratch)
    for name, title, source in SECTIONS:
      art = picture(source, 40, 28, 128, 72) + pixel_label(title, 208, 43, 6)
      path = stage / f'section-{name}.svg'
      path.write_text(svg(title, 1280, 128, art))
      subprocess.run(['rsvg-convert', str(path), '-o', str(OWNER / 'sections' / f'{name}.png')], check=True)
    for name, title, source in CARDS:
      art = picture(source, 44, 16, 104, 64) + pixel_label(title, (192 - (len(title) * 6 - 1) * 2) // 2, 96, 2)
      path = stage / f'card-{name}.svg'
      path.write_text(svg(title, 192, 128, art))
      subprocess.run(['rsvg-convert', str(path), '-o', str(OWNER / 'cards' / f'{name}.png')], check=True)
  print(f'Rendered {len(SECTIONS)} section bars and {len(CARDS)} product/feature cards.')


if __name__ == '__main__':
  main()
