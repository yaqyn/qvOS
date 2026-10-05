"""Render the README's pixel-gradient cover from the canonical qvOS wordmark."""

import hashlib
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from pixel_art import pixel_gradient, pixel_label

OWNER = Path(__file__).resolve().parent
ROOT = OWNER.parents[1]
WIDTH, HEIGHT, CELL, FRAMES = 1280, 448, 16, 32


def system_label():
  return pixel_label("SYSTEM", 554, 352, 4, "#c8c8c8", spacing=2.5)


def render_svg(paths, digest, frame):
  return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="title desc">
  <title id="title">qvOS System</title>
  <desc id="desc">The official white qvOS wordmark and a pixel-lettered SYSTEM label over a simple dark red-to-grayscale pixel gradient.</desc>
  <!-- Canonical wordmark: qvcore/branding/assets/qvos-wordmark-light.svg; SHA-256: {digest}. Rendered by docs/readme/render-cover.py. -->
  {pixel_gradient(WIDTH, HEIGHT, frame)}
  <svg x="340" y="94" width="600" height="212" viewBox="0 740 2000 707">{paths}</svg>
  {system_label()}
</svg>
'''


def main():
  master = ROOT / 'qvcore/branding/assets/qvos-wordmark-light.svg'
  digest = hashlib.sha256(master.read_bytes()).hexdigest()
  paths = ''.join(f'<path fill="#ffffff" d="{element.attrib["d"]}"/>'
                  for element in ET.parse(master).getroot().iter()
                  if element.tag.endswith('path'))
  assert paths, 'Canonical wordmark paths are required'
  (OWNER / 'cover.svg').write_text(render_svg(paths, digest, 0))
  with tempfile.TemporaryDirectory(prefix='qvos-cover-') as scratch:
    stage = Path(scratch)
    for frame in range(FRAMES):
      source = stage / f'frame-{frame:03}.svg'
      source.write_text(render_svg(paths, digest, frame))
      subprocess.run(['rsvg-convert', str(source), '-o',
                      str(stage / f'frame-{frame:03}.png')], check=True)
    subprocess.run([
      'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
      '-framerate', '6.25', '-i', str(stage / 'frame-%03d.png'),
      '-filter_complex',
      '[0:v]split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];'
      '[b][p]paletteuse=dither=none:diff_mode=rectangle',
      '-loop', '0', str(OWNER / 'cover.gif'),
    ], check=True)
  print(f'Rendered {FRAMES} frames; cover.gif: '
        f'{(OWNER / "cover.gif").stat().st_size:,} bytes')


if __name__ == '__main__':
  main()
