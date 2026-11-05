// CORE 6.7.5: partial-eraser gesture = one command = one undo step, and undo / redo chains.
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

void main() {
  late NoteStore store;
  late NoteSession session;
  late PageId pageId;

  setUp(() async {
    store = createFakeNoteStore();
    final note = await store.library.createNote(title: 'chain');
    session = await store.openSession(note.id);
    pageId = session.pages.single.id;
    await session.openPage(pageId);
  });

  tearDown(() async {
    await session.close();
    await store.close();
  });

  List<Stroke> current() => session.pageIfLoaded(pageId)!.strokes;

  test('5 strokes cut → 1 execute → 1 undo restores them → redo restores 7 fragments', () async {
    final originals = StrokeFixtures.manySynthetic(
      pageId: pageId,
      ids: store.ids,
      count: 5,
    );
    session.execute(AddStrokes(pageId: pageId, strokes: originals));
    final before = current().toList();
    final fragments = <Stroke>[
      for (final s in originals)
        s.fragment(id: store.ids.newId(), points: s.points.sublist(0, 20)),
      originals[0].fragment(
        id: store.ids.newId(),
        points: originals[0].points.sublist(60),
      ),
      originals[3].fragment(
        id: store.ids.newId(),
        points: originals[3].points.sublist(70),
      ),
    ];
    session.execute(
      SplitStrokes(
        pageId: pageId,
        removedIds: [for (final s in originals) s.id],
        added: fragments,
      ),
    );
    expect(current(), hasLength(7));
    expect(session.history.undoDepth, 2);

    final undo = await session.undo();
    expect(undo.applied, isTrue);
    expect(session.history.undoDepth, 1);
    final restored = current();
    expect(
      restored.map((s) => s.id),
      before.map((s) => s.id),
      reason: 'same drawing order',
    );
    for (var i = 0; i < restored.length; i++) {
      expect(restored[i].points.contentEquals(before[i].points), isTrue);
      expect(restored[i].style, before[i].style);
    }

    final redo = await session.redo();
    expect(redo.applied, isTrue);
    expect(current().map((s) => s.id).toSet(), {
      for (final f in fragments) f.id,
    });
    // Fragments keep the z-order of their originals (createdAt inherited).
    expect(current().first.createdAt, originals.first.createdAt);
  });

  test('add → split → undo → undo', () async {
    final s = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
    session.execute(AddStrokes(pageId: pageId, strokes: [s]));
    final piece = s.fragment(
      id: store.ids.newId(),
      points: s.points.sublist(10, 30),
    );
    session.execute(
      SplitStrokes(pageId: pageId, removedIds: [s.id], added: [piece]),
    );
    expect(current().single.id, piece.id);
    expect((await session.undo()).applied, isTrue);
    expect(current().single.id, s.id);
    final second = await session.undo();
    expect(second.applied, isTrue);
    expect(second.skippedEntities, 0);
    expect(current(), isEmpty);
    expect(session.history.redoDepth, 2);
    // and forward again
    expect((await session.redo()).applied, isTrue);
    expect(current().single.id, s.id);
    expect((await session.redo()).applied, isTrue);
    expect(current().single.id, piece.id);
  });

  test('add → transform → undo×2 → redo×2 ends in the same state', () async {
    final s = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
    session.execute(AddStrokes(pageId: pageId, strokes: [s]));
    session.execute(
      TransformElements(
        pageId: pageId,
        elementIds: [s.id],
        transform: Affine2.rotation(
          0.5,
          originX: 100,
          originY: 100,
        ).then(Affine2.scaling(1.5, 1.5)),
      ),
    );
    final transformed = current().single;
    await session.undo();
    expect(current().single.points.contentEquals(s.points), isTrue);
    await session.undo();
    expect(current(), isEmpty);
    await session.redo();
    expect(current().single.points.contentEquals(s.points), isTrue);
    await session.redo();
    final again = current().single;
    expect(again.points.contentEquals(transformed.points), isTrue);
    expect(again.style, transformed.style);
    expect(session.history.undoDepth, 2);
    expect(session.history.redoDepth, 0);
    // The store has the same final state after the writes commit.
    await session.flush();
    final stored = await store.content.loadPage(pageId);
    expect(
      stored.strokes.single.points.contentEquals(transformed.points),
      isTrue,
    );
  });

  test('undo/redo results report what was written', () async {
    final s = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
    session.execute(AddStrokes(pageId: pageId, strokes: [s]));
    final r = await session.undo();
    expect(r.edit!.label, 'add-strokes');
    expect(r.affectedPageIds, {pageId});
    expect((r.edit!.deltas.single.after! as Stroke).isDeleted, isTrue);
    final changes = <ChangeOrigin>[];
    final sub = store.changes.listen((b) => changes.add(b.origin));
    await session.redo();
    await session.flush();
    await Future<void>.value();
    expect(changes, contains(ChangeOrigin.redo));
    await sub.cancel();
  });
}
