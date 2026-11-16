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
///
/// (v2.15-ui) [presetId]: the tray pen it was long-pressed on (its
/// '트레이에서 빼기' row); null from the toolbar-less paths.
final class QuickPenPopup extends EditorPopup {
  const QuickPenPopup({this.globalPosition, this.presetId});
  final Offset? globalPosition;
  final String? presetId;

  @override
  bool operator ==(Object other) =>
      other is QuickPenPopup &&
      other.globalPosition == globalPosition &&
      other.presetId == presetId;

  @override
  int get hashCode => Object.hash(QuickPenPopup, globalPosition, presetId);
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

/// (v2, E2-09 — m5-7/04-editor 6.9.1) The shape tool popup (kind, style);
/// at [globalPosition], else under the toolbar's shape button when
/// [anchored] (E2-13 — 6.13.1), else centred.
final class ShapeToolPopup extends EditorPopup {
  const ShapeToolPopup({this.globalPosition, this.anchored = false});
  final Offset? globalPosition;
  final bool anchored;

  @override
  bool operator ==(Object other) =>
      other is ShapeToolPopup &&
      other.globalPosition == globalPosition &&
      other.anchored == anchored;

  @override
  int get hashCode => Object.hash(ShapeToolPopup, globalPosition, anchored);
}

/// (v2, E2-09 — 6.7.5) The selection menu's '스타일' (selected shapes).
final class ShapeStylePopup extends EditorPopup {
  const ShapeStylePopup({this.globalPosition});
  final Offset? globalPosition;

  @override
  bool operator ==(Object other) =>
      other is ShapeStylePopup && other.globalPosition == globalPosition;

  @override
  int get hashCode => Object.hash(ShapeStylePopup, globalPosition);
}

/// (v2, E2-10 — m5-7/04-editor 6.11.4) The text tool popup (the style of
/// the next box — ToolOptions.textStyle); at [globalPosition], else under
/// the toolbar's text button when [anchored] (E2-13 — 6.13.1), else centred.
final class TextToolPopup extends EditorPopup {
  const TextToolPopup({this.globalPosition, this.anchored = false});
  final Offset? globalPosition;
  final bool anchored;

  @override
  bool operator ==(Object other) =>
      other is TextToolPopup &&
      other.globalPosition == globalPosition &&
      other.anchored == anchored;

  @override
  int get hashCode => Object.hash(TextToolPopup, globalPosition, anchored);
}

/// (v2, E2-10 — 6.7.5) The selection menu's '서식' (a selected text box,
/// outside an edit session).
final class TextFormatPopup extends EditorPopup {
  const TextFormatPopup({this.globalPosition});
  final Offset? globalPosition;

  @override
  bool operator ==(Object other) =>
      other is TextFormatPopup && other.globalPosition == globalPosition;

  @override
  int get hashCode => Object.hash(TextFormatPopup, globalPosition);
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
