// T10 (03-ink 8, INK-2-4, 6.12 R9, contract 7.2.15 v1.1): InkPageView is the
// only caller of setViewport — after layout, from a post-frame callback, with
// deviceScale = viewScale × ancestorScale × devicePixelRatio. setViewport never
// notifies the controller's listeners (so a parent that rebuilds on them never
// sees 'setState during build'), and one controller has one view (assert).
// The test code itself never calls setViewport.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

/// Rebuilds whenever the controller notifies (like an EDITOR page widget).
class _Listening extends StatefulWidget {
  const _Listening({super.key, required this.controller, required this.child});
  final InkPageController controller;
  final Widget child;

  @override
  State<_Listening> createState() => _ListeningState();
}

class _ListeningState extends State<_Listening> {
  int builds = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    builds++;
    return widget.child;
  }
}

void main() {
  late InkPageController controller;
  var notified = 0;
  var baseRepaints = 0;
  final page = core.PageSize.a4Portrait;

  setUp(() {
    notified = 0;
    baseRepaints = 0;
    controller = createTestPageController()
      ..updateContent(
        SyntheticInk.pageContent(
          strokes: [
            strokeThrough(
              segment(const Offset(40, 40), const Offset(200, 80)),
              core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
              id: 'a',
            ),
          ],
        ),
      )
      ..addListener(() => notified++);
    controller
        .layerRepaint(InkRenderLayer.inkBase)
        .addListener(() => baseRepaints++);
  });
  tearDown(() => controller.dispose());

  testWidgets('DPR 2: bucket right after pumpWidget; ancestorScale 1.5 / 5', (
    tester,
  ) async {
    final render = inkPageRenderOf(controller);
    expect(controller.renderStats.currentBucket, isNull, reason: 'R9 ④');
    await pumpPageView(
      tester,
      controller,
      width: page.width, // viewScale 1
      devicePixelRatio: 2,
    );
    expect(render.deviceScale, 2.0);
    expect(controller.renderStats.currentBucket, 2.0);

    await tester.pumpWidget(
      pageViewApp(controller, width: page.width, ancestorScale: 1.5),
    );
    expect(render.deviceScale, 3.0);
    expect(controller.renderStats.currentBucket, 3.0);

    await tester.pumpWidget(
      pageViewApp(controller, width: page.width, ancestorScale: 5),
    );
    expect(render.deviceScale, 10.0);
    expect(controller.renderStats.currentBucket, isNull, reason: 'vector');

    expect(notified, 0, reason: 'setViewport never notifies');
    expect(baseRepaints, 0, reason: 'vector chunks: no picture change');
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewScale and DPR changes are reported too', (tester) async {
    await pumpPageView(
      tester,
      controller,
      width: page.width * 0.5, // viewScale 0.5
      devicePixelRatio: 2,
    );
    expect(controller.renderStats.currentBucket, 1.0);
    tester.view.devicePixelRatio = 3; // MediaQuery dependency → rebuild
    tester.view.physicalSize = const Size(700, 900) * 3;
    await tester.pump();
    expect(inkPageRenderOf(controller).deviceScale, 1.5);
    expect(controller.renderStats.currentBucket, 1.5);
    expect(notified, 0);
  });

  testWidgets('visiblePageRect and isScaling are reported', (tester) async {
    final render = inkPageRenderOf(controller);
    await pumpPageView(tester, controller, width: page.width);
    expect(render.visiblePageRect, isNull);
    expect(render.isScaling, isFalse);
    const visible = Rect.fromLTWH(0, 100, 300, 400);
    await tester.pumpWidget(
      pageViewApp(
        controller,
        width: page.width,
        visiblePageRect: visible,
        isScaling: true,
      ),
    );
    expect(render.visiblePageRect, visible);
    expect(render.isScaling, isTrue);
    await tester.pumpWidget(pageViewApp(controller, width: page.width));
    expect(render.visiblePageRect, isNull);
    expect(render.isScaling, isFalse);
    expect(notified, 0);
  });

  testWidgets('a parent rebuilding on the controller: no build-phase error', (
    tester,
  ) async {
    final parent = GlobalKey<_ListeningState>();
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(1400, 1800);
    addTearDown(tester.view.reset);
    Widget app(double ancestorScale) => Directionality(
      textDirection: TextDirection.ltr,
      child: _Listening(
        key: parent,
        controller: controller,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: page.width,
            child: InkPageView(
              controller: controller,
              ancestorScale: ancestorScale,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(1));
    await tester.pumpWidget(app(2));
    await tester.pumpWidget(app(0.5));
    expect(tester.takeException(), isNull);
    expect(controller.renderStats.currentBucket, 1.0);
    final builds = parent.currentState!.builds;
    // a real controller notification still reaches the parent
    controller.select({'a'});
    await tester.pump();
    expect(parent.currentState!.builds, builds + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second InkPageView on the same controller asserts', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1300, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: page.width,
              child: InkPageView(controller: controller),
            ),
            SizedBox(
              width: page.width,
              child: InkPageView(controller: controller),
            ),
          ],
        ),
      ),
    );
    final error = tester.takeException();
    expect(error, isA<AssertionError>());
    expect('$error', contains('already has an InkPageView'));
  });

  testWidgets('replacing the view (same controller) is fine', (tester) async {
    await pumpPageView(tester, controller, width: page.width);
    await tester.pumpWidget(const SizedBox());
    await pumpPageView(tester, controller, width: page.width * 0.5);
    expect(tester.takeException(), isNull);
    expect(controller.renderStats.currentBucket, 0.5);
  });
}
