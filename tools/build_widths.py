#!/usr/bin/env python3
"""Generate Unicode scalar widths and Unicode combining placement offsets."""
import argparse
import unicodedata

MAX = 0x110000


def parse_combining(path):
    offsets = {}
    with open(path, encoding="ascii") as f:
        for line_no, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            try:
                code, value = line.split(":", 1)
                cp, offset = int(code, 16), int(value, 10)
            except (ValueError, TypeError):
                raise ValueError("invalid combining entry on line %d" % line_no)
            if not 0 <= cp < MAX or not -128 <= offset <= 127:
                raise ValueError("combining entry out of range on line %d" % line_no)
            if cp in offsets and offsets[cp] != offset:
                raise ValueError("duplicate combining entry U+%04X" % cp)
            offsets[cp] = offset
    return offsets


def build(combining, out, offsets_out, version_out):
    offsets = parse_combining(combining)
    widths = bytearray(1 for _ in range(MAX))
    for cp in range(MAX):
        ch = chr(cp)
        if (unicodedata.combining(ch) or
                unicodedata.category(ch) in ("Mn", "Me", "Cf")):
            widths[cp] = 0
        elif unicodedata.category(ch) != "Cn" and unicodedata.east_asian_width(ch) in ("W", "F"):
            widths[cp] = 2
    for cp in offsets:
        widths[cp] = 0
    with open(out, "wb") as f:
        f.write(widths)
    with open(offsets_out, "wb") as f:
        f.write(bytes((offsets.get(cp, 0) & 0xff) for cp in range(MAX)))
    with open(version_out, "w", encoding="ascii") as f:
        f.write(unicodedata.unidata_version + "\n")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--combining", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--offsets-out", required=True)
    p.add_argument("--version-out", required=True)
    a = p.parse_args()
    build(a.combining, a.out, a.offsets_out, a.version_out)


if __name__ == "__main__":
    main()
