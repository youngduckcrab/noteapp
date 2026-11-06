// E-10: StrokeClipboardNotifier (04-editor 6.6.7) — placement, clamping, repeated
// paste offset, new ids, createdAt + i, z order. (v2, E2-07a — m5-7/04-editor
// 6.8) ElementClipboardNotifier (renamed — the 1st-round cases moved here as
// they were, through the strokes of instantiate): objects too — new ids by
// copyTo, createdAt + i over strokes and objects together in z order, the
// same move as the strokes, an UnknownObject left where it was, an image's
// assetId kept.
import 'dart:ui';

import 'package:feature_editor/src/tools/element_clipboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/test_data.dart';

const Size _a4 = Size(595.2756, 841.8898);

Rect _rectOf(core.PageRect b) =>
    Rect.fromLTRB(b.left, b.top, b.right, b.bottom);

Rect _union(Iterable<core.Stroke> strokes) => strokes
    .map((s) => _rectOf(s.bounds))
    .reduce((a, b) => a.expandToInclude(b));

void main() {
  late ProviderContainer container;
  late ElementClipboardNotifier clipboard;
  var ids = 0;
  String newId() => 'new-${ids++}';

  setUp(() {
    ids = 0;
    container = ProviderContainer();
    clipboard = container.read(editorClipboardProvider.notifier);
  });
  tearDown(() => container.dispose());

  // strokeA: (100..220, 150), strokeB: (100..260, 400), createdAt 1 and 2.
  final a = strokeA;
  final b = strokeB;

  ({List<core.Stroke> strokes, List<core.PageObject> objects}) pasteAll({
    Offset center = const Offset(300, 400),
    bool explicitPoint = false,
    String pageId = 'target',
    Size pageSize = _a4,
    int createdAt = 5000,
  }) => clipboard.instantiate(
    pageId: pageId,
    pageSize: pageSize,
    center: center,
    explicitPoint: explicitPoint,
    newId: newId,
    createdAt: createdAt,
  );

  /// The strokes of a paste (the 1st-round cases).
  List<core.Stroke> paste({
    Offset center = const Offset(300, 400),
    bool explicitPoint = false,
    String pageId = 'target',
    Size pageSize = _a4,
    int createdAt = 5000,
  }) => pasteAll(
    center: center,
    explicitPoint: explicitPoint,
    pageId: pageId,
    pageSize: pageSize,
    createdAt: createdAt,
  ).strokes;

  test('empty at first; copy keeps z order and the union of the bounds', () {
    expect(container.read(editorClipboardProvider), isNull);
    expect(paste(), isEmpty);
    clipboard.copy([b, a]); // given out of order
    final content = container.read(editorClipboardProvider)!;
    expect(content.strokes.map((s) => s.id), [a.id, b.id]);
    expect(content.bounds, _union([a, b]));
    clipboard.copy(const <core.PageElement>[]);
    expect(container.read(editorClipboardProvider), isNull);
  });

  test('placed centred at the point, without width scaling', () {
    clipboard.copy([a, b]);
    final pasted = paste(center: const Offset(300, 420), explicitPoint: true);
    expect(pasted, hasLength(2));
    final bounds = _union(pasted);
    expect(bounds.center.dx, closeTo(300, 0.02));
    expect(bounds.center.dy, closeTo(420, 0.02));
    expect(bounds.size.width, closeTo(_union([a, b]).width, 0.02));
    for (var i = 0; i < 2; i++) {
      final source = [a, b][i];
      expect(pasted[i].style, source.style); // width unchanged
      expect(pasted[i].points.length, source.points.length);
      final dx = pasted[i].points.x(0) - source.points.x(0);
      final dy = pasted[i].points.y(0) - source.points.y(0);
      // Every point moved by the same offset (CORE quantization 0.01 pt).
      for (var k = 0; k < source.points.length; k++) {
        expect(pasted[i].points.x(k) - source.points.x(k), closeTo(dx, 0.02));
        expect(pasted[i].points.y(k) - source.points.y(k), closeTo(dy, 0.02));
      }
    }
  });

  test('new ids, the target page, createdAt + i, no version', () {
    clipboard.copy([b, a]);
    final pasted = paste(createdAt: 7000);
    expect(pasted.map((s) => s.id), ['new-0', 'new-1']);
    expect(pasted.map((s) => s.pageId), everyElement('target'));
    expect(pasted.map((s) => s.createdAt), [7000, 7001]);
    expect(pasted.map((s) => s.version), everyElement(isNull));
    // z order: the copy of A (older) stays below the copy of B.
    expect(core.Stroke.compareOrder(pasted[0], pasted[1]), lessThan(0));
    expect(pasted[0].style, a.style);
    expect(pasted[1].style, b.style);
  });

  test('clamped inside the page', () {
    clipboard.copy([a, b]);
    final size = _union([a, b]).size;
    final nearCorner = _union(
      paste(center: const Offset(590, 840), explicitPoint: true),
    );
    expect(nearCorner.right, closeTo(_a4.width, 0.02));
    expect(nearCorner.bottom, closeTo(_a4.height, 0.02));
    expect(nearCorner.width, closeTo(size.width, 0.02));
    final topLeft = _union(
      paste(center: const Offset(-50, -80), explicitPoint: true),
    );
    expect(topLeft.left, closeTo(0, 0.02));
    expect(topLeft.top, closeTo(0, 0.02));
  });

  test('content larger than the page: top-left at 0,0', () {
    final wide = lineStroke(id: 'wide', x0: 10, y0: 50, x1: 900, y1: 60);
    clipboard.copy([wide]);
    final placed = _union(
      paste(center: const Offset(300, 400), explicitPoint: true),
    );
    expect(placed.left, closeTo(0, 0.02));
    // Only the too-wide axis goes to 0; the other is still centred.
    expect(placed.center.dy, closeTo(400, 0.02));

    clipboard.copy([wide]);
    final tiny = _union(
      paste(center: const Offset(50, 50), pageSize: const Size(100, 5)),
    );
    expect(tiny.left, closeTo(0, 0.02));
    expect(tiny.top, closeTo(0, 0.02));
  });

  test('repeated pastes without a point move +16 pt each; copy resets', () {
    clipboard.copy([a]);
    Offset centreOf(List<core.Stroke> s) => _union(s).center;
    const at = Offset(300, 400);
    final first = centreOf(paste(center: at));
    final second = centreOf(paste(center: at));
    final third = centreOf(paste(center: at));
    expect(first.dx, closeTo(300, 0.02));
    expect(first.dy, closeTo(400, 0.02));
    expect(second - first, _closeOffset(const Offset(16, 16)));
    expect(third - first, _closeOffset(const Offset(32, 32)));

    // An explicit point is not offset and does not count.
    final explicit = centreOf(paste(center: at, explicitPoint: true));
    expect(explicit, _closeOffset(at));
    final fourth = centreOf(paste(center: at));
    expect(fourth - first, _closeOffset(const Offset(48, 48)));

    clipboard.copy([a]);
    expect(centreOf(paste(center: at)), _closeOffset(at));
  });

  group('(v2) objects', () {
    // createdAt: a 1, b 2 (strokes), shape 3, image 4, unknown 1 (fixture).
    final shape = PageObjectFixtures.shape(
      pageId: 'src',
      id: 'shape-1',
      rect: const core.PageRect(300, 120, 420, 200),
      createdAt: 3,
    );
    final image = PageObjectFixtures.image(
      pageId: 'src',
      id: 'image-1',
      assetId: 'asset-7',
      rect: const core.PageRect(300, 450, 450, 560),
      createdAt: 4,
    );
    final unknown = PageObjectFixtures.unknown(pageId: 'src', id: 'unknown-1');

    test('copy: strokes and objects together in z order, bounds of all, '
        'objectCount', () {
      clipboard.copy([image, b, shape, a]);
      final content = container.read(editorClipboardProvider)!;
      expect(content.elements.map((e) => e.id), [
        a.id,
        b.id,
        shape.id,
        image.id,
      ]);
      expect(content.objectCount, 2);
      expect(content.strokes.map((s) => s.id), [a.id, b.id]);
      final all = [
        for (final e in content.elements)
          Rect.fromLTRB(
            e.bounds.left,
            e.bounds.top,
            e.bounds.right,
            e.bounds.bottom,
          ),
      ].reduce((x, y) => x.expandToInclude(y));
      expect(content.bounds, all);
    });

    test('instantiate: new ids by copyTo, the target page, createdAt + i '
        'across strokes and objects (z order kept), no version', () {
      clipboard.copy([a, shape, b, image]);
      final pasted = pasteAll(createdAt: 9000);
      // z order a(1), b(2), shape(3), image(4) → i = 0..3
      expect(pasted.strokes.map((s) => s.id), ['new-0', 'new-1']);
      expect(pasted.objects.map((o) => o.id), ['new-2', 'new-3']);
      expect(pasted.strokes.map((s) => s.createdAt), [9000, 9001]);
      expect(pasted.objects.map((o) => o.createdAt), [9002, 9003]);
      expect(
        [...pasted.strokes, ...pasted.objects].map((e) => e.pageId),
        everyElement('target'),
      );
      expect(pasted.objects.map((o) => o.version), everyElement(isNull));
      final all = <core.PageElement>[...pasted.strokes, ...pasted.objects]
        ..sort(core.Stroke.compareOrder);
      expect(all.map((e) => e.id), ['new-0', 'new-1', 'new-2', 'new-3']);
      expect(pasted.objects[0], isA<core.ShapeObject>());
      // The image keeps its asset.
      expect((pasted.objects[1] as core.ImageObject).assetId, 'asset-7');
    });

    test('objects move by the same offset as the strokes', () {
      clipboard.copy([a, shape]);
      final pasted = pasteAll(
        center: const Offset(300, 500),
        explicitPoint: true,
      );
      final dx = pasted.strokes.single.points.x(0) - a.points.x(0);
      final dy = pasted.strokes.single.points.y(0) - a.points.y(0);
      final moved = pasted.objects.single.frame.rect;
      expect(moved.left - shape.frame.rect.left, closeTo(dx, 0.02));
      expect(moved.top - shape.frame.rect.top, closeTo(dy, 0.02));
      expect(
        moved.right - moved.left,
        closeTo(shape.frame.rect.right - shape.frame.rect.left, 1e-9),
      );
      // Same style (no width scaling for a move).
      expect((pasted.objects.single as core.ShapeObject).style, shape.style);
    });

    test('an UnknownObject stays where it was (transformed returns it)', () {
      clipboard.copy([a, unknown]);
      final pasted = pasteAll(
        center: const Offset(100, 700),
        explicitPoint: true,
      );
      final copy = pasted.objects.single;
      expect(copy, isA<core.UnknownObject>());
      expect(copy.id, 'new-1'); // createdAt 1 like A: 'stroke-a' < 'unknown-1'
      expect(copy.pageId, 'target');
      expect(copy.frame, unknown.frame); // not moved
    });

    test('objects only: no strokes', () {
      clipboard.copy([image]);
      final pasted = pasteAll();
      expect(pasted.strokes, isEmpty);
      expect(pasted.objects, hasLength(1));
      clipboard.copy(const <core.PageElement>[]);
      final none = pasteAll();
      expect(none.strokes, isEmpty);
      expect(none.objects, isEmpty);
    });
  });
}

Matcher _closeOffset(Offset expected) => predicate<Offset>(
  (o) => (o - expected).distance < 0.03,
  'within 0.03 of $expected',
);
