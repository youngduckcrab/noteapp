import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

Future<List<Stroke>> _strokes(NoteStore store, NoteId noteId) async => [
  for (final p in await store.content.pagesOf(noteId))
    ...(await store.content.loadPage(p.id)).strokes,
];

void main() {
  test(
    'pages: 3, strokesPerPage: 10 → 1 note, 3 pages, 30 strokes with widthQ',
    () async {
      final store = createFakeNoteStore();
      final id = await seedSyntheticNote(
        store,
        pages: 3,
        strokesPerPage: 10,
        pointsPerStroke: 50,
      );
      final note = (await store.library.getNote(id))!;
      expect(note.title, 'perf-test');
      expect(note.pageCount, 3);
      expect(await store.content.pagesOf(id), hasLength(3));
      final strokes = await _strokes(store, id);
      expect(strokes, hasLength(30));
      for (final s in strokes) {
        expect(s.points.length, 50);
        final q = {
          for (var i = 0; i < s.points.length; i++) s.points.widthQ(i),
        };
        expect(q.length, greaterThan(1), reason: 'widthQ channel varies');
        expect(s.points.maxWidthQ, inInclusiveRange(0.05, 1));
        expect(s.version, isNotNull);
      }
      final session = await store.openSession(id);
      expect(session.history.undoDepth, 0, reason: 'seeding is not undoable');
      await session.close();
      await store.close();
    },
  );

  test('the same seed gives the same points', () async {
    final a = createFakeNoteStore();
    final b = createFakeNoteStore();
    final idA = await seedSyntheticNote(
      a,
      pages: 2,
      strokesPerPage: 5,
      seed: 7,
    );
    final idB = await seedSyntheticNote(
      b,
      pages: 2,
      strokesPerPage: 5,
      seed: 7,
    );
    final sa = await _strokes(a, idA);
    final sb = await _strokes(b, idB);
    expect(sa, hasLength(10));
    for (var i = 0; i < sa.length; i++) {
      expect(sa[i].points.contentEquals(sb[i].points), isTrue);
    }
    final c = createFakeNoteStore();
    final idC = await seedSyntheticNote(
      c,
      pages: 2,
      strokesPerPage: 5,
      seed: 8,
    );
    final sc = await _strokes(c, idC);
    expect(sc.first.points.contentEquals(sa.first.points), isFalse);
    await a.close();
    await b.close();
    await c.close();
  });

  test('argument errors', () async {
    final store = createFakeNoteStore();
    await expectLater(seedSyntheticNote(store, pages: 0), throwsArgumentError);
    await store.close();
  });
}
