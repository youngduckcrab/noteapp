// lib/src/actions/follow_system.dart — m5-7/04-editor 6.5.2 (contract 7.2.10
// 'followSystem' sentence).
//
// EditorAction.followSystem follows the iPadOS preferred action that comes
// with each Apple Pencil double tap / squeeze event.
import '../di/stylus_extras.dart';
import '../state/settings/editor_settings.dart';

/// switchEraser → toggleEraser, switchPrevious → previousTool,
/// showColorPalette → colorPalette, showInkAttributes · showContextualPalette
/// → toolPalette, ignore · runSystemShortcut · unknown → none.
EditorAction followSystemAction(StylusPreferredAction preferred) =>
    switch (preferred) {
      StylusPreferredAction.switchEraser => EditorAction.toggleEraser,
      StylusPreferredAction.switchPrevious => EditorAction.previousTool,
      StylusPreferredAction.showColorPalette => EditorAction.colorPalette,
      StylusPreferredAction.showInkAttributes ||
      StylusPreferredAction.showContextualPalette => EditorAction.toolPalette,
      StylusPreferredAction.ignore ||
      StylusPreferredAction.runSystemShortcut ||
      StylusPreferredAction.unknown => EditorAction.none,
    };
