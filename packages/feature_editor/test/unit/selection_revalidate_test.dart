// E2-02 (m5-7/04-editor 6.6.1, 6.6.7): the selection v2 model and its
// revalidation by elementById, on the editor screen (fake store, R2-B3 INK).
// - select keeps the INK selection's allIds (strokes AND objects) and the
//   given origin;
// - an object id gone (RemoveElements from outside the selection) → out of
//   the selection, the INK selection follows, the origin kept;
// - everything gone → cleared;
// - ignored while a drag runs;
// - setVertexMode only for a single polyline shape.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

void main() {
  Future<EditorTestHandles> open(WidgetTester tester) async {
    final h = await pumpEditor(
      tester,
      pages: 1,
      strokesByPageIndex: {
        0: [lineStroke(id: 's1', x0: 60, y0: 80, x1: 300, y1: 80)],
      },
      objectsByPageIndex: {
        0: [
          PageObjectFixtures.shape(pageId: 'x', id: 'rect-1'),
          PageObjectFixtures.textBox(pageId: 'x', id: 'text-1'),
          PageObjectFixtures.shape(
            pageId: 'x',
            id: 'oval-1',
            kind: core.ShapeKind.ellipse,
          ),
        ],
      },
    );
    // The lasso keeps the selection (other tools clear it — 6.6.6).
    h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
    await tester.pump();
    return h;
  }

  EditorSelectionNotifier notifier(EditorTestHandles h) =>
      h.container.read(editorSelectionProvider.notifier);
  EditorSelection? selection(EditorTestHandles h) =>
      h.container.read(editorSelectionProvider);

  void remove(EditorTestHandles h, List<String> ids) => h.session.execute(
    core.RemoveElements(pageId: h.pageId(0), elementIds: ids),
  );

  testWidgets('select: allIds (strokes and objects) and the origin', (
    tester,
  ) async {
    final h = await open(tester);
    notifier(h).select(h.pageId(0), {
      's1',
      'rect-1',
      'text-1',
      'unknown',
    }, origin: SelectionOrigin.paste);
    final s = selection(h)!;
    expect(s.elementIds, {'s1', 'rect-1', 'text-1'});
    expect(s.origin, SelectionOrigin.paste);
    expect(s.isDragging, isFalse);
    expect(s.vertexMode, isFalse);
    final ink = h.controllerOf(0).selection!;
    expect(ink.strokeIds, {'s1'});
    expect(ink.objectIds, {'rect-1', 'text-1'});
    // Default origin: lasso.
    notifier(h).select(h.pageId(0), {'s1'});
    expect(selection(h)!.origin, SelectionOrigin.lasso);
  });

  testWidgets('an object id gone → out of the selection, the origin kept', (
    tester,
  ) async {
    final h = await open(tester);
    notifier(h).select(h.pageId(0), {
      's1',
      'rect-1',
      'text-1',
    }, origin: SelectionOrigin.insert);
    remove(h, ['rect-1']);
    await tester.pump();
    final s = selection(h)!;
    expect(s.elementIds, {'s1', 'text-1'});
    expect(s.origin, SelectionOrigin.insert);
    expect(h.controllerOf(0).selection!.allIds, {'s1', 'text-1'});

    // An id that is not selected: nothing changes.
    remove(h, ['oval-1']);
    await tester.pump();
    expect(selection(h), s);
  });

  testWidgets('everything gone → cleared', (tester) async {
    final h = await open(tester);
    notifier(h).select(h.pageId(0), {'rect-1', 'text-1'});
    remove(h, ['rect-1', 'text-1']);
    await tester.pump();
    expect(selection(h), isNull);
    final ink = h.controllerOf(0).selection;
    expect(ink == null || ink.isEmpty || ink.isDisposed, isTrue);
  });

  testWidgets('ignored while a drag runs', (tester) async {
    final h = await open(tester);
    notifier(h)
      ..select(h.pageId(0), {'s1', 'rect-1'}, origin: SelectionOrigin.tap)
      ..setDragging(true);
    remove(h, ['rect-1']);
    await tester.pump();
    final s = selection(h)!;
    expect(s.elementIds, {'s1', 'rect-1'});
    expect(s.isDragging, isTrue);
    notifier(h).setDragging(false);
    expect(selection(h)!.origin, SelectionOrigin.tap);
  });

  testWidgets('setVertexMode: only a single polyline shape', (tester) async {
    final h = await open(tester);
    notifier(h).select(h.pageId(0), {'rect-1'});
    notifier(h).setVertexMode(true);
    expect(selection(h)!.vertexMode, isTrue, reason: 'rectangle = polyline');
    notifier(h).setVertexMode(false);
    expect(selection(h)!.vertexMode, isFalse);

    for (final ids in [
      {'oval-1'}, // ellipse geometry
      {'text-1'}, // not a shape
      {'rect-1', 's1'}, // not single
    ]) {
      notifier(h).select(h.pageId(0), ids);
      notifier(h).setVertexMode(true);
      expect(selection(h)!.vertexMode, isFalse, reason: '$ids');
    }
  });

  test('EditorSelection ==: ids as a set, origin, drag and vertex mode', () {
    const a = EditorSelection(pageId: 'p', elementIds: {'a', 'b'});
    expect(a, const EditorSelection(pageId: 'p', elementIds: {'b', 'a'}));
    expect(a.origin, SelectionOrigin.lasso);
    expect(a == a.copyWith(origin: SelectionOrigin.paste), isFalse);
    expect(a == a.copyWith(isDragging: true), isFalse);
    expect(a == a.copyWith(vertexMode: true), isFalse);
    expect(a.copyWith(elementIds: {'a'}).elementIds, {'a'});
    expect(a.copyWith(isDragging: true).hashCode, isNot(a.hashCode));
  });
}
