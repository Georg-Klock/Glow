#!/usr/bin/env python3
"""Cut scene.js into the blocks the Webflow page can hold.

A Webflow custom-code block stops at 10,000 characters and the scene is longer
than that, so it is written here as one file with explicit `===== block n of m`
boundaries and split on them. Each block is a complete IIFE and they are loaded
in order; block 1 publishes window.GWA_M, block 2 window.GWA_S, block 3 reads
both and builds the scene.

Only whole-line comments are dropped, so the trailing notes that explain a
number stay with the number. Writes webflow/*.html and prints the sizes, which
is the number that matters: over 10,000 and Webflow refuses the paste.
"""
import pathlib
import re
import sys

CAP = 10000
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / 'webflow'


def strip_line_comments(src: str) -> str:
    """Remove comment-only lines. Anything sharing a line with code stays."""
    out, in_block = [], False
    for line in src.split('\n'):
        bare = line.strip()
        if in_block:
            if '*/' in bare:
                in_block = False
                tail = bare.split('*/', 1)[1].strip()
                if tail:
                    out.append(tail)
            continue
        if bare.startswith('/*'):
            if '*/' not in bare:
                in_block = True
                continue
            tail = bare.split('*/', 1)[1].strip()
            if tail:
                out.append(tail)
            continue
        if bare.startswith('//'):
            continue
        out.append(line)
    text = '\n'.join(out)
    return re.sub(r'\n{3,}', '\n\n', text).strip() + '\n'


def main() -> int:
    src = (HERE / 'scene.js').read_text(encoding='utf-8')
    parts = re.split(r'/\* ===== block \d+ of \d+ =+.*?\*/\n', src, flags=re.S)
    parts = [p for p in parts if p.strip()]
    if len(parts) != 3:
        print('expected 3 blocks, found %d' % len(parts), file=sys.stderr)
        return 1

    OUT.mkdir(exist_ok=True)
    over = False
    for i, part in enumerate(parts, 1):
        body = strip_line_comments(part)
        block = '<script>' + body + '</script>'
        (OUT / ('block%d.html' % i)).write_text(block, encoding='utf-8')
        flag = '  OVER THE 10,000 CAP' if len(block) > CAP else ''
        over = over or bool(flag)
        print('block%d.html  %6d chars%s' % (i, len(block), flag))
    return 1 if over else 0


if __name__ == '__main__':
    raise SystemExit(main())
