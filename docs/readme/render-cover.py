"""Render the README's pixel-gradient cover from the canonical qvOS wordmark."""

import hashlib
import math
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

OWNER = Path(__file__).resolve().parent
ROOT = OWNER.parents[1]
WIDTH, HEIGHT, CELL, FRAMES = 1280, 448, 16, 32


def system_label():
  glyphs = {
    'S': ['11111', '10000', '10000', '11111', '00001', '00001', '11111'],
    'Y': ['10001', '10001', '01010', '00100', '00100', '00100', '00100'],
    'T': ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
    'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    'M': ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
  }
  cells = []
  for index, letter in enumerate('SYSTEM'):
    for row, line in enumerate(glyphs[letter]):
      for column, bit in enumerate(line):
        if bit == '1':
          cells.append(f'<rect x="{554 + index * 30 + column * 4}" '
                       f'y="{352 + row * 4}" width="4" height="4"/>')
  return '<g fill="#c8c8c8">' + ''.join(cells) + '</g>'


def render_svg(paths, digest, frame):
  phase = 2 * math.pi * frame / FRAMES
  pixels = []
  for y in range(0, HEIGHT, CELL):
    strength = 0.12 + 0.88 * (y / HEIGHT) ** 1.5
    for x in range(0, WIDTH, CELL):
      position = x / WIDTH
      red = max(0, 1 - position / 0.65)
      gray = max(0, (position - 0.38) / 0.62)
      motion = 0.88 + 0.12 * math.sin(phase + position * math.pi)
      neutral = round(gray * 36 * strength * motion / 4) * 4
      warm = round(red * 92 * strength * motion / 4) * 4
      color = f'#{8 + neutral + warm:02x}{8 + neutral:02x}{8 + neutral:02x}'
      pixels.append(f'<rect x="{x}" y="{y}" width="{CELL}" '
                    f'height="{CELL}" fill="{color}"/>')
  return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="title desc">
  <title id="title">qvOS System</title>
  <desc id="desc">The official white qvOS wordmark and a pixel-lettered SYSTEM label over a simple dark red-to-grayscale pixel gradient.</desc>
  <!-- Canonical wordmark: qvcore/branding/assets/qvos-wordmark-light.svg; SHA-256: {digest}. Rendered by docs/readme/render-cover.py. -->
  <g shape-rendering="crispEdges">{''.join(pixels)}</g>
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
