// RecordingPanel placeholder (m5-7/06-pdf 8.1 T30 — 2nd-round contract 7.6.2 R2-B4: title +
// close). In the EDITOR slot (height ≤ 40 % of the screen — 6.13.1) on an iPad Pro 13" in
// both orientations: the title '녹음', a close button that calls onClose once, no overflow,
// tap-target guidelines; the panel does not touch tapToSeek and needs no provider override.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart';

import '../support/ipad.dart';

void main() {
  for (final landscape in [false, true]) {
    testWidgets(
      'title and close button (${landscape ? 'landscape' : 'portrait'})',
      (tester) async {
        var closes = 0;
        final changes = <bool>[];
        final tap = ValueNotifier(false);
        addTearDown(tap.dispose);
        final size = landscape ? ipad13Landscape : ipad13Portrait;
        await pumpOnIpad(
          tester,
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: size.height * 0.4,
                    child: RecordingPanel(
                      noteId: 'n1',
                      tapToSeek: tap,
                      onTapToSeekChanged: changes.add,
                      onClose: () => closes++,
                    ),
                  ),
                ),
              ),
            ),
          ),
          landscape: landscape,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('녹음'), findsOneWidget);
        final close = find.byTooltip('닫기');
        expect(close, findsOneWidget);
        await expectTapTargetGuidelines(tester);

        await tester.tap(close);
        await tester.pump();
        expect(closes, 1);
        expect(changes, isEmpty);
        expect(tap.value, isFalse);
      },
    );
  }
}
