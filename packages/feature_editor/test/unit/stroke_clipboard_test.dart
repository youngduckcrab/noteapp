// E-10: StrokeClipboardNotifier (04-editor 6.6.7) — placement, clamping, repeated
// paste offset, new ids, createdAt + i, z order.
import 'dart:ui';

import 'package:feature_editor/src/tools/stroke_clipboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/test_data.dart';

const Size _a4 = Size(595.2756, 841.8898);

Rect _rectOf(core.PageRect b) =>
    Rect.fromLTRB(b.left, b.top, b.right, b.bottom);

Rect _union(Iterable<core.Stroke> strokes) => strokes
    .map((s) => _rectOf(s.bounds))
    .reduce((a, b) => a.expandToInclude(b));

void main() {
  late ProviderContainer container;
  late StrokeClipboardNotifier clipboard;
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

  List<core.Stroke> paste({
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

  test('empty at first; copy keeps z order and the union of the bounds', () {
    expect(container.read(editorClipboardProvider), isNull);
    expect(paste(), isEmpty);
    clipboard.copy([b, a]); // given out of order
    final content = container.read(editorClipboardProvider)!;
    expect(content.strokes.map((s) => s.id), [a.id, b.id]);
    expect(content.bounds, _union([a, b]));
    clipboard.copy(const []);
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
}

Matcher _closeOffset(Offset expected) => predicate<Offset>(
  (o) => (o - expected).distance < 0.03,
  'within 0.03 of $expected',
);
