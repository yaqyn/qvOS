"""Shared pixel typography and gradient for qvOS documentation artwork."""

import math

GLYPHS = {
  'A':'01110 10001 10001 11111 10001 10001 10001',
  'B':'11110 10001 10001 11110 10001 10001 11110',
  'C':'01111 10000 10000 10000 10000 10000 01111',
  'D':'11110 10001 10001 10001 10001 10001 11110',
  'E':'11111 10000 10000 11110 10000 10000 11111',
  'F':'11111 10000 10000 11110 10000 10000 10000',
  'G':'01111 10000 10000 10111 10001 10001 01111',
  'H':'10001 10001 10001 11111 10001 10001 10001',
  'I':'11111 00100 00100 00100 00100 00100 11111',
  'J':'00111 00010 00010 00010 10010 10010 01100',
  'K':'10001 10010 10100 11000 10100 10010 10001',
  'L':'10000 10000 10000 10000 10000 10000 11111',
  'M':'10001 11011 10101 10101 10001 10001 10001',
  'N':'10001 11001 11001 10101 10011 10011 10001',
  'O':'01110 10001 10001 10001 10001 10001 01110',
  'P':'11110 10001 10001 11110 10000 10000 10000',
  'Q':'01110 10001 10001 10001 10101 10010 01101',
  'R':'11110 10001 10001 11110 10100 10010 10001',
  'S':'11111 10000 10000 11111 00001 00001 11111',
  'T':'11111 00100 00100 00100 00100 00100 00100',
  'U':'10001 10001 10001 10001 10001 10001 01110',
  'V':'10001 10001 10001 10001 10001 01010 00100',
  'W':'10001 10001 10001 10101 10101 10101 01010',
  'X':'10001 10001 01010 00100 01010 10001 10001',
  'Y':'10001 10001 01010 00100 00100 00100 00100',
  'Z':'11111 00001 00010 00100 01000 10000 11111',
  '&':'01100 10010 10100 01000 10101 10010 01101',
  ' ':'00000 00000 00000 00000 00000 00000 00000',
}

def pixel_gradient(width, height, frame=0, frames=32):
  phase = 2 * math.pi * frame / frames
  pixels = []
  for y in range(0, height, 16):
    strength = 0.12 + 0.88 * (y / height) ** 1.5
    for x in range(0, width, 16):
      position = x / width
      red = max(0, 1 - position / 0.65)
      gray = max(0, (position - 0.38) / 0.62)
      motion = 0.88 + 0.12 * math.sin(phase + position * math.pi)
      neutral = round(gray * 36 * strength * motion / 4) * 4
      warm = round(red * 92 * strength * motion / 4) * 4
      color = f'#{8 + neutral + warm:02x}{8 + neutral:02x}{8 + neutral:02x}'
      pixels.append(f'<rect x="{x}" y="{y}" width="{16}" '
                    f'height="{16}" fill="{color}"/>')
  return '<g shape-rendering="crispEdges">' + ''.join(pixels) + '</g>'


def pixel_label(text, x, y, scale, color="#e6e6e6", spacing=1):
  rectangles = []
  for index, letter in enumerate(text):
    for row, line in enumerate(GLYPHS[letter].split()):
      for column, bit in enumerate(line):
        if bit == '1':
          rectangles.append(f'<rect x="{x + (index * (5 + spacing) + column) * scale}" '
                            f'y="{y + row * scale}" width="{scale}" height="{scale}"/>')
  return f'<g fill="{color}" shape-rendering="crispEdges">' + ''.join(rectangles) + '</g>'


