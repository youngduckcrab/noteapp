# NoteSans — text box fonts of ink_engine

Repository documentation, not an app asset: `pubspec.yaml` lists the three font
files one by one (`NoteSans-Regular.ttf`, `NoteSans-Bold.ttf`, `OFL.txt`), so this
README never reaches the app bundle or the web build (m5-7/03-ink 3.1).

| File | Bytes | sha256 |
|---|---|---|
| `NoteSans-Regular.ttf` (wght 400) | 466,936 | `b8acd7a98e83b4f8c87bb8b09a3513174df51547d4a0d8cfb82a732b700c1041` |
| `NoteSans-Bold.ttf` (wght 700) | 466,440 | `f53c538560aed1bee635913515157005bcb7bbbdcbc864cc9ee96cd29a1fc624` |
| `OFL.txt` | 4,388 | `1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9` |

gzip -9: Regular 213,615 B, Bold 216,764 B. 2,718 glyphs each.

## Source

Noto Sans KR variable font, SIL Open Font License 1.1 (`OFL.txt` is the license text
from the same directory):

- `https://raw.githubusercontent.com/google/fonts/24ddc1f324cac5d9f5aedca126d298f56e3f1640/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf`
- 10,414,588 B, sha256 `194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252`

The address pins the google/fonts commit that was `main` on 2026-11-06. The sha256
check in the tool guarantees the same bytes whichever commit serves them.

## Modified version

The fonts are a modified version under OFL 1.1: they are renamed to **NoteSans**
(name IDs 1, 2, 3, 4 and 6; the typographic and variation names 16, 17, 21, 22, 25
and 256+ are removed), so the original names ("Noto Sans KR", the reserved name
"Source") are not used for them.

Subset (2,674 code points):

- ASCII U+0020–007E, Latin-1 U+00A0–00FF
- Hangul compatibility jamo U+3131–318E
- the 2,350 Hangul syllables of KS X 1001 (encoded by EUC-KR in two bytes)
- 40 punctuation marks and symbols: ‘’“”…·–—•※→←↑↓、。「」『』〈〉《》【】₩℃№™①–⑩

Layout features kept: kern, liga, calt, ccmp, locl, mark, mkmk. No hinting.
`lib/src/text/note_sans_coverage.dart` holds the code point ranges of the subset
(`InkFonts.covers`); `test/unit/text/coverage_table_test.dart` checks it against the
`cmap` of `NoteSans-Regular.ttf`.

## Regenerate

From `packages/ink_engine`, with fonttools **4.67.0** (no brotli: TTF only):

```sh
python3 -m venv /tmp/fontvenv
/tmp/fontvenv/bin/pip install fonttools==4.67.0
/tmp/fontvenv/bin/python tool/fonts/make_note_sans.py --test-font
```

`--source <file>` uses a local copy of the source font instead of downloading it.
The tool saves with `recalcTimestamp=False`, so two runs give the same bytes (the
hashes above). `--test-font` also writes `lib/src/testing/ink_test_font.dart`, the
small test font of `useInkTestFonts` (ASCII + compatibility jamo + the syllables of
`tool/fonts/test_font_chars.txt`, regular only — 432 code points, 64,452 B, sha256
`fc5f897a721e9941e4c015b5730de92019feda5b2c2cd2d1d8ca8638ab804aff`).
