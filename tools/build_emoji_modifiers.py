#!/usr/bin/env python3
"""Generate the Unicode Emoji_Modifier_Base device range table."""
import argparse
import re
from pathlib import Path


def bases(path):
    out = []
    for line_no, raw in enumerate(Path(path).read_text(encoding='utf-8').splitlines(), 1):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        fields = [x.strip() for x in line.split(';')]
        if len(fields) < 2 or fields[1] != 'Emoji_Modifier_Base':
            continue
        for item in fields[0].split():
            if '..' in item:
                first, last = (int(x, 16) for x in item.split('..'))
            else:
                first = last = int(item, 16)
            out.append((first, last))
    if not out:
        raise ValueError('no Emoji_Modifier_Base entries')
    previous = -1
    for first, last in out:
        if first > last or first <= previous:
            raise ValueError('ranges must be sorted, unique, and non-overlapping')
        previous = last
    return out


def render(path, rs):
    text = Path(path).read_text(encoding='utf-8')
    actual = [(int(a, 16), int(b, 16)) for a, b in
              re.findall(r'\{0x([0-9a-f]+),0x([0-9a-f]+)\}', text)]
    if actual != rs:
        raise ValueError('header ranges differ from Unicode Emoji_Modifier_Base data')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source')
    p.add_argument('--check', type=Path)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    rs = bases(a.source)
    if a.check:
        render(a.check, rs)
        return
    lines = [
        '#pragma once', '',
        '// Generated from Unicode 17.0.0 emoji-data.txt (2025-07-25):',
        '// https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt',
        '// Copyright Unicode, Inc.; Unicode data files are distributed under',
        '// the Unicode Terms of Use: https://www.unicode.org/terms_of_use.html',
        '//', f'// {sum(b - a + 1 for a, b in rs)} code points in {len(rs)} ranges.',
        'struct EmojiModifierBaseRange { uint32_t first, last; };',
        'static __device__ __constant__ const EmojiModifierBaseRange',
        '    emoji_modifier_base_ranges[] = {']
    lines += [f'  {{0x{first:04x},0x{last:04x}}},' for first, last in rs]
    lines += ['};', '__device__ bool emoji_modifier_base(uint32_t cp) {',
              '  for (const auto &r : emoji_modifier_base_ranges)',
              '    if (cp < r.first) return false;',
              '    else if (cp <= r.last) return true;',
              '  return false;', '}', '']
    result = '\n'.join(lines)
    if a.output:
        a.output.write_text(result)
    else:
        print(result, end='')


if __name__ == '__main__':
    main()
