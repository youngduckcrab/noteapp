// (v2) groupContentHits / focusRectOf / ContentHitGroup (05-library 4.4.10, 6.1.2,
// 6.1.4 — L2-01) on hand-made PageSearchHit lists.
import 'dart:ui' show Rect;

import 'package:feature_library/src/model/content.dart';
import 'package:feature_library/src/model/content_hits.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

PageSearchHit hit(
  String note,
  String page, {
  SearchSource source = SearchSource.text,
  List<PageRect> rects = const [],
  double score = 1,
}) => PageSearchHit(
  noteId: note,
  pageId: page,
  source: source,
  snippet: '$note $page',
  matchRange: (0, 1),
  rects: rects,
  score: score,
);

List<String> shape(List<ContentHitGroup> groups) => [
  for (final g in groups)
    '${g.noteId}: ${g.hits.map((h) => h.pageId).join(', ')}',
];

void main() {
  group('groupContentHits', () {
    test('6.1.2 example: stable by first hit, CORE order inside', () {
      final groups = groupContentHits([
        hit('A', 'p3', score: 9),
        hit('B', 'p1', score: 8),
        hit('A', 'p1', score: 7),
        hit('C', 'p2', score: 6),
        hit('B', 'p4', score: 5),
      ]);
      expect(shape(groups), ['A: p3, p1', 'B: p1, p4', 'C: p2']);
    });

    test('never re-sorts: a lower score first stays first', () {
      final groups = groupContentHits([
        hit('A', 'p1', score: 1),
        hit('A', 'p2', score: 5),
        hit('B', 'p1', score: 9),
      ]);
      expect(shape(groups), ['A: p1, p2', 'B: p1']);
      expect(groups.first.hits.map((h) => h.score), [1, 5]);
    });

    test('empty list → no groups', () {
      expect(groupContentHits(const []), isEmpty);
    });

    test('a repeated (note, page) is kept as CORE sent it', () {
      final groups = groupContentHits([
        hit('A', 'p1', source: SearchSource.ink),
        hit('A', 'p1', source: SearchSource.text),
      ]);
      expect(shape(groups), ['A: p1, p1']);
    });

    test('the result and its hit lists are unmodifiable', () {
      final groups = groupContentHits([hit('A', 'p1')]);
      expect(() => groups.add(groups.first), throwsUnsupportedError);
      expect(() => groups.first.hits.clear(), throwsUnsupportedError);
    });

    test('ContentHitGroup ==, hashCode, toString', () {
      final a = ContentHitGroup(noteId: 'A', hits: [hit('A', 'p1')]);
      final b = ContentHitGroup(noteId: 'A', hits: [hit('A', 'p1')]);
      final c = ContentHitGroup(noteId: 'A', hits: [hit('A', 'p2')]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), 'ContentHitGroup(A, 1 hits)');
    });
  });

  group('focusRectOf', () {
    test('union of the rects (note page pt)', () {
      final h = hit(
        'A',
        'p1',
        source: SearchSource.ink,
        rects: const [
          PageRect(40, 100, 420, 140),
          PageRect(10, 160, 300, 220),
          PageRect(50, 90, 60, 95),
        ],
      );
      expect(focusRectOf(h), const Rect.fromLTRB(10, 90, 420, 220));
    });

    test('one rect → that rect', () {
      expect(
        focusRectOf(hit('A', 'p1', rects: const [PageRect(1, 2, 3, 4)])),
        const Rect.fromLTRB(1, 2, 3, 4),
      );
    });

    test('empty rects → null', () {
      expect(focusRectOf(hit('A', 'p1')), isNull);
    });
  });

  group('LibraryContent v2', () {
    const section = SearchSection('q', returnTo: FolderSection(null));
    final groups = [
      ContentHitGroup(noteId: 'A', hits: [hit('A', 'p1')]),
    ];

    test('defaults: no content groups, not truncated', () {
      const c = LibraryContent(section: section);
      expect(c.contentGroups, isEmpty);
      expect(c.contentTruncated, isFalse);
      expect(c.isEmpty, isTrue);
    });

    test('content groups alone are not empty', () {
      final c = LibraryContent(section: section, contentGroups: groups);
      expect(c.isEmpty, isFalse);
      expect(c.orderedKeys, isEmpty);
    });

    test('== and hashCode include both new fields', () {
      final a = LibraryContent(section: section, contentGroups: groups);
      final b = LibraryContent(
        section: section,
        contentGroups: [
          ContentHitGroup(noteId: 'A', hits: [hit('A', 'p1')]),
        ],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const LibraryContent(section: section)));
      expect(
        a,
        isNot(
          LibraryContent(
            section: section,
            contentGroups: groups,
            contentTruncated: true,
          ),
        ),
      );
    });
  });
}
