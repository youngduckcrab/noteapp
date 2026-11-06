// 6.9.4 ② mergeIndexerResult step by step and 6.13.5 mergeConfirmed
// (m5-7/05-library 8.2 L2-10b; contract 7.2.5 HandwritingLine.userConfirmed
// comment): pure, synchronous merges on the STORED value. Keep boundary
// r = 0.8 / 0.79, added box = H / H + 0.01, dots only → kept, a new syllable
// → replaced with the old text first, two confirmed lines joined → the bigger
// pair, the smaller text among the alternatives, erased confirmed line →
// gone, fresh → null, null current, 5 alternatives, deterministic.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/indexer/line_reuse.dart';
import 'package:note_core/note_core.dart' as core;

const double kH = 20; // the line's glyph height H_G
const double kHs = 10; // the line's stroke height h_s

/// A stroke box: x from [x], 4 pt wide, [h] high, top 100.
core.PageRect box(double x, {double w = 4, double h = 10, double top = 100}) =>
    core.PageRect(x, top, x + w, top + h);

/// Ids s0..s(n-1) with boxes 8 pt apart.
Map<String, core.PageRect> strokes(
  int n, {
  String prefix = 's',
  double x0 = 0,
}) => {for (var i = 0; i < n; i++) '$prefix$i': box(x0 + 8 * i)};

core.PageRect unionOf(Iterable<core.PageRect> rects) =>
    rects.reduce((a, b) => a.expandToInclude(b));

core.HandwritingLine computedLine(
  Map<String, core.PageRect> boxes, {
  String text = '엔진',
  List<String> alternatives = const ['엔진?', '엔진!'],
}) => core.HandwritingLine(
  text: text,
  alternatives: alternatives,
  rect: unionOf(boxes.values),
  strokeIds: boxes.keys.toList(),
);

LineGeometry geometryOf(Map<String, core.PageRect> boxes) =>
    LineGeometry(strokeBoxes: boxes, strokeHeight: kHs, glyphHeight: kH);

IndexerResult result(
  List<Map<String, core.PageRect>> lines, {
  List<core.HandwritingLine>? computed,
  String rev = 'rev-new',
  String lang = 'ko',
}) => IndexerResult(
  rev: rev,
  lang: lang,
  engineId: 'fake:$lang',
  lines: computed ?? [for (final l in lines) computedLine(l)],
  geometry: [for (final l in lines) geometryOf(l)],
  nowMs: 5000,
);

core.HandwritingLine confirmedLine(
  Iterable<String> ids, {
  String text = '확정',
  List<String> alternatives = const ['후보'],
}) => core.HandwritingLine(
  text: text,
  alternatives: alternatives,
  rect: const core.PageRect(0, 0, 1, 1),
  strokeIds: ids.toList(),
  languageTag: 'ko',
  userConfirmed: true,
);

core.HandwritingText stored(
  List<core.HandwritingLine> lines, {
  String rev = 'rev-old',
  String engineId = 'fake:ko',
}) => core.HandwritingText(
  noteId: 'n',
  pageId: 'p',
  engineId: engineId,
  sourceRev: rev,
  lines: lines,
  createdAt: 1000,
);

core.HandwritingText? merge(core.HandwritingText? current, IndexerResult r) =>
    mergeIndexerResult(current, r, noteId: 'n', pageId: 'p');

void main() {
  group('step 1 · step 5', () {
    test('current fresh (same sourceRev and language, any engine) → null', () {
      final r = result([strokes(3)]);
      expect(merge(stored(const [], rev: 'rev-new'), r), isNull);
      expect(
        merge(
          stored(
            const [],
            rev: 'rev-new',
            engineId: 'mlkit-digital-ink/19.0.0:ko',
          ),
          r,
        ),
        isNull,
      );
    });

    test('same sourceRev, another language → not fresh', () {
      final r = result([strokes(3)]);
      final out = merge(
        stored(const [], rev: 'rev-new', engineId: 'fake:en'),
        r,
      )!;
      expect(out.engineId, 'fake:ko');
    });

    test('current null → the computed lines; createdAt = updatedAt = now', () {
      final r = result([strokes(3), strokes(2, prefix: 't', x0: 100)]);
      final out = merge(null, r)!;
      expect(out.id, core.HandwritingText.idFor('p'));
      expect(out.noteId, 'n');
      expect(out.sourceRev, 'rev-new');
      expect(out.engineId, 'fake:ko');
      expect(out.lines, r.lines);
      expect(out.createdAt, 5000);
      expect(out.updatedAt, 5000);
    });

    test('stale current without confirmed lines → the computed lines only '
        '(engine lines of current are not carried over); createdAt kept', () {
      final r = result([strokes(3)]);
      final current = stored([
        core.HandwritingLine(
          text: '옛 엔진 글',
          rect: const core.PageRect(0, 0, 1, 1),
          strokeIds: const ['s0', 'old'],
        ),
      ]);
      final out = merge(current, r)!;
      expect(out.lines, r.lines);
      expect(out.createdAt, 1000);
      expect(out.updatedAt, 5000);
    });
  });

  group('step 2–3: keep or replace a confirmed line', () {
    test('r = 0.8 → kept; r = 0.79 → replaced', () {
      // 100 confirmed strokes; the computed line has 80 (or 79) of them.
      final all = strokes(100);
      Map<String, core.PageRect> first(int n) =>
          Map.fromEntries(all.entries.take(n));
      final current = stored([confirmedLine(all.keys)]);

      final kept = merge(current, result([first(80)]))!.lines.single;
      expect(kept.text, '확정');
      expect(kept.userConfirmed, isTrue);
      expect(kept.alternatives, ['후보']);
      expect(kept.strokeIds, first(80).keys);
      expect(kept.rect, unionOf(first(80).values));

      final replaced = merge(current, result([first(79)]))!.lines.single;
      expect(replaced.text, '엔진');
      expect(replaced.userConfirmed, isFalse);
      expect(replaced.alternatives, ['확정', '엔진?', '엔진!']);
    });

    test('an added box of exactly H → kept; H + 0.01 → replaced', () {
      final base = strokes(10);
      final current = stored([confirmedLine(base.keys)]);
      Map<String, core.PageRect> plus(double h) => {
        ...base,
        'add': box(200, w: 2, h: h),
      };
      expect(merge(current, result([plus(kH)]))!.lines.single.text, '확정');
      expect(
        merge(current, result([plus(kH + 0.01)]))!.lines.single.text,
        '엔진',
      );
    });

    test('dots only (a full stop, the dot of an i) → kept', () {
      final base = strokes(10);
      final current = stored([confirmedLine(base.keys)]);
      final out = merge(
        current,
        result([
          {
            ...base,
            'dot1': box(90, w: 1.5, h: 1.5, top: 108),
            'dot2': box(30, w: 1.5, h: 1.5, top: 90),
          },
        ]),
      )!.lines.single;
      expect(out.text, '확정');
      expect(out.userConfirmed, isTrue);
      expect(out.strokeIds, hasLength(12));
    });

    test('a new syllable (strokes joined into a box > H) → replaced, the old '
        'confirmed text first among the alternatives', () {
      final base = strokes(10);
      final current = stored([confirmedLine(base.keys)]);
      // Three overlapping strokes: together 24 pt wide (> H = 20).
      final syllable = {
        'n0': box(200, w: 10, h: 18),
        'n1': box(206, w: 10, h: 18),
        'n2': box(214, w: 10, h: 18),
      };
      final out = merge(
        current,
        result([
          {...base, ...syllable},
        ]),
      )!.lines.single;
      expect(out.text, '엔진');
      expect(out.userConfirmed, isFalse);
      expect(out.alternatives.first, '확정');
    });

    test('alternatives: no duplicates, never the text itself, at most 5', () {
      final base = strokes(4);
      final current = stored([confirmedLine(base.keys, text: 'B')]);
      final computed = computedLine(
        {...base, 'big': box(100, w: 40, h: 40)},
        text: 'A',
        alternatives: const ['B', 'C', 'A', 'D', 'E'],
      );
      final out = merge(
        current,
        result(
          [
            {...base, 'big': box(100, w: 40, h: 40)},
          ],
          computed: [computed],
        ),
      )!.lines.single;
      expect(out.text, 'A');
      expect(out.alternatives, ['B', 'C', 'D', 'E']);

      final many = computedLine(
        {...base, 'big': box(100, w: 40, h: 40)},
        alternatives: const ['1', '2', '3', '4', '5'],
      );
      final capped = merge(
        current,
        result(
          [
            {...base, 'big': box(100, w: 40, h: 40)},
          ],
          computed: [many],
        ),
      )!.lines.single;
      expect(capped.alternatives, ['B', '1', '2', '3', '4']);
    });
  });

  group('step 2 · 4: pairs, joined lines, erased lines', () {
    test('two confirmed lines joined into one → the bigger pair decides, the '
        'smaller text follows among the alternatives', () {
      final big = strokes(6);
      final small = {
        't0': box(100, w: 12, h: 24),
        't1': box(110, w: 12, h: 24),
        't2': box(120, w: 12, h: 24),
      };
      final current = stored([
        confirmedLine(big.keys, text: '큰 줄'),
        confirmedLine(small.keys, text: '작은 줄'),
      ]);
      final out = merge(
        current,
        result([
          {...big, ...small},
        ]),
      )!.lines.single;
      // The small line's strokes are big additions (> H): replaced.
      expect(out.text, '엔진');
      expect(out.userConfirmed, isFalse);
      expect(out.alternatives.take(2), ['큰 줄', '작은 줄']);
    });

    test('joined into a line that keeps the bigger confirmed text → the '
        'smaller text is not added', () {
      final big = strokes(10);
      final current = stored([
        confirmedLine(big.keys, text: '큰 줄'),
        confirmedLine(['dot'], text: '점'),
      ]);
      final out = merge(
        current,
        result([
          {...big, 'dot': box(90, w: 1, h: 1)},
        ]),
      )!.lines.single;
      expect(out.text, '큰 줄');
      expect(out.userConfirmed, isTrue);
      expect(out.alternatives, ['후보']);
    });

    test('a confirmed line whose strokes were all erased is dropped', () {
      final other = strokes(5, prefix: 'o');
      final current = stored([
        confirmedLine(['gone1', 'gone2'], text: '지워진 줄'),
      ]);
      final out = merge(current, result([other]))!;
      expect(out.lines.single.text, '엔진');
      expect(out.lines.single.alternatives, isNot(contains('지워진 줄')));
    });

    test('pairs by shared strokes, then reading order; lines keep the '
        'computed reading order', () {
      final l1 = strokes(4, prefix: 'a');
      final l2 = strokes(4, prefix: 'b', x0: 100);
      final current = stored([
        confirmedLine(l2.keys, text: '둘째'),
        confirmedLine(l1.keys, text: '첫째'),
      ]);
      final out = merge(current, result([l1, l2]))!;
      expect(out.lines.map((l) => l.text), ['첫째', '둘째']);
      expect(out.lines.every((l) => l.userConfirmed), isTrue);
    });

    test('deterministic: the same input gives the same value', () {
      final l1 = strokes(4, prefix: 'a');
      final l2 = strokes(3, prefix: 'b', x0: 100);
      final current = stored([
        confirmedLine([...l1.keys, 'b0'], text: '첫째'),
        confirmedLine(['b1', 'b2'], text: '둘째'),
      ]);
      final first = merge(current, result([l1, l2]));
      final second = merge(current, result([l1, l2]));
      expect(first, second);
      expect(first!.toJson(), second!.toJson());
    });
  });

  group('mergeConfirmed (6.13.5)', () {
    core.HandwritingLine engineLine(
      List<String> ids,
      String text,
      double top,
    ) => core.HandwritingLine(
      text: text,
      rect: core.PageRect(0, top, 100, top + 20),
      strokeIds: ids,
    );

    test('replaces the stored lines it overlaps, keeps the others, sorts by '
        'rect; all → rev and engine of the sheet', () {
      final current = stored([
        engineLine(['a', 'b'], '첫 줄', 0),
        engineLine(['c'], '둘째 줄', 40),
        engineLine(['d'], '셋째 줄', 80),
      ]);
      final converted = core.HandwritingLine(
        text: '고친 둘째 줄',
        alternatives: const ['고친 둘째 줄', '후보1'],
        rect: const core.PageRect(0, 40, 100, 60),
        strokeIds: const ['c', 'b'],
      );
      final out = mergeConfirmed(
        current,
        [converted],
        noteId: 'n',
        pageId: 'p',
        rev: 'rev-sheet',
        all: true,
        engineId: 'fake:ko',
        nowMs: 7000,
      );
      expect(out.lines.map((l) => l.text), ['고친 둘째 줄', '셋째 줄']);
      expect(out.lines.first.userConfirmed, isTrue);
      expect(out.lines.first.alternatives, ['후보1']);
      expect(out.sourceRev, 'rev-sheet');
      expect(out.engineId, 'fake:ko');
      expect(out.createdAt, 1000);
      expect(out.updatedAt, 7000);
    });

    test('a part of the page → sourceRev and engine id stay', () {
      final current = stored([
        engineLine(['a'], '첫 줄', 0),
      ], engineId: 'x:ko');
      final out = mergeConfirmed(
        current,
        [
          engineLine(['z'], '새 줄', 40),
        ],
        noteId: 'n',
        pageId: 'p',
        rev: 'rev-sheet',
        all: false,
        engineId: 'fake:ko',
        nowMs: 7000,
      );
      expect(out.sourceRev, 'rev-old');
      expect(out.engineId, 'x:ko');
      expect(out.lines.map((l) => l.text), ['첫 줄', '새 줄']);
      final fromNothing = mergeConfirmed(
        null,
        [
          engineLine(['z'], '새 줄', 40),
        ],
        noteId: 'n',
        pageId: 'p',
        rev: 'rev-sheet',
        all: false,
        engineId: 'fake:ko',
        nowMs: 7000,
      );
      expect(fromNothing.sourceRev, '');
      expect(fromNothing.engineId, 'fake:ko');
      expect(fromNothing.createdAt, 7000);
    });
  });
}
