// m5-7/04-editor 6.5.2: followSystemAction — the iPadOS preferred action of
// an Apple Pencil double tap / squeeze → EditorAction, all 8 values. (Written
// with the action runner in E2-05; E2-18 consumes the Pencil events.)
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/actions/follow_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('followSystemAction: the 8 preferred actions (6.5.2)', () {
    expect(
      {for (final p in StylusPreferredAction.values) p: followSystemAction(p)},
      {
        StylusPreferredAction.ignore: EditorAction.none,
        StylusPreferredAction.switchEraser: EditorAction.toggleEraser,
        StylusPreferredAction.switchPrevious: EditorAction.previousTool,
        StylusPreferredAction.showColorPalette: EditorAction.colorPalette,
        StylusPreferredAction.showInkAttributes: EditorAction.toolPalette,
        StylusPreferredAction.showContextualPalette: EditorAction.toolPalette,
        StylusPreferredAction.runSystemShortcut: EditorAction.none,
        StylusPreferredAction.unknown: EditorAction.none,
      },
    );
  });
}
