"""Bake a configured font/fallback chain into a CUDA alpha atlas at build time."""
import argparse
import math
from pathlib import Path
import struct

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont


# Terminal rules join at cell centres, regardless of the font's glyph bearings.
BOX_ARMS = {'─': 'lr', '│': 'ud', '┌': 'rd', '┐': 'ld', '└': 'ru', '┘': 'lu',
            '├': 'urd', '┤': 'uld', '┬': 'lrd', '┴': 'lru', '┼': 'lrud'}


def box_glyph(character, width, height):
    image = Image.new('L', (width * 2, height))
    draw = ImageDraw.Draw(image)
    x, y = (width - 1) // 2, (height - 1) // 2
    for arm in BOX_ARMS[character]:
        end = {'l': (0, y), 'r': (width - 1, y),
               'u': (x, 0), 'd': (x, height - 1)}[arm]
        draw.line([(x, y), end], fill=255)
    return image.tobytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--font', action='append', required=True)
    parser.add_argument('--pixels', type=int, required=True)
    parser.add_argument('--height', type=int, required=True)
    parser.add_argument('--widths', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not 1 <= args.pixels <= 128 or not 1 <= args.height <= 128:
        parser.error('font pixels and cell height must be between 1 and 128')
    widths = Path(args.widths).read_bytes()
    if len(widths) != 0x110000: raise ValueError('invalid width table')
    fonts = [ImageFont.truetype(path, args.pixels, layout_engine=ImageFont.Layout.BASIC) for path in args.font]
    width = math.ceil(fonts[0].getlength('M'))
    if not 1 <= width <= 64: raise ValueError('invalid cell width')
    glyphs = {}
    for path, font in zip(args.font, fonts):
        with TTFont(path) as source:
            cmap = source.getBestCmap()
        ascent, descent = font.getmetrics()
        baseline = (args.height - ascent - descent) // 2 + ascent
        for cp in sorted(cmap):
            if cp in glyphs or cp < 32 or cp >= len(widths) or widths[cp] not in (1, 2): continue
            span = width * widths[cp]
            # Fit oversized fallback symbols into their terminal cell span.
            left, top, right, bottom = font.getbbox(chr(cp), anchor='ls')
            canvas = Image.new('L', (max(span, right - min(0, left)), args.height))
            ImageDraw.Draw(canvas).text((-min(0,left), baseline), chr(cp), font=font, fill=255, anchor='ls')
            if canvas.width > span: canvas = canvas.resize((span,args.height), Image.Resampling.LANCZOS)
            image = Image.new('L', (width * 2, args.height))
            image.paste(canvas, (0,0))
            glyphs[cp] = image.tobytes()
    if not glyphs: raise ValueError('font chain contains no usable glyphs')
    for character in BOX_ARMS:
        glyphs[ord(character)] = box_glyph(character, width, args.height)
    pixels = b''.join(glyphs.values())
    if len(pixels) > 64 * 1024 * 1024: raise ValueError('font atlas exceeds 64 MiB')
    pages = {}
    for slot, cp in enumerate(glyphs):
        pages.setdefault(cp >> 8, [0xffffffff] * 256)[cp & 255] = slot
    page_map = [0xffffffff] * 0x1100
    for index, page in enumerate(pages): page_map[page] = index
    data = b'CTFACE01' + struct.pack('<4I', width, args.height, len(glyphs), len(pages)) + pixels
    data += b'\0' * (-len(data) % 4)
    data += struct.pack('<4352I', *page_map)
    data += b''.join(struct.pack('<256I', *values) for values in pages.values())
    Path(args.output).write_bytes(data)


if __name__ == '__main__': main()
