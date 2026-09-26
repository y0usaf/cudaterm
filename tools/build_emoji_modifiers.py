#!/usr/bin/env python3
import argparse
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


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source')
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    rs = bases(a.source)
    lines = [
        '#pragma once', '',
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
