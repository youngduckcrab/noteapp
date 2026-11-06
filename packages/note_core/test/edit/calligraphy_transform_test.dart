// Calligraphy nib angle under transforms (C2-38, m5-7/02-core 6.2.7): the pure cases (shared
// with Chrome — test/web/object_json_browser_test.dart) and, on the SQLite store, one
// TransformElements → undo giving back the old extras with the 1st-round field version steps
// ({points, style}).
@TestOn('vm')
library;

import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../shared/object_json_web_cases.dart';
import 'undo_support.dart';

void main() {
  defineCalligraphyTransformCases();

  test(
    'TransformElements → undo: the old extras and style field version',
    () async {
      final f = await UndoFixture.open();
      addTearDown(f.close);
      final s = StrokeFixtures.synthetic(
        pageId: f.pageId,
        ids: f.store.ids,
        tool: PenTool.calligraphy,
        createdAt: 1000,
      );
      await f.run(AddStrokes(pageId: f.pageId, strokes: [s]));
      final added = await f.row(s.id);
      final before = f.current(s.id).style.extras;
      expect(before['nibAngleDeg'], 45);
      await f.store.db.delete(f.store.db.outbox).go();

      await f.run(
        TransformElements(
          pageId: f.pageId,
          elementIds: [s.id],
          transform: Affine2.rotation(math.pi / 6, originX: 100, originY: 100),
        ),
      );
      final turned = await f.row(s.id);
      expect(
        (f.current(s.id).style.extras['nibAngleDeg']! as num).toDouble(),
        closeTo(75, 1e-9),
      );
      expect(turned.versions.of('style'), isNot(added.versions.of('style')));
      expect((await readOutbox(f.store.db)).single.changedFields, {
        'points',
        'style',
      });
      await f.store.db.delete(f.store.db.outbox).go();

      await f.session.undo();
      await f.session.flush();
      final undone = await f.row(s.id);
      expect(f.current(s.id).style.extras, before);
      expect((undone.entity as Stroke).style.extras, before);
      expect((await readOutbox(f.store.db)).single.changedFields, {
        'points',
        'style',
      });
      expect(
        undone.versions.of('style').compareTo(turned.versions.of('style')),
        greaterThan(0),
      );
    },
  );
}
