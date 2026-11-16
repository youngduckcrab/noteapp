// (v2.15-ui, m5-7/04-editor 23.1) The pen drawings as the tray and the picker
// draw them: every pen type in its default ink colour, then the eraser, on
// the craft tray's well. No text on screen (contract 7.4.8 golden rule).
@Tags(['golden'])
@TestOn('vm')
library;

import 'package:feature_editor/src/ui/pen/pen_art_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

void main() {
  testWidgets('the 18 pens and the eraser', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(20 * 36.0 + 24, 110) * 2;
    addTearDown(tester.view.reset);
    final look = PenTrayStyle.of(
      styleTokensFor(AppStyle.craft, Brightness.light),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('pens'),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [look.wellTop, look.wellBottom],
                  ),
                ),
                child: ClipRect(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in core.PenTool.values)
                        SizedBox(
                          width: 36,
                          child: Center(
                            child: PenArt.of(
                              core.StrokeStyle.defaultsFor(t),
                              height: 86,
                            ),
                          ),
                        ),
                      const SizedBox(
                        width: 36,
                        child: Center(child: EraserArt(height: 86)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('pens')),
      matchesGoldenFile('pen_art_all.png'),
    );
  });
}
