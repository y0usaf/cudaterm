#!/usr/bin/env python3
"""Build cudaterm's fixed 16-row BMP and supplementary font atlas."""
import argparse
import struct

MAGIC = b"CTFONT02"
COUNT = 0x10000
MAX_CP = 0x10FFFF
PAGE_TOTAL = 0x1100
UINT_MAX = 0xFFFFFFFF


def _read_bdf(bdf):
    ascent = None
    glyphs = {}
    current = None
    bitmap = None
    with open(bdf, "r", encoding="utf-8") as f:
        for raw in f:
            fields = raw.split()
            if not fields:
                continue
            tag = fields[0]
            if tag == "FONT_ASCENT":
                ascent = int(fields[1])
            elif tag == "STARTCHAR":
                if current is not None:
                    raise ValueError("nested STARTCHAR")
                current = {}
            elif tag == "ENDCHAR":
                if current is None or bitmap is None:
                    raise ValueError("incomplete glyph")
                enc = current.get("encoding")
                if enc is None:
                    raise ValueError("glyph missing ENCODING")
                if 0 <= enc < COUNT:
                    if enc in glyphs:
                        raise ValueError("duplicate BMP encoding %d" % enc)
                    width, height, xoff, yoff = current["bbx"]
                    dwidth = current["dwidth"]
                    if width not in (8, 16) or dwidth not in (0, 8, 16) or xoff != 0:
                        raise ValueError("unsupported glyph width for %d" % enc)
                    if not 0 <= height <= 16 or len(bitmap) != height or any(value < 0 or value >= (1 << width) for value in bitmap):
                        raise ValueError("invalid bitmap height for %d" % enc)
                    glyphs[enc] = (width, height, xoff, yoff, bitmap)
                current = None
                bitmap = None
            elif current is not None:
                if tag == "ENCODING":
                    current["encoding"] = int(fields[1])
                elif tag == "DWIDTH":
                    current["dwidth"] = int(fields[1])
                elif tag == "BBX":
                    current["bbx"] = tuple(map(int, fields[1:5]))
                elif tag == "BITMAP":
                    if "bbx" not in current:
                        raise ValueError("BITMAP before BBX")
                    height = current["bbx"][1]
                    bitmap = []
                    for _ in range(height):
                        line = next(f, "").strip()
                        try:
                            bitmap.append(int(line, 16))
                        except ValueError as e:
                            raise ValueError("invalid bitmap row") from e
    if current is not None or ascent is None:
        raise ValueError("malformed BDF")
    return ascent, glyphs


def _read_upper(path):
    glyphs = {}
    with open(path, "r", encoding="ascii") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if ":" not in line:
                raise ValueError("malformed upper hex line")
            cp_text, bits = line.split(":", 1)
            try:
                cp = int(cp_text, 16)
            except ValueError as e:
                raise ValueError("invalid upper codepoint") from e
            bits = bits.strip()
            if cp < 0 or cp > MAX_CP or 0xD800 <= cp <= 0xDFFF:
                raise ValueError("invalid upper scalar")
            if cp < COUNT:
                continue
            if len(bits) not in (32, 64) or any(c not in "0123456789abcdefABCDEF" for c in bits):
                raise ValueError("upper glyph must be 8x16 or 16x16")
            try:
                rawbits = bytes.fromhex(bits)
            except ValueError as e:
                raise ValueError("invalid upper bitmap") from e
            width = 8 if len(bits) == 32 else 16
            if cp in glyphs:
                raise ValueError("duplicate upper encoding %d" % cp)
            stride = width // 8
            rows = [int.from_bytes(rawbits[y * stride:(y + 1) * stride], "big")
                    << (8 if width == 8 else 0) for y in range(16)]
            glyphs[cp] = (width, rows)
    return glyphs


def build(bdf, out, upper_hex=None):
    ascent, glyphs = _read_bdf(bdf)
    upper = _read_upper(upper_hex) if upper_hex else {}
    rows = [0] * (COUNT * 16)
    widths = bytearray(COUNT)
    for enc, (width, height, xoff, yoff, bits) in glyphs.items():
        widths[enc] = width
        for source_row, value in enumerate(bits):
            y = ascent - (yoff + height) + source_row
            if not 0 <= y < 16:
                raise ValueError("glyph %d exceeds 16-row atlas" % enc)
            if width == 8:
                value = (value & 0xff) << 8
            else:
                value &= 0xffff
            rows[enc * 16 + y] = value
    upper_cps = sorted(upper)
    page_ids = [UINT_MAX] * PAGE_TOTAL
    pages = []
    for index, enc in enumerate(upper_cps):
        page = enc >> 8
        if page_ids[page] == UINT_MAX:
            page_ids[page] = len(pages)
            pages.append([UINT_MAX] * 256)
        pages[page_ids[page]][enc & 0xff] = COUNT + index
    with open(out, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<II", COUNT + len(upper_cps), len(pages)))
        all_rows = list(rows)
        all_widths = bytearray(widths)
        for enc in upper_cps:
            width, glyph_rows = upper[enc]
            all_rows.extend(glyph_rows)
            all_widths.append(width)
        f.write(struct.pack("<%dH" % len(all_rows), *all_rows))
        f.write(all_widths)
        f.write(struct.pack("<%dI" % PAGE_TOTAL, *page_ids))
        for page in pages:
            f.write(struct.pack("<256I", *page))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bdf", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--upper-hex")
    args = p.parse_args()
    build(args.bdf, args.out, args.upper_hex)


if __name__ == "__main__":
    main()
