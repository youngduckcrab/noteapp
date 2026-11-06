# Third-party notices — ink_engine

## perfect-freehand

The stroke outline generator (`lib/src/geometry/outline_generator.dart`,
03-ink 6.8) is our own implementation. It follows the algorithm of
perfect-freehand: offset the smoothed centerline by the per-point radius on
both sides, and close the ends with round or flat caps. No source code is
copied. The Dart port `perfect_freehand` 2.5.2+1 is a dev dependency only,
used as the reference in `test/unit/geometry/outline_parity_test.dart`; it is
not part of the app.

```text
MIT License

Copyright (c) 2021 Stephen Ruiz
Copyright (c) 2023 Adil Hanney

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## NoteSans (Noto Sans KR subset) — SIL Open Font License 1.1

`assets/fonts/NoteSans-Regular.ttf` and `assets/fonts/NoteSans-Bold.ttf` (the
text box font, m5-7/03-ink 6.10.1) are a modified version of the Noto Sans KR
variable font (google/fonts `ofl/notosanskr/NotoSansKR[wght].ttf`): the weight
axis is pinned to 400 / 700, the glyphs are cut down to 2,674 code points and
the fonts are renamed to NoteSans, so the original font names are not used
for them. The small test font in `lib/src/testing/ink_test_font.dart` (test
helpers only) is a further subset of the regular weight. Copyright (c)
2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.
The license text is `assets/fonts/OFL.txt` (shipped with the app, which shows
it in its about screen); how the files are made is in
`assets/fonts/README.md`.

## flutter_math_fork and the KaTeX fonts

Formulas are laid out and drawn with `flutter_math_fork` 0.7.4 (a dependency,
Apache License 2.0 — its `LICENSE` file), which bundles the KaTeX fonts
(MIT License, Copyright (c) 2018 Khan Academy — its
`lib/katex_fonts/LICENSE`). INK copies no code from it. Flutter collects both
license texts into the app's license page from the packages themselves.
