// CORE T11 — undo / redo next to remote changes on the SQLite store (6.7.3, F-08 'only
// the edits of this device'): an entity changed or deleted remotely since the step is
// skipped, the rest of the step applies; a step left with nothing is skipped as a whole.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:test/test.dart';

import 'undo_support.dart';

void main() {
  late UndoFixture f;
  setUp(() async => f = await UndoFixture.open());
  tearDown(() => f.close());

  test('undo of an add: a stroke deleted remotely is skipped, the other one is '
      'removed', () async {
    final a = f.stroke(seed: 1), b = f.stroke(seed: 2);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a, b]));
    await f.remote([f.current(a.id).copyWith(deletedAt: 77)]);
    final remoteRow = await f.row(a.id);
    await f.store.db.delete(f.store.db.outbox).go();

    final result = await f.session.undo();
    await f.session.flush();
    expect(result.applied, isTrue);
    expect(result.skippedEntities, 1);
    expect(result.edit!.deltas.map((d) => d.id), [b.id]);
    final content = f.session.pageIfLoaded(f.pageId)!;
    expect(content.strokes, isEmpty);
    expect(
      (await f.row(a.id)).versions,
      remoteRow.versions,
      reason: 'untouched',
    );
    expect((await f.row(a.id)).entity.deletedAt, 77);
    expect((await f.row(b.id)).entity.deletedAt, isNotNull);
    expect([for (final e in await readOutbox(f.store.db)) e.entityId], [b.id]);
  });

  test('undo of a move: a stroke restyled remotely keeps its remote style and '
      'position; the other stroke moves back', () async {
    final a = f.stroke(seed: 1), b = f.stroke(seed: 2);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a, b]));
    final added = {a.id: f.current(a.id), b.id: f.current(b.id)};
    await f.run(
      TransformElements(
        pageId: f.pageId,
        elementIds: [a.id, b.id],
        transform: Affine2.translation(40, 0),
      ),
    );
    final movedA = f.current(a.id);
    final recolored = movedA.copyWith(
      style: movedA.style.copyWith(colorArgb: 0xFF00FF00),
    );
    await f.remote([recolored]);

    final result = await f.session.undo();
    await f.session.flush();
    expect(result.skippedEntities, 1);
    final nowA = f.current(a.id), nowB = f.current(b.id);
    expect(nowA.style.colorArgb, 0xFF00FF00);
    expect(nowA.points.contentEquals(movedA.points), isTrue);
    expect(nowB.points.contentEquals(added[b.id]!.points), isTrue);
    final stored = await f.store.content.loadPage(f.pageId);
    expect(stored.strokeById(a.id)!.style.colorArgb, 0xFF00FF00);
    expect(
      stored.strokeById(b.id)!.points.contentEquals(added[b.id]!.points),
      isTrue,
    );
    // The next undo (the add) still removes both: a's add is this device's edit and
    // its current content is the remote one — skipped; b is removed.
    final second = await f.session.undo();
    await f.session.flush();
    expect(second.skippedEntities, 1);
    expect(f.session.pageIfLoaded(f.pageId)!.strokeById(b.id), isNull);
    expect(f.session.pageIfLoaded(f.pageId)!.strokeById(a.id), isNotNull);
  });

  test('a step whose every entity changed remotely is skipped as a whole; undo '
      'goes on with the step below', () async {
    final a = f.stroke(seed: 1), b = f.stroke(seed: 2);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a]));
    await f.run(AddStrokes(pageId: f.pageId, strokes: [b]));
    await f.remote([f.current(b.id).copyWith(deletedAt: 5)]);

    final result = await f.session.undo();
    await f.session.flush();
    expect(result.applied, isTrue);
    expect(result.skippedEntries, 1);
    expect(result.edit!.deltas.single.id, a.id);
    expect(f.session.pageIfLoaded(f.pageId)!.strokes, isEmpty);
    expect(f.session.history.undoDepth, 0);
    expect(f.session.history.redoDepth, 1, reason: 'only the applied step');
  });

  test('redo skips an entity changed remotely after the undo', () async {
    final a = f.stroke(seed: 1), b = f.stroke(seed: 2);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a, b]));
    await f.session.undo();
    await f.session.flush();
    // Another device brings a back with its own content.
    final undone = (await f.row(a.id)).entity as Stroke;
    await f.remote([undone.copyWith(clearDeletedAt: true)]);
    expect(f.session.pageIfLoaded(f.pageId)!.strokeById(a.id), isNotNull);

    final result = await f.session.redo();
    await f.session.flush();
    expect(result.applied, isTrue);
    expect(result.skippedEntities, 1);
    expect(result.edit!.deltas.single.id, b.id);
    expect(f.session.pageIfLoaded(f.pageId)!.strokes, hasLength(2));
  });

  test('remote changes of other entities do not affect undo', () async {
    final a = f.stroke(seed: 1), other = f.stroke(seed: 9);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [other]));
    f.session.clearHistory();
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a]));
    final o = f.current(other.id);
    await f.remote([o.copyWith(style: o.style.copyWith(width: 12))]);
    final result = await f.session.undo();
    await f.session.flush();
    expect(result.skippedEntities, 0);
    expect(f.session.pageIfLoaded(f.pageId)!.strokeById(a.id), isNull);
    expect(f.current(other.id).style.width, 12);
  });

  test('remote changes are not history steps', () async {
    final a = f.stroke(seed: 1);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a]));
    final history = f.session.history;
    await f.remote([f.stroke(seed: 3)]);
    expect(f.session.history, history);
  });
}
