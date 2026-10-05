"""Render section bars and product cards using the cover's shared pixel gradient."""

import base64
import html
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from pixel_art import pixel_gradient, pixel_label

OWNER = Path(__file__).resolve().parent
SECTIONS = [
  ('start', 'GET QVOS', 'icons/start.svg'),
  ('desktop', 'DESKTOP', 'logos/hyprland.png'),
  ('wallpaper', 'WALLPAPER & APPEARANCE', 'icons/wallpaper.svg'),
  ('gaming-symbol', 'GAMING', 'logos/steam.svg'),
  ('tools', 'TOOLS', 'icons/tools.svg'),
  ('recovery', 'SYSTEM & RECOVERY', 'icons/recovery.svg'),
  ('extensions', 'OPTIONAL INTEGRATIONS', 'logos/proton-proton.svg'),
  ('build', 'BUILD & INSTALL', 'logos/git.png'),
  ('developer', 'DEVELOPER', 'icons/developer.svg'),
  ('project', 'PROJECT', 'icons/project.svg'),
]
CARDS = [
  ('capture', 'CAPTURE', 'icons/wallpaper.svg'),
  ('media', 'MEDIA', 'icons/gaming.svg'),
  ('thunar', 'THUNAR', 'icons/folder.svg'),
  ('webapps', 'WEB APPS', 'icons/desktop.svg'),
  ('snapshots', 'SNAPSHOTS', 'icons/recovery.svg'),
  ('security', 'SECURITY', 'icons/shield.svg'),
  ('power', 'POWER', 'icons/battery.svg'),
  ('windows', 'WINDOWS VM', 'icons/desktop.svg'),
  ('devel', 'DEVEL', 'icons/code.svg'),
  ('git', 'GIT', 'logos/git.png'),
]


def picture(source, x, y, width, height):
  path = OWNER / source
  mime = 'image/svg+xml' if path.suffix == '.svg' else 'image/png'
  payload = path.read_bytes()
  if path.name == 'steam.svg':
    # The first three canonical paths form the symbol; later paths are lettering.
    root = ET.fromstring(payload)
    paths = [element for element in root.iter() if element.tag.endswith('path')]
    assert len(paths) >= 3, 'Steam symbol paths are required'
    symbol = ET.Element('svg', {'xmlns': 'http://www.w3.org/2000/svg',
                               'viewBox': '0 0 89 89', 'width': '89', 'height': '89'})
    symbol.extend(paths[:3])
    payload = ET.tostring(symbol)
  data = base64.b64encode(payload).decode()
  return f'<image x="{x}" y="{y}" width="{width}" height="{height}" href="data:{mime};base64,{data}"/>'


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
