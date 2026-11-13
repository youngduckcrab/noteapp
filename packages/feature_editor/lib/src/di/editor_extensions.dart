// lib/src/di/editor_extensions.dart — contract 00-overview 7.2.17 (v1.4) and
// 2nd-round contract m5-7/00-overview 7.2.10 (v2.0 additions); m5-7/04-editor
// 4.2, 4.3.1.
//
// Extension points other areas fill through the app shell: INFRA's
// FeatureWiringModule overrides editorExtensionsProvider (contract 7.3.3) —
// PDF's menu actions (v1.4), recog's selection / insert items and media_io's
// recording panel (v2.0). The editor reads the provider and builds a context
// value when a menu, sheet or panel opens.
//
// R2-B5 (foundation): the v2.0 types, fields and value equality only. The
// editor shows the new slots from the concurrent stage on (selection items
// E2-07c, insert items E2-12, recording panel E2-16).
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show Listenable, ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

@immutable
class EditorMenuContext {
  const EditorMenuContext({
    required this.noteId,
    required this.pageIds,
    required this.currentPageIndex,
    this.selectedPageIds = const [],
    required this.navigateToPage,
  });
  final String noteId;
  final List<String> pageIds; // note order
  final int currentPageIndex;
  final List<String> selectedPageIds; // page panel multi-select, note order
  /// Jump/scroll to the page; when focusRectPt is given, bring that page rect into view.
  /// (v1.1) focusRectPt is in displayed page coordinates: pt of the note's Page.size,
  /// origin top-left, y down — same as core.Stroke points (PDF converts its search hits).
  final void Function(String pageId, Rect? focusRectPt) navigateToPage;

  /// `pageIds[currentPageIndex]`, or null when the index is outside the list
  /// (04-editor 4.5 table).
  String? get currentPageId =>
      currentPageIndex >= 0 && currentPageIndex < pageIds.length
      ? pageIds[currentPageIndex]
      : null;
}

/// One item contributed to the editor's more menu or to the '다른 소스' row of
/// the add-page sheet (04-editor 4.5).
///
/// onSelected is awaited after the menu closes and cannot run twice at the
/// same time; an exception is reported with FlutterError.reportError and a
/// '실행하지 못했어요' snack bar (contract 7.4.5). isEnabled == false shows the
/// item greyed out (not hidden).
@immutable
class EditorMenuItem {
  const EditorMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.isEnabled,
  });

  /// Stable id (e.g. 'pdf.export'); used as widget key and in tests.
  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, EditorMenuContext menu)
  onSelected;
  final bool Function(EditorMenuContext menu)? isEnabled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorMenuItem &&
          other.id == id &&
          other.label == label &&
          other.icon == icon &&
          other.onSelected == onSelected &&
          other.isEnabled == isEnabled;

  @override
  int get hashCode => Object.hash(id, label, icon, onSelected, isEnabled);

  @override
  String toString() => 'EditorMenuItem($id, "$label")';
}

@immutable
class EditorExtensions {
  const EditorExtensions({
    this.moreMenuItems = const [],
    this.addPageSources = const [],
    this.appBarTrailing,
    this.selectionMenuItems = const [],
    this.insertMenuItems = const [],
    this.recordingPanel,
    this.mathPen,
    this.textPen,
  });
  final List<EditorMenuItem> moreMenuItems; // PDF: export, share, print, search
  final List<EditorMenuItem> addPageSources; // PDF: insert pages from PDF
  final WidgetBuilder? appBarTrailing; // reserved, unused in this scope
  final List<EditorSelectionMenuItem>
  selectionMenuItems; // recog: toText, copyText, toMath, editMath
  final List<EditorInsertMenuItem> insertMenuItems; // recog: mathPad
  final EditorPanelBuilder?
  recordingPanel; // media_io RecordingPanel; null → mic button hidden
  /// (math pen, phase 1) recog's recognition for the 수식 펜 tool; null → no
  /// math pen tool (a stored "math" tool acts as the pen).
  final EditorMathPen? mathPen;

  /// (text pen, phase 1) recog's recognition for the 텍스트 펜 tool and the
  /// insert menu's '손글씨를 텍스트로'; null → neither (a stored "textPen"
  /// tool acts as the pen).
  final EditorTextPen? textPen;

  static const _items = ListEquality<EditorMenuItem>();
  static const _selectionItems = ListEquality<EditorSelectionMenuItem>();
  static const _insertItems = ListEquality<EditorInsertMenuItem>();

  /// Lists compare in order, item by item; the builder fields compare as
  /// functions (04-editor 4.3.1).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorExtensions &&
          _items.equals(other.moreMenuItems, moreMenuItems) &&
          _items.equals(other.addPageSources, addPageSources) &&
          other.appBarTrailing == appBarTrailing &&
          _selectionItems.equals(
            other.selectionMenuItems,
            selectionMenuItems,
          ) &&
          _insertItems.equals(other.insertMenuItems, insertMenuItems) &&
          other.recordingPanel == recordingPanel &&
          other.mathPen == mathPen &&
          other.textPen == textPen;

  @override
  int get hashCode => Object.hash(
    _items.hash(moreMenuItems),
    _items.hash(addPageSources),
    appBarTrailing,
    _selectionItems.hash(selectionMenuItems),
    _insertItems.hash(insertMenuItems),
    recordingPanel,
    mathPen,
    textPen,
  );

  @override
  String toString() =>
      'EditorExtensions(more: $moreMenuItems, addPage: $addPageSources, '
      'selection: $selectionMenuItems, insert: $insertMenuItems, '
      'recordingPanel: ${recordingPanel != null}, '
      'mathPen: ${mathPen != null}, textPen: ${textPen != null})';
}

final editorExtensionsProvider = Provider<EditorExtensions>(
  (ref) => const EditorExtensions(),
  name: 'editorExtensionsProvider',
);

/// What a selection menu item gets (v2.0). Built anew each time the
/// selection menu runs an item, so it has no `==` (04-editor 4.3.1).
@immutable
class EditorSelectionContext {
  const EditorSelectionContext({
    required this.noteId,
    required this.pageId,
    required this.pageSize,
    required this.strokes,
    required this.objects,
    required this.boundsPt,
    required this.execute,
    required this.clearSelection,
  });
  final String noteId, pageId;
  final core.PageSize pageSize;
  final List<core.Stroke> strokes; // selected, z order
  final List<core.PageObject> objects; // selected, z order
  final Rect boundsPt; // page pt
  /// Runs ONE command on the note session (one undo step). Throws like NoteSession.execute
  /// (ReadOnlyNoteException …); the caller shows the message.
  final void Function(core.EditCommand command) execute;
  final VoidCallback clearSelection;
}

/// One item of the selection menu (v2.0 — recog: toText, copyText, toMath,
/// editMath).
///
/// The editor calls [onSelected] synchronously inside the button's
/// onPressed, with the editor body's context, and closes the menu after
/// that call (contract 7.2.10 (v2.1)). [isVisible] runs every time the menu
/// is built: keep it light and do not read providers.
@immutable
class EditorSelectionMenuItem {
  const EditorSelectionMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.isVisible,
    this.pinned = false,
  });
  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(
    BuildContext context,
    EditorSelectionContext selection,
  )
  onSelected;
  final bool Function(EditorSelectionContext selection)? isVisible;

  /// (text pen track) Always on the bar, before '⋯', whatever the width
  /// (recog: '텍스트로 변환'); the others fill the rest of the bar's
  /// places (SelectionMenu.maxBarItems) by width.
  final bool pinned;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorSelectionMenuItem &&
          other.id == id &&
          other.label == label &&
          other.icon == icon &&
          other.onSelected == onSelected &&
          other.isVisible == isVisible &&
          other.pinned == pinned;

  @override
  int get hashCode =>
      Object.hash(id, label, icon, onSelected, isVisible, pinned);

  @override
  String toString() => 'EditorSelectionMenuItem($id, "$label")';
}

/// What an insert menu item gets (v2.0). Built anew for each run, so it has
/// no `==` (04-editor 4.3.1).
@immutable
class EditorInsertContext {
  const EditorInsertContext({
    required this.noteId,
    required this.pageId,
    required this.pageSize,
    required this.visibleRectPt,
    required this.execute,
    required this.selectObject,
  });
  final String noteId, pageId;
  final core.PageSize pageSize;
  final Rect visibleRectPt; // insert near its center
  final void Function(core.EditCommand command) execute;
  final void Function(String objectId)
  selectObject; // select what was just inserted
}

/// One item of the insert menu `[+]` (v2.0 — recog: mathPad). Called like
/// [EditorSelectionMenuItem.onSelected]: synchronously inside onPressed,
/// with the editor body's context, before the menu closes.
@immutable
class EditorInsertMenuItem {
  const EditorInsertMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
  });
  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, EditorInsertContext insert)
  onSelected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorInsertMenuItem &&
          other.id == id &&
          other.label == label &&
          other.icon == icon &&
          other.onSelected == onSelected;

  @override
  int get hashCode => Object.hash(id, label, icon, onSelected);

  @override
  String toString() => 'EditorInsertMenuItem($id, "$label")';
}

/// Builds the bottom panel slot (v2.0 — media_io RecordingPanel).
typedef EditorPanelBuilder = Widget Function(
  BuildContext context,
  EditorPanelContext panel,
);

/// What the panel builder gets (v2.0). Built when the panel opens, so it has
/// no `==` (04-editor 4.3.1).
@immutable
class EditorPanelContext {
  const EditorPanelContext({
    required this.noteId,
    required this.tapToSeek,
    required this.setTapToSeek,
    required this.close,
  });
  final String noteId;
  final ValueListenable<bool>
  tapToSeek; // EDITOR owns the flag (finger tap on a recorded stroke → seek)
  final ValueChanged<bool> setTapToSeek;
  final VoidCallback close;
}

// --- (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 11.1) ---

/// The math pen slot: recog's recognition behind the editor's 수식 펜 tool.
/// The editor owns the tool, the strokes, the grouping, the bubble's place
/// and the commands host; [open] gives the per-note recognition session
/// (once per note screen, disposed with it). Compares by [open].
@immutable
class EditorMathPen {
  const EditorMathPen({required this.open});
  final EditorMathPenSession Function(EditorMathPenContext context) open;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EditorMathPen && other.open == open;

  @override
  int get hashCode => open.hashCode;
}

/// What [EditorMathPen.open] gets — built by the editor per note screen (no
/// `==`).
@immutable
class EditorMathPenContext {
  const EditorMathPenContext({
    required this.noteId,
    required this.pageSizeOf,
    required this.execute,
    required this.liveStrokes,
    required this.bodyContext,
  });
  final String noteId;

  /// The size of page [pageId], or null when it is not in the note.
  final core.PageSize? Function(String pageId) pageSizeOf;

  /// Runs ONE command (one undo step); throws like NoteSession.execute.
  final void Function(core.EditCommand command) execute;

  /// The current strokes [ids] of [pageId] (in that order), or null when
  /// the page is not loaded or any of them is gone.
  final List<core.Stroke>? Function(String pageId, List<String> ids)
  liveStrokes;

  /// The editor body's context while it is mounted (sheets, providers).
  final BuildContext? Function() bodyContext;
}

/// The open handwriting group of the math pen — a value copy made by the
/// editor whenever the group changes.
@immutable
class EditorMathGroup {
  const EditorMathGroup({
    required this.pageId,
    required this.strokes,
    required this.boundsPt,
    this.reopenedFrom,
    this.reopenedStrokeIds = const {},
  });
  final String pageId;

  /// The group's strokes, z order.
  final List<core.Stroke> strokes;

  /// The union of the strokes' point bounds (page pt).
  final Rect boundsPt;

  /// The formula this group was reopened from (its handwriting), if any.
  final core.MathObject? reopenedFrom;

  /// The ids the reopened handwriting got (a subset of [strokes]).
  final Set<String> reopenedStrokeIds;
}

/// Why the editor converts a group.
enum EditorMathConvertTrigger {
  /// The user tapped the bubble (a sheet may open).
  bubbleTap,

  /// The user switched to another tool (never opens a sheet).
  toolSwitch,

  /// The user started a new group away from this one (never opens a sheet).
  newGroup,
}

/// recog's per-note recognition session behind the math pen.
abstract interface class EditorMathPenSession {
  /// The group's strokes changed: recognize them again (debounced).
  void update(EditorMathGroup group);

  /// A new contact: stop the timer and cancel the request in flight.
  void interrupt();

  /// The group is gone (no conversion).
  void clear();

  /// Converts [group] with ONE execute (one undo step); completes true when
  /// the formula was added. Only [EditorMathConvertTrigger.bubbleTap] may
  /// open a sheet. A background conversion (toolSwitch / newGroup) keeps the
  /// handwriting in the formula or does not convert, and asks [stillWanted]
  /// right before its execute (after any wait for an answer): false → it
  /// does not convert (the editor's history moved on meanwhile — a late step
  /// would land on top of the user's later work and clear redo).
  Future<bool> convert(
    EditorMathGroup group,
    EditorMathConvertTrigger trigger, {
    bool Function()? stillWanted,
  });

  /// '고치기': the LaTeX editor on [math] (one UpdateObjects).
  Future<void> fix(core.MathObject math);

  /// Fires when what [buildBubble] shows changes.
  Listenable get changes;

  /// The bubble's content for [group]; [onConvert] converts it (a button
  /// inside the content may call it).
  Widget buildBubble(
    BuildContext context,
    EditorMathGroup group,
    VoidCallback onConvert,
  );

  void dispose();
}

// --- (text pen, phase 1 — m5-7/04-editor 6.21, contract C210) ---

/// What a pen session gets (the math pen's context, shared).
typedef EditorPenContext = EditorMathPenContext;

/// An open pen group (the math pen's value, shared; reopenedFrom is always
/// null for the text pen).
typedef EditorPenGroup = EditorMathGroup;

/// The text pen slot: recog's recognition behind the editor's 텍스트 펜. The
/// editor owns the tool, the strokes, the grouping and the bubble's frame;
/// [open] gives the per-note session (once per note screen, disposed with
/// it). Compares by [open].
@immutable
class EditorTextPen {
  const EditorTextPen({required this.open});
  final EditorTextPenSession Function(EditorPenContext context) open;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EditorTextPen && other.open == open;

  @override
  int get hashCode => open.hashCode;
}

/// recog's per-note recognition session behind the text pen. Unlike the
/// math pen nothing converts in the background: a group stays handwriting
/// until [convert] (the bubble tap) or [fix] (the sheet) runs.
abstract interface class EditorTextPenSession {
  /// The group's strokes changed: recognize them again (debounced).
  void update(EditorPenGroup group);

  /// A new contact: stop the timer; only a newer answer counts.
  void interrupt();

  /// The group is gone (no conversion).
  void clear();

  /// The bubble tap: converts [group] into a text box with ONE execute (one
  /// undo step); completes true when the box was added. With no usable
  /// answer it may open the conversion sheet.
  Future<bool> convert(EditorPenGroup group);

  /// '고치기' / a long press on the bubble, and the insert menu's
  /// '손글씨를 텍스트로' with an ink selection: the conversion sheet on
  /// [group]'s strokes (per-line editing, candidates); true when it
  /// converted.
  Future<bool> fix(EditorPenGroup group);

  /// Fires when what [buildBubble] shows changes.
  Listenable get changes;

  /// The bubble's content for [group]; [onConvert] converts it, [onFix]
  /// opens the sheet (buttons inside the content may call them).
  Widget buildBubble(
    BuildContext context,
    EditorPenGroup group,
    VoidCallback onConvert,
    VoidCallback onFix,
  );

  void dispose();
}
