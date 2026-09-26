#!/usr/bin/env python3
import argparse


def bases(path):
    out = []
    for line_no, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) < 2 or fields[1] != "FE0F":
            continue
        if len(fields) < 3 or fields[2] != ";":
            raise ValueError(f"unexpected sequence on line {line_no}")
        out.append(int(fields[0], 16))
    return out


def ranges(values):
    out = []
    for cp in values:
        if out and cp == out[-1][1] + 1:
            out[-1] = (out[-1][0], cp)
        else:
            out.append((cp, cp))
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("source")
    a = p.parse_args()
    values = bases(a.source)
    if values != sorted(set(values)):
        raise ValueError("emoji VS16 bases must be sorted and unique")
    rs = ranges(values)
    for first, last in rs:
        print(f"{{0x{first:04x},0x{last:04x}}},")


if __name__ == "__main__":
    main()
