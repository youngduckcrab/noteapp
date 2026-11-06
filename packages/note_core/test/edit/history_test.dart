// CORE 6.7 history rules (8.1 T5): 100 steps, redo cleared by a new edit, byte limit,
// no-op entries skipped, a pending undo cancelled by a new edit.
import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/edit/history.dart';
import 'package:note_core/src/session/session_backend.dart';
import 'package:note_core/src/session/session_engine.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

AppliedEdit _edit(String label, {int points = 0}) {
  final pts = StrokePoints.fromList([
    for (var i = 0; i < (points == 0 ? 1 : points); i++)
      StrokePoint(i.toDouble(), 0),
  ]);
  final s = Stroke(
    id: 's-$label',
    pageId: 'p',
    style: StrokeStyle.defaultsFor(PenTool.ballpoint),
    points: pts,
    createdAt: 0,
  );
  return AppliedEdit(
    label: label,
    deltas: [EntityDelta(kind: EntityKind.stroke, id: s.id, after: s)],
    version: Hlc.zero,
    affectedPageIds: const {'p'},
  );
}

void main() {
  group('EditHistory', () {
    test('the 101st push drops the oldest step', () {
      final h = EditHistory(const HistoryLimits());
      for (var i = 0; i < 101; i++) {
        h.push(_edit('e$i'));
      }
      expect(h.state.undoDepth, 100);
      expect(h.state.undoLabel, 'e100');
      // Walk down: the bottom entry is e1 (e0 was dropped).
      final labels = <String>[];
      while (h.undoTop != null) {
        labels.add(h.undoTop!.edit.label);
        h.dropUndoTop();
      }
      expect(labels.last, 'e1');
    });

    test('a new edit clears redo', () {
      final h = EditHistory(const HistoryLimits())
        ..push(_edit('a'))
        ..push(_edit('b'))
        ..moveUndoTopToRedo();
      expect(h.state.redoDepth, 1);
      h.push(_edit('c'));
      expect(h.state.redoDepth, 0);
      expect(h.state.undoDepth, 2);
      expect(h.state.canRedo, isFalse);
    });

    test('byte limit evicts the oldest steps but keeps the newest', () {
      final one = _edit('x', points: 1000).estimatedBytes;
      final h = EditHistory(HistoryLimits(maxBytes: one * 3));
      for (var i = 0; i < 5; i++) {
        h.push(_edit('e$i', points: 1000));
      }
      expect(h.state.undoDepth, 3);
      expect(h.state.retainedBytes, one * 3);
      final tiny = EditHistory(const HistoryLimits(maxBytes: 10))
        ..push(_edit('big', points: 1000));
      expect(
        tiny.state.undoDepth,
        1,
        reason: 'the step just pushed always stays',
      );
    });

    test('estimatedBytes: 96 per delta + point arrays, 256 per page delta', () {
      expect(_edit('x', points: 10).estimatedBytes, 96 + 10 * 24);
      const page = Page(
        id: 'p',
        noteId: 'n',
        sortKey: 'a0',
        size: PageSize.a4Portrait,
        background: BlankBackground(),
        createdAt: 0,
        updatedAt: 0,
      );
      const edit = AppliedEdit(
        label: 'p',
        deltas: [
          EntityDelta(
            kind: EntityKind.page,
            id: 'p',
            before: page,
            after: page,
          ),
        ],
        version: Hlc.zero,
        affectedPageIds: {'p'},
      );
      expect(edit.estimatedBytes, 256);
    });
  });

  group('session history', () {
    late NoteStore store;
    late NoteSession session;
    late PageId pageId;

    setUp(() async {
      store = createFakeNoteStore();
      final note = await store.library.createNote(title: 'h');
      session = await store.openSession(note.id);
      pageId = session.pages.single.id;
      await session.openPage(pageId);
    });

    tearDown(() async {
      await session.close();
      await store.close();
    });

    Stroke stroke(int seed) => StrokeFixtures.synthetic(
      pageId: pageId,
      ids: store.ids,
      seed: seed,
      createdAt: seed,
    );

    test(
      '101 executes keep 100 steps; 100 undos return to the first state',
      () async {
        final first = stroke(0);
        session.execute(AddStrokes(pageId: pageId, strokes: [first]));
        final initial = session.pageIfLoaded(pageId)!.strokes.toList();
        for (var i = 1; i <= 100; i++) {
          session.execute(
            TransformElements(
              pageId: pageId,
              elementIds: [first.id],
              transform: Affine2.translation(1, 0),
            ),
          );
        }
        expect(session.history.undoDepth, 100);
        for (var i = 0; i < 100; i++) {
          expect((await session.undo()).applied, isTrue);
        }
        expect((await session.undo()).applied, isFalse);
        final now = session.pageIfLoaded(pageId)!.strokes;
        expect(now, hasLength(1));
        expect(now.single.points.contentEquals(initial.single.points), isTrue);
      },
    );

    test('a new edit clears redo', () async {
      session.execute(AddStrokes(pageId: pageId, strokes: [stroke(1)]));
      await session.undo();
      expect(session.history.canRedo, isTrue);
      session.execute(AddStrokes(pageId: pageId, strokes: [stroke(2)]));
      expect(session.history.canRedo, isFalse);
    });

    test('execute while an undo is pending cancels the undo', () async {
      session.execute(AddStrokes(pageId: pageId, strokes: [stroke(1)]));
      final pending = session.undo();
      session.execute(AddStrokes(pageId: pageId, strokes: [stroke(2)]));
      final result = await pending;
      expect(result.applied, isFalse);
      expect(session.pageIfLoaded(pageId)!.strokeCount, 2);
      expect(session.history.undoDepth, 2);
    });

    test('two undos in a row both apply', () async {
      session
        ..execute(AddStrokes(pageId: pageId, strokes: [stroke(1)]))
        ..execute(AddStrokes(pageId: pageId, strokes: [stroke(2)]));
      final r = await Future.wait([session.undo(), session.undo()]);
      expect(r.map((x) => x.applied), [true, true]);
      expect(session.pageIfLoaded(pageId)!.strokeCount, 0);
      expect(session.history.redoDepth, 2);
    });
  });

  group('entries changed elsewhere (6.7.3)', () {
    // Two engines over one backend stand in for "another writer" (remote changes reach
    // the real store in CORE T10/T11; the fake store has no remote path).
    late _MapBackend backend;
    late SessionEngine a;
    late SessionEngine b;
    final ids = SequentialIdGenerator(prefix: 's');
    const note = Note(
      id: 'n',
      ownerId: 'local',
      title: 't',
      sortKey: 'a0',
      createdAt: 0,
      updatedAt: 0,
    );
    const page = Page(
      id: 'p',
      noteId: 'n',
      sortKey: 'a0',
      size: PageSize.a4Portrait,
      background: BlankBackground(),
      createdAt: 0,
      updatedAt: 0,
    );

    SessionEngine engine(String node) => SessionEngine(
      note: note,
      pages: const [page],
      backend: backend,
      options: const NoteSessionOptions(maxCachedPages: 0),
      hlc: HlcClock(nodeId: node, clock: const Clock()),
      clock: const Clock(),
      ids: ids,
    );

    setUp(() {
      backend = _MapBackend();
      a = engine('000000000000000a');
      b = engine('000000000000000b');
    });

    test('the changed entity is skipped, the rest is undone', () async {
      await a.openPage('p');
      final s1 = StrokeFixtures.synthetic(pageId: 'p', ids: ids, seed: 1);
      final s2 = StrokeFixtures.synthetic(pageId: 'p', ids: ids, seed: 2);
      a.execute(AddStrokes(pageId: 'p', strokes: [s1, s2]));
      a.closePage('p'); // evicted (maxCachedPages 0)
      await b.openPage('p');
      b.execute(
        RestyleStrokes(
          pageId: 'p',
          strokeIds: [s1.id],
          patch: const StrokeStylePatch(colorArgb: 0xFFFF0000),
        ),
      );
      final r = await a.undo();
      expect(r.applied, isTrue);
      expect(r.skippedEntities, 1);
      expect(r.edit!.deltas.single.id, s2.id);
      expect(
        backend.strokes[s1.id]!.isDeleted,
        isFalse,
        reason: "the other writer's change stays",
      );
      expect(backend.strokes[s2.id]!.isDeleted, isTrue);
    });

    test(
      'an entry whose entities all changed elsewhere is skipped as a whole',
      () async {
        await a.openPage('p');
        final s1 = StrokeFixtures.synthetic(pageId: 'p', ids: ids, seed: 1);
        a.execute(AddStrokes(pageId: 'p', strokes: [s1]));
        a.closePage('p');
        await b.openPage('p');
        b.execute(RemoveStrokes(pageId: 'p', strokeIds: [s1.id]));
        final r = await a.undo();
        expect(r.applied, isFalse);
        expect(r.skippedEntries, 1);
        expect(a.history.undoDepth, 0);
        expect(a.history.redoDepth, 0);
      },
    );
  });
}

final class _MapBackend implements SessionBackend {
  final Map<ElementId, Stroke> strokes = {};

  @override
  Future<({List<Stroke> strokes, List<PageObject> objects})> loadContent(
    PageId pageId,
  ) async => (
    strokes: [
      for (final s in strokes.values)
        if (s.pageId == pageId && !s.isDeleted) s,
    ],
    objects: const <PageObject>[],
  );

  @override
  Future<void> write(SessionWrite write) async {
    for (final e in write.entities) {
      if (e is Stroke) strokes[e.id] = e;
    }
  }

  @override
  Future<void> flush() async {}

  @override
  void sessionClosed(NoteId noteId) {}
}
