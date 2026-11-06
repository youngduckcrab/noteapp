// lib/src/state/popup.dart — 04-editor 6.9.2 (popup state, per note).
// (v2) E2-05: popups at a point (m5-7/04-editor 6.4.1 palettes).
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../scope/editor_scope.dart';

@immutable
sealed class EditorPopup {
  const EditorPopup();
}

final class PenSettingsPopup extends EditorPopup {
  const PenSettingsPopup();

  @override
  bool operator ==(Object other) => other is PenSettingsPopup;

  @override
  int get hashCode => (PenSettingsPopup).hashCode;
}

/// The quick pen popup: below the pen button, or (v2, EditorAction
/// toolPalette — m5-7/04-editor 6.4.1) at [globalPosition] (the pencil's
/// hover point, global logical px).
final class QuickPenPopup extends EditorPopup {
  const QuickPenPopup({this.globalPosition});
  final Offset? globalPosition;

  @override
  bool operator ==(Object other) =>
      other is QuickPenPopup && other.globalPosition == globalPosition;

  @override
  int get hashCode => Object.hash(QuickPenPopup, globalPosition);
}

/// (v2, EditorAction colorPalette — m5-7/04-editor 6.4.1) the recent colours
/// and the user palette (the two rows of the colour panel), below the pen
/// button or at [globalPosition].
final class ColorPalettePopup extends EditorPopup {
  const ColorPalettePopup({this.globalPosition});
  final Offset? globalPosition;

  @override
  bool operator ==(Object other) =>
      other is ColorPalettePopup && other.globalPosition == globalPosition;

  @override
  int get hashCode => Object.hash(ColorPalettePopup, globalPosition);
}

/// (v2, m5-7/04-editor 6.7.2) The recolor popup of the selection menu's
/// '색 ●': the recent colours, the user palette and '더 보기' (the colour
/// panel), its top-left at [globalPosition] (under the '색' button — global
/// logical px).
final class RecolorPopup extends EditorPopup {
  const RecolorPopup({this.globalPosition});
  final Offset? globalPosition;

  @override
  bool operator ==(Object other) =>
      other is RecolorPopup && other.globalPosition == globalPosition;

  @override
  int get hashCode => Object.hash(RecolorPopup, globalPosition);
}

final class EraserSettingsPopup extends EditorPopup {
  const EraserSettingsPopup();

  @override
  bool operator ==(Object other) => other is EraserSettingsPopup;

  @override
  int get hashCode => (EraserSettingsPopup).hashCode;
}

final class CanvasContextMenuPopup extends EditorPopup {
  const CanvasContextMenuPopup({required this.screenPoint});
  final Offset screenPoint;

  @override
  bool operator ==(Object other) =>
      other is CanvasContextMenuPopup && other.screenPoint == screenPoint;

  @override
  int get hashCode => Object.hash(CanvasContextMenuPopup, screenPoint);
}

final class SelectionContextMenuPopup extends EditorPopup {
  const SelectionContextMenuPopup({required this.screenPoint});
  final Offset screenPoint;

  @override
  bool operator ==(Object other) =>
      other is SelectionContextMenuPopup && other.screenPoint == screenPoint;

  @override
  int get hashCode => Object.hash(SelectionContextMenuPopup, screenPoint);
}

/// Where a new page goes relative to the anchor (EDITOR UI value, mapped to
/// core.PageBefore / core.PageAfter / core.PageAtEnd in EditorCommands.addPage).
enum AddPagePlacement { before, after, end }

final class AddPagePopup extends EditorPopup {
  const AddPagePopup({
    this.initialPlacement = AddPagePlacement.after,
    this.anchorPageId,
  });
  final AddPagePlacement initialPlacement;
  final String? anchorPageId; // null = current page

  @override
  bool operator ==(Object other) =>
      other is AddPagePopup &&
      other.initialPlacement == initialPlacement &&
      other.anchorPageId == anchorPageId;

  @override
  int get hashCode => Object.hash(AddPagePopup, initialPlacement, anchorPageId);
}

final class SavePresetPopup extends EditorPopup {
  const SavePresetPopup();

  @override
  bool operator ==(Object other) => other is SavePresetPopup;

  @override
  int get hashCode => (SavePresetPopup).hashCode;
}

final class PresetManagerPopup extends EditorPopup {
  const PresetManagerPopup();

  @override
  bool operator ==(Object other) => other is PresetManagerPopup;

  @override
  int get hashCode => (PresetManagerPopup).hashCode;
}

/// Per note. At most one popup at a time.
class EditorPopupNotifier extends Notifier<EditorPopup?> {
  @override
  EditorPopup? build() {
    ref.watch(editorNoteIdProvider);
    return null;
  }

  void open(EditorPopup popup) => state = popup;

  void close() {
    if (state != null) state = null;
  }
}

final editorPopupProvider = NotifierProvider<EditorPopupNotifier, EditorPopup?>(
  EditorPopupNotifier.new,
  dependencies: [editorNoteIdProvider],
  name: 'editorPopupProvider',
);
