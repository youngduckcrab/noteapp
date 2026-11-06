// m5-7/04-editor 8.2 E2-04b, host side through the whole editor: the text
// session in the input policy (6.3.4), two- / three-finger taps by
// GestureSettings.actionFor (6.3.4 — the action runner of 6.4.3 is E2-05),
// and pen dots that nothing takes yet stay dot strokes (6.3.5 — R-5: no
// handwriting lost; tape ② is E2-14, tap-to-seek ③ E2-17).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const List<Offset> _points = [
  Offset(100, 150),
  Offset(140, 170),
  Offset(190, 185),
  Offset(240, 200),
];

/// Longer than the palm-rejection cooldown after the pen lifts.
const Duration _afterPen = Duration(seconds: 1);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _draw(EditorTestHandles h, {double dy = 0}) =>
    h.driver.stylusStroke(
      pathThrough(h, 0, [for (final p in _points) p + Offset(0, dy)]),
    );

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

void main() {
  testWidgets('policy.textSessionActive follows the text edit session', (
    tester,
  ) async {
    final box = PageObjectFixtures.textBox(pageId: 'x', id: 'tb-1');
    final h = await pumpEditor(
      tester,
      objectsByPageIndex: {
        0: [box],
      },
    );
    final host = h.container.read(editorInteractionHostProvider);
    expect(host.policy.textSessionActive, isFalse);
    final seeded =
        h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
            as core.TextBoxObject;
    final notifier = h.container.read(editorTextEditProvider.notifier)
      ..start(seeded, isNew: false);
    await tester.pump();
    expect(host.policy.textSessionActive, isTrue);
    await notifier.end(reason: TextEditEndReason.escape);
    await notifier.ending;
    await tester.pump();
    expect(host.policy.textSessionActive, isFalse);
  });

  testWidgets('twoFingerTap = redo, threeFingerTap = undo → the swapped '
      'commands; none → nothing', (tester) async {
    final h = await pumpEditor(
      tester,
      settings: const EditorSettings(
        gestures: GestureSettings(
          actions: {
            EditorGesture.twoFingerTap: EditorAction.redo,
            EditorGesture.threeFingerTap: EditorAction.undo,
          },
        ),
      ),
    );
    await _draw(h);
    await _draw(h, dy: 80);
    await h.driver.wait(_afterPen);
    final c = pageCenterOf(h, 0);

    await h.driver.multiTap([
      c,
      c + const Offset(60, 0),
      c + const Offset(120, 0),
    ]);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.recorder!.countOf('redo'), 0);

    await h.driver.multiTap([c, c + const Offset(60, 0)]);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.recorder!.countOf('redo'), 1);
    expect(h.session.history.undoDepth, 2);

    h.container
        .read(editorSettingsProvider.notifier)
        .setGestures(
          const GestureSettings(
            actions: {
              EditorGesture.twoFingerTap: EditorAction.none,
              EditorGesture.threeFingerTap: EditorAction.none,
            },
          ),
        );
    await tester.pump();
    await h.driver.multiTap([c, c + const Offset(60, 0)]);
    await h.driver.multiTap([
      c,
      c + const Offset(60, 0),
      c + const Offset(120, 0),
    ]);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.recorder!.countOf('redo'), 1);
  });

  testWidgets('a pen dot (1 px · 50 ms) nothing takes → a dot stroke is '
      'committed (no handwriting lost)', (tester) async {
    final h = await pumpEditor(tester);
    final at = h.toGlobal(0, const Offset(200, 300));
    await h.driver.stylusStroke([
      at,
      at + const Offset(1, 0),
    ], interval: const Duration(milliseconds: 25));
    await tester.pump();
    expect(_executes(h), ['execute:add-strokes']);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));
  });
}
