// 6.9.4 ① line reuse, row by row (m5-7/05-library 8.2 L2-10b): a stored line
// with exactly the new group's stroke set, confirmed or of the job's
// language, is reused with the new rect (moved / recoloured strokes keep
// their text) — the engine id is not looked at; anything else is recognized.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/indexer/line_reuse.dart';
import 'package:note_core/note_core.dart' as core;

const core.PageRect oldRect = core.PageRect(10, 10, 100, 30);
const core.PageRect newRect = core.PageRect(20, 40, 110, 60);

core.HandwritingText stored(
  List<core.HandwritingLine> lines, {
  String engineId = 'fake:ko',
}) => core.HandwritingText(
  noteId: 'n',
  pageId: 'p',
  engineId: engineId,
  sourceRev: '0000000000000000',
  lines: lines,
  createdAt: 1,
);

core.HandwritingLine line(
  List<String> ids, {
  String text = '회의',
  String lang = 'ko',
  bool confirmed = false,
}) => core.HandwritingLine(
  text: text,
  alternatives: const ['회의?'],
  rect: oldRect,
  strokeIds: ids,
  languageTag: lang,
  userConfirmed: confirmed,
);

void main() {
  test('same stroke set, same language → reused with the new rect and the '
      "group's stroke order", () {
    final reuse = LineReuse(
      stored([
        line(['a', 'b', 'c']),
      ]),
    );
    final out = reuse.reuse(['c', 'a', 'b'], 'ko', newRect)!;
    expect(out.text, '회의');
    expect(out.alternatives, ['회의?']);
    expect(out.rect, newRect);
    expect(out.strokeIds, ['c', 'a', 'b']);
    expect(out.languageTag, 'ko');
    expect(out.userConfirmed, isFalse);
  });

  test('same stroke set, confirmed, another language → reused (the user '
      'chose that text)', () {
    final reuse = LineReuse(
      stored([
        line(['a', 'b'], text: 'Meeting', lang: 'en', confirmed: true),
      ]),
    );
    final out = reuse.reuse(['a', 'b'], 'ko', newRect)!;
    expect(out.text, 'Meeting');
    expect(out.languageTag, 'en');
    expect(out.userConfirmed, isTrue);
    expect(out.rect, newRect);
  });

  test('same stroke set, not confirmed, another language → recognize', () {
    final reuse = LineReuse(
      stored([
        line(['a', 'b'], lang: 'en'),
      ]),
    );
    expect(reuse.reuse(['a', 'b'], 'ko', newRect), isNull);
  });

  test('another stroke set (fewer, more, one swapped) → recognize, even for '
      'a confirmed line', () {
    final reuse = LineReuse(
      stored([
        line(['a', 'b', 'c'], confirmed: true),
      ]),
    );
    expect(reuse.reuse(['a', 'b'], 'ko', newRect), isNull);
    expect(reuse.reuse(['a', 'b', 'c', 'd'], 'ko', newRect), isNull);
    expect(reuse.reuse(['a', 'b', 'x'], 'ko', newRect), isNull);
  });

  test('another engine id / version / device does not matter', () {
    final reuse = LineReuse(
      stored([
        line(['a']),
      ], engineId: 'mlkit-digital-ink-ios/9.0.0:ko'),
    );
    expect(reuse.reuse(['a'], 'ko', newRect)?.text, '회의');
  });

  test('several lines: each group finds its own; nothing stored → null', () {
    final reuse = LineReuse(
      stored([
        line(['a', 'b'], text: '첫 줄'),
        line(['c'], text: '둘째 줄'),
      ]),
    );
    expect(reuse.reuse(['c'], 'ko', newRect)?.text, '둘째 줄');
    expect(reuse.reuse(['b', 'a'], 'ko', newRect)?.text, '첫 줄');
    expect(LineReuse(null).reuse(['a'], 'ko', newRect), isNull);
  });
}
