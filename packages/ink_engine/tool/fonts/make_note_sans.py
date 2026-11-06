#!/usr/bin/env python3
"""Builds the NoteSans text box fonts of ink_engine (m5-7/03-ink 6.10.1, 4.12).

Developer tool only: neither the build nor CI runs it. The outputs are committed.

  source  Noto Sans KR variable font (google/fonts, OFL 1.1), checked by sha256
  steps   pin wght 400 / 700 -> subset -> rename to NoteSans -> save
          (recalcTimestamp=False, so two runs give the same bytes)
  outputs assets/fonts/NoteSans-Regular.ttf, assets/fonts/NoteSans-Bold.ttf,
          lib/src/text/note_sans_coverage.dart (code point ranges of the subset),
          with --test-font also lib/src/testing/ink_test_font.dart (base64 test font:
          ASCII + compatibility jamo + tool/fonts/test_font_chars.txt, regular only)

Usage (from packages/ink_engine, with fonttools 4.67.0 — no brotli needed):

  python3 -m venv /tmp/fontvenv && /tmp/fontvenv/bin/pip install fonttools==4.67.0
  /tmp/fontvenv/bin/python tool/fonts/make_note_sans.py --test-font \
      [--source /path/to/NotoSansKR[wght].ttf]

Without --source the font is downloaded from SOURCE_URL (a commit-pinned address).
"""

import argparse
import base64
import gzip
import hashlib
import io
import os
import sys
import urllib.request

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

FONTTOOLS_VERSION = '4.67.0'
SOURCE_COMMIT = '24ddc1f324cac5d9f5aedca126d298f56e3f1640'
SOURCE_URL = ('https://raw.githubusercontent.com/google/fonts/' + SOURCE_COMMIT +
              '/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf')
SOURCE_SHA256 = '194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252'
FAMILY = 'NoteSans'
WEIGHTS = ((400, 'Regular'), (700, 'Bold'))

# 40 punctuation marks and symbols (m5-7/03-ink 6.10.1)
SYMBOLS = (
    0x2018, 0x2019, 0x201C, 0x201D, 0x2026, 0x00B7, 0x2013, 0x2014, 0x2022, 0x203B,
    0x2192, 0x2190, 0x2191, 0x2193, 0x3001, 0x3002, 0x300C, 0x300D, 0x300E, 0x300F,
    0x3008, 0x3009, 0x300A, 0x300B, 0x3010, 0x3011, 0x20A9, 0x2103, 0x2116, 0x2122,
    0x2460, 0x2461, 0x2462, 0x2463, 0x2464, 0x2465, 0x2466, 0x2467, 0x2468, 0x2469,
)
ASCII = range(0x20, 0x7F)
LATIN1 = range(0xA0, 0x100)
COMPAT_JAMO = range(0x3131, 0x318F)
LAYOUT_FEATURES = ['kern', 'liga', 'calt', 'ccmp', 'locl', 'mark', 'mkmk']


def ks_x_1001_hangul():
    """The 2,350 Hangul syllables encoded by EUC-KR in two bytes (KS X 1001)."""
    out = []
    for c in range(0xAC00, 0xD7A4):
        try:
            if len(chr(c).encode('euc_kr')) == 2:
                out.append(c)
        except UnicodeEncodeError:
            pass
    return out


def subset_code_points():
    cps = set(ASCII) | set(LATIN1) | set(SYMBOLS) | set(COMPAT_JAMO)
    hangul = ks_x_1001_hangul()
    assert len(hangul) == 2350, len(hangul)
    cps |= set(hangul)
    return cps


def test_font_code_points(chars_path):
    cps = set(ASCII) | set(COMPAT_JAMO)
    with open(chars_path, encoding='utf-8') as f:
        for line in f:
            line = line.split('#', 1)[0]
            for ch in line:
                if 0xAC00 <= ord(ch) <= 0xD7A3:
                    cps.add(ord(ch))
    return cps


def read_source(path):
    if path:
        with open(path, 'rb') as f:
            data = f.read()
    else:
        with urllib.request.urlopen(SOURCE_URL) as r:
            data = r.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256:
        sys.exit('source sha256 %s != %s' % (digest, SOURCE_SHA256))
    return data


def rename(font, style):
    """NoteSans names (the modified version does not use the original font names)."""
    name = font['name']
    version = name.getDebugName(5) or ''
    version_number = version.split(';')[0].replace('Version ', '').split('-')[0]
    full = '%s %s' % (FAMILY, style)
    ps = '%s-%s' % (FAMILY, style)
    keep = []
    for record in name.names:
        if record.nameID in (16, 17, 21, 22, 25) or record.nameID >= 256:
            continue
        keep.append(record)
    name.names = keep
    for name_id, value in ((1, FAMILY), (2, style),
                           (3, '%s;%s' % (version_number, ps)),
                           (4, full), (6, ps)):
        name.removeNames(nameID=name_id)
        name.setName(value, name_id, 3, 1, 0x409)
        name.setName(value, name_id, 1, 0, 0)
    os2 = font['OS/2']
    head = font['head']
    if style == 'Bold':
        os2.fsSelection = (os2.fsSelection | (1 << 5)) & ~(1 << 6) & ~1
        head.macStyle |= 1
    else:
        os2.fsSelection = (os2.fsSelection | (1 << 6)) & ~(1 << 5) & ~1
        head.macStyle &= ~1


def make_instance(source_bytes, weight, style, code_points):
    font = TTFont(io.BytesIO(source_bytes), recalcTimestamp=False)
    inst = instancer.instantiateVariableFont(font, {'wght': weight})
    opts = subset.Options()
    opts.layout_features = LAYOUT_FEATURES
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    opts.hinting = False
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=code_points)
    sub.subset(inst)
    rename(inst, style)
    out = io.BytesIO()
    inst.recalcTimestamp = False
    inst.save(out)
    return out.getvalue(), inst


def ranges_of(code_points):
    ranges = []
    for c in sorted(code_points):
        if ranges and ranges[-1][1] == c - 1:
            ranges[-1][1] = c
        else:
            ranges.append([c, c])
    return ranges


def write_coverage(path, font):
    cmap = font.getBestCmap()
    ranges = ranges_of(cmap.keys())
    lines = [
        '// GENERATED by tool/fonts/make_note_sans.py — do not edit.',
        '// The code points of the bundled NoteSans subset (m5-7/03-ink 6.10.1):',
        '// sorted [start, end] pairs, both inclusive; InkFonts.covers searches it.',
        '// coverage_table_test.dart checks it against the cmap of the committed font.',
        "import 'package:meta/meta.dart';",
        '',
        '/// %d code points in %d ranges.' % (len(cmap), len(ranges)),
        '@internal',
        'const List<int> noteSansCoverage = [',
    ]
    row = []
    for start, end in ranges:
        row.append('0x%X, 0x%X,' % (start, end))
        if len(row) == 4:
            lines.append('  ' + ' '.join(row))
            row = []
    if row:
        lines.append('  ' + ' '.join(row))
    lines.append('];')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    return len(cmap), len(ranges)


def write_test_font(path, data, count):
    b64 = base64.b64encode(data).decode('ascii')
    chunks = [b64[i:i + 72] for i in range(0, len(b64), 72)]
    lines = [
        '// GENERATED by tool/fonts/make_note_sans.py --test-font — do not edit.',
        '// The small bundled test font of useInkTestFonts (m5-7/03-ink 4.12): NoteSans',
        '// Regular subset to ASCII U+0020-007E, the compatibility jamo and the syllables',
        '// of tool/fonts/test_font_chars.txt (%d code points, %d bytes).' % (count, len(data)),
        '// Exported only through testing.dart (never imported by an app library).',
        "import 'package:meta/meta.dart';",
        '',
        '/// sha256 %s' % hashlib.sha256(data).hexdigest(),
        '@internal',
        'const String inkTestFontBase64 =',
    ]
    for i, c in enumerate(chunks):
        end = ';' if i == len(chunks) - 1 else ''
        lines.append("    '%s'%s" % (c, end))
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--source', help='local NotoSansKR[wght].ttf (else downloaded)')
    parser.add_argument('--package', default='.', help='packages/ink_engine directory')
    parser.add_argument('--test-font', action='store_true',
                        help='also write lib/src/testing/ink_test_font.dart')
    args = parser.parse_args()
    if fontTools.version != FONTTOOLS_VERSION:
        sys.exit('fonttools %s needed (found %s)' % (FONTTOOLS_VERSION, fontTools.version))
    pkg = args.package
    source = read_source(args.source)
    cps = subset_code_points()
    print('subset: %d code points' % len(cps))
    regular = None
    for weight, style in WEIGHTS:
        data, inst = make_instance(source, weight, style, cps)
        out = os.path.join(pkg, 'assets', 'fonts', '%s-%s.ttf' % (FAMILY, style))
        with open(out, 'wb') as f:
            f.write(data)
        print('%s: %d B (gzip %d), %d glyphs, sha256 %s' % (
            out, len(data), len(gzip.compress(data, 9, mtime=0)),
            len(inst.getGlyphOrder()), hashlib.sha256(data).hexdigest()))
        if style == 'Regular':
            regular = inst
    count, nranges = write_coverage(
        os.path.join(pkg, 'lib', 'src', 'text', 'note_sans_coverage.dart'), regular)
    print('coverage: %d code points, %d ranges' % (count, nranges))
    if args.test_font:
        tcps = test_font_code_points(os.path.join(pkg, 'tool', 'fonts', 'test_font_chars.txt'))
        data, inst = make_instance(source, 400, 'Regular', tcps)
        write_test_font(os.path.join(pkg, 'lib', 'src', 'testing', 'ink_test_font.dart'),
                        data, len(inst.getBestCmap()))
        print('test font: %d code points, %d B (base64 %d), sha256 %s' % (
            len(inst.getBestCmap()), len(data), (len(data) + 2) // 3 * 4,
            hashlib.sha256(data).hexdigest()))


if __name__ == '__main__':
    main()
