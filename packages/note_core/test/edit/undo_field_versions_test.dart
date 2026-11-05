// CORE T11 — undo / redo writes on the SQLite store (6.7.6): only the JSON keys that
// really differ get the new HLC and go to the outbox, the other field versions stay;
// 100 steps undone give back the initial page (contentEquals); aliases leave the
// history with the last step touching their entity (6.7.3).
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/edit/history.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:test/test.dart';

import 'undo_support.dart';

void main() {
  late UndoFixture f;
  tearDown(() => f.close());

  Future<Set<String>> outboxFieldsOf(ElementId id) async =>
      (await readOutbox(f.store.db))
          .singleWhere((e) => e.entityId == id)
          .changedFields;

  Future<void> ack() => f.store.db.delete(f.store.db.outbox).go();

  test(
    'undo of a move writes {points} only; the style keeps its version',
    () async {
      f = await UndoFixture.open();
      final a = f.stroke(seed: 1);
      await f.run(AddStrokes(pageId: f.pageId, strokes: [a]));
      final added = await f.row(a.id);
      await f.run(
        TransformElements(
          pageId: f.pageId,
          elementIds: [a.id],
          transform: Affine2.translation(10, 5),
        ),
      );
      final moved = await f.row(a.id);
      expect(moved.versions.of('style'), added.versions.of('style'));
      expect(moved.versions.of('points'), isNot(added.versions.of('points')));
      await ack();

      await f.session.undo();
      await f.session.flush();
      final undone = await f.row(a.id);
      expect(await outboxFieldsOf(a.id), {'points'});
      expect(undone.versions.of('style'), added.versions.of('style'));
      expect(undone.versions.of('pageId'), added.versions.of('pageId'));
      expect(
        undone.versions.of('points').compareTo(moved.versions.max),
        greaterThan(0),
      );
      expect(undone.versions.max, undone.versions.of('points'));
      expect(
        undone.entity.version,
        f.current(a.id).version,
        reason: 'memory = row',
      );
      expect((undone.entity as Stroke).points.contentEquals(a.points), isTrue);
    },
  );

  test('undo of a restyle writes {style} only', () async {
    f = await UndoFixture.open();
    final a = f.stroke(seed: 1);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a]));
    await f.run(
      RestyleStrokes(
        pageId: f.pageId,
        strokeIds: [a.id],
        patch: const StrokeStylePatch(colorArgb: 0xFF123456),
      ),
    );
    final restyled = await f.row(a.id);
    await ack();
    await f.session.undo();
    await f.session.flush();
    expect(await outboxFieldsOf(a.id), {'style'});
    final undone = await f.row(a.id);
    expect(undone.versions.of('points'), restyled.versions.of('points'));
    expect((undone.entity as Stroke).style, a.style);
  });

  test('undo / redo of a creation write {deletedAt}', () async {
    f = await UndoFixture.open();
    final a = f.stroke(seed: 1);
    await f.run(AddStrokes(pageId: f.pageId, strokes: [a]));
    final added = await f.row(a.id);
    await ack();
    await f.session.undo();
    await f.session.flush();
    expect(await outboxFieldsOf(a.id), {'deletedAt'});
    final undone = await f.row(a.id);
    expect(undone.entity.deletedAt, isNotNull);
    expect(undone.versions.of('points'), added.versions.of('points'));
    await ack();
    await f.session.redo();
    await f.session.flush();
    expect(await outboxFieldsOf(a.id), {'deletedAt'});
    final redone = await f.row(a.id);
    expect(redone.entity.deletedAt, isNull);
    expect(redone.versions.of('style'), added.versions.of('style'));
  });

  test(
    '100 steps undone give back the initial page, in memory and stored',
    () async {
      f = await UndoFixture.open(
        initial: (pageId) => [
          for (var i = 0; i < 5; i++)
            Stroke(
              id: 'init-$i',
              pageId: pageId,
              style: StrokeStyle.defaultsFor(PenTool.ballpoint),
              points: StrokePoints.fromList([
                for (var k = 0; k < 8; k++)
                  StrokePoint(10.0 * i + k, 20.0 + k, widthQ: 0.5),
              ]),
              createdAt: 100 + i,
            ),
        ],
      );
      final initial = f.session.pageIfLoaded(f.pageId)!.strokes;
      expect(initial, hasLength(5));
      final ids = [for (final s in initial) s.id];
      for (var step = 0; step < 100; step++) {
        final target = ids[step % ids.length];
        final cmd = switch (step % 4) {
          0 => TransformElements(
            pageId: f.pageId,
            elementIds: [target],
            transform: Affine2.translation(1.5, -0.5),
          ),
          1 => RestyleStrokes(
            pageId: f.pageId,
            strokeIds: [target],
            patch: StrokeStylePatch(colorArgb: 0xFF000000 + step),
          ),
          2 => AddStrokes(
            pageId: f.pageId,
            strokes: [f.stroke(seed: step)],
          ),
          _ => RemoveStrokes(
            pageId: f.pageId,
            strokeIds: [f.session.pageIfLoaded(f.pageId)!.strokes.last.id],
          ),
        };
        f.session.execute(cmd);
      }
      expect(f.session.history.undoDepth, 100);
      for (var i = 0; i < 100; i++) {
        final r = await f.session.undo();
        expect(r.applied, isTrue, reason: 'undo $i');
        expect(r.skippedEntities, 0);
      }
      await f.session.flush();
      expect(f.session.history.canUndo, isFalse);

      void expectInitial(List<Stroke> strokes) {
        expect([for (final s in strokes) s.id], ids);
        for (var i = 0; i < ids.length; i++) {
          expect(strokes[i].style, initial[i].style);
          expect(strokes[i].points.contentEquals(initial[i].points), isTrue);
          expect(strokes[i].createdAt, initial[i].createdAt);
        }
      }

      expectInitial(f.session.pageIfLoaded(f.pageId)!.strokes);
      expectInitial((await f.store.content.loadPage(f.pageId)).strokes);
      // And redo all the way gives back the edited page.
      for (var i = 0; i < 100; i++) {
        expect((await f.session.redo()).applied, isTrue);
      }
      await f.session.flush();
      expect(f.session.history.canRedo, isFalse);
    },
  );

  group('aliases (6.7.3)', () {
    AppliedEdit edit(String id, Hlc v, {Hlc? before}) {
      Stroke s(Hlc version) => Stroke(
        id: id,
        pageId: 'p',
        style: StrokeStyle.defaultsFor(PenTool.ballpoint),
        points: StrokePoints.fromList(const [StrokePoint(0, 0)]),
        createdAt: 0,
        version: version,
      );
      return AppliedEdit(
        label: 'e',
        deltas: [
          EntityDelta(
            kind: EntityKind.stroke,
            id: id,
            before: before == null ? null : s(before),
            after: s(v),
          ),
        ],
        version: v,
        affectedPageIds: const {'p'},
      );
    }

    Hlc v(int n) => Hlc(n, 0, '0000000000000001');
    const a = EntityRef(EntityKind.stroke, 'a');

    test('kept while a step touches the entity, dropped with the last one', () {
      final h = EditHistory(const HistoryLimits(maxSteps: 2))
        ..push(edit('a', v(1)))
        ..push(edit('b', v(2)));
      h
        ..alias(a, v(3), v(1)) // an undo wrote a again
        ..alias(const EntityRef(EntityKind.stroke, 'z'), v(4), v(1));
      expect(h.canonical(a, v(3)), v(1));
      expect(h.debugAliasedEntityCount, 1, reason: 'no step touches z');
      h.push(edit('c', v(5))); // the step of 'a' leaves (maxSteps 2)
      expect(h.debugAliasedEntityCount, 0);
      expect(h.canonical(a, v(3)), v(3));
    });

    test('a step below that needs the alias keeps it after the step above '
        'leaves (erase, undo, new edit, undo add)', () {
      final h = EditHistory(const HistoryLimits())
        ..push(edit('a', v(1))) // add a
        ..push(edit('a', v(2), before: v(1))); // erase a
      h
        ..alias(a, v(3), v(1)) // undo of the erase restores the add's content
        ..moveUndoTopToRedo()
        ..push(edit('x', v(4))); // new edit: the erase step leaves with redo
      expect(h.state.redoDepth, 0);
      expect(h.canonical(a, v(3)), v(1), reason: 'the add step still needs it');
      h.clear();
      expect(h.debugAliasedEntityCount, 0);
    });
  });
}
