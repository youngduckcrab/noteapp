// E-08: hover cursor (04-editor 6.6.9). Stylus hover over the page area:
//   - pen tool → PenDotCursor: diameter max(4, 2 × previewRadius × scale),
//     the pen colour at 50% alpha; mouse hover shows no pen dot;
//   - eraser tool → EraserRingCursor (stylus or mouse): eraser diameter × scale,
//     painted as a 1.5 px ring in onSurface 60%;
//   - lasso → none;
//   - hidden 300 ms after the last hover, and when the pen touches.
import 'dart:math' as math;

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/interaction_host.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/overlays/cursor_painter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

Finder _cursorPaint() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is CursorPainter,
);

void main() {
  testWidgets('pen tool: a dot in the pen colour at 50%, sized by zoom', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final host = h.container.read(editorInteractionHostProvider);
    final tools = h.container.read(editorToolProvider.notifier);
    tools.setColor(0xFF3366CC);
    final pen = h.container.read(editorToolProvider).currentPen;
    final at = pageCenterOf(h, 0);

    await h.driver.hover(at);
    final cursor = host.cursor.value! as PenDotCursor;
    final local = at - h.viewportOrigin;
    expect(cursor.position, local);
    final scale = h.viewport.camera.scale;
    expect(
      cursor.diameter,
      closeTo(
        math.max(4, 2 * ink.StrokeStyleInk(pen).previewRadius * scale),
        1e-9,
      ),
    );
    expect(cursor.color, const Color(0xFF3366CC).withValues(alpha: 0.5));
    expect(
      tester.renderObject(_cursorPaint()),
      paints..circle(
        x: local.dx,
        y: local.dy,
        radius: cursor.diameter / 2,
        color: cursor.color,
      ),
    );

    // Zoomed in, the dot grows with the camera scale.
    h.viewport.zoomBy(2, h.viewport.viewportSize.center(Offset.zero));
    await tester.pump(const Duration(milliseconds: 200));
    await h.driver.hover(at);
    final zoomed = host.cursor.value! as PenDotCursor;
    expect(
      zoomed.diameter,
      closeTo(
        math.max(
          4,
          2 * ink.StrokeStyleInk(pen).previewRadius * h.viewport.camera.scale,
        ),
        1e-9,
      ),
    );
    await tester.pump(kHoverCursorTimeout);
  });

  testWidgets('a thin pen still shows a 4 px dot', (tester) async {
    final h = await pumpEditor(tester);
    final tools = h.container.read(editorToolProvider.notifier);
    h.viewport.zoomBy(0.01, h.viewport.viewportSize.center(Offset.zero));
    await tester.pump(const Duration(milliseconds: 200));
    tools.setWidth(0.1);
    await h.driver.hover(pageCenterOf(h, 0));
    final host = h.container.read(editorInteractionHostProvider);
    expect((host.cursor.value! as PenDotCursor).diameter, 4);
    await tester.pump(kHoverCursorTimeout);
  });

  testWidgets('hidden 300 ms after the last hover', (tester) async {
    final h = await pumpEditor(tester);
    final host = h.container.read(editorInteractionHostProvider);
    final at = pageCenterOf(h, 0);
    await h.driver.hover(at);
    await h.driver.wait(const Duration(milliseconds: 200));
    await h.driver.hover(at + const Offset(10, 0)); // restarts the timer
    await h.driver.wait(const Duration(milliseconds: 200));
    expect(host.cursor.value, isNotNull);
    await h.driver.wait(const Duration(milliseconds: 120));
    expect(host.cursor.value, isNull);
    expect(tester.renderObject(_cursorPaint()), isNot(paints..circle()));
  });

  testWidgets('hidden when the pen touches', (tester) async {
    final h = await pumpEditor(tester);
    final host = h.container.read(editorInteractionHostProvider);
    final at = pageCenterOf(h, 0);
    await h.driver.hover(at);
    expect(host.cursor.value, isNotNull);
    await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
    expect(host.cursor.value, isNull);
    await h.driver.up(1);
  });

  testWidgets('eraser: a ring of the eraser diameter, stylus or mouse', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final host = h.container.read(editorInteractionHostProvider);
    final tools = h.container.read(editorToolProvider.notifier);
    tools
      ..selectTool(EditorTool.eraser)
      ..updateEraser((e) => e.copyWith(diameter: 20));
    final at = pageCenterOf(h, 0);
    final scale = h.viewport.camera.scale;

    await h.driver.hover(at);
    var ring = host.cursor.value! as EraserRingCursor;
    expect(ring.position, at - h.viewportOrigin);
    expect(ring.diameter, closeTo(20 * scale, 1e-9));
    final scheme = Theme.of(tester.element(_cursorPaint())).colorScheme;
    expect(
      tester.renderObject(_cursorPaint()),
      paints..circle(
        x: ring.position.dx,
        y: ring.position.dy,
        radius: ring.diameter / 2,
        style: PaintingStyle.stroke,
        strokeWidth: CursorPainter.ringWidth,
        color: scheme.onSurface.withValues(alpha: 0.6),
      ),
    );
    await tester.pump(kHoverCursorTimeout);

    await h.driver.hover(at, kind: PointerDeviceKind.mouse);
    ring = host.cursor.value! as EraserRingCursor;
    expect(ring.diameter, closeTo(20 * scale, 1e-9));
    await tester.pump(kHoverCursorTimeout);
  });

  testWidgets('mouse hover with the pen, and the lasso: no cursor', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final host = h.container.read(editorInteractionHostProvider);
    final at = pageCenterOf(h, 0);

    await h.driver.hover(at, kind: PointerDeviceKind.mouse);
    expect(host.cursor.value, isNull);

    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.lasso);
    await h.driver.hover(at);
    expect(host.cursor.value, isNull);
    expect(tester.renderObject(_cursorPaint()), isNot(paints..circle()));
  });
}
