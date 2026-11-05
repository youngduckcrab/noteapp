// lib/src/di/editor_extensions.dart — contract 00-overview 7.2.17,
// 04-editor 4.5.
//
// Extension points other areas fill through the app shell: INFRA's
// FeatureWiringModule overrides editorExtensionsProvider with PDF's menu
// actions (contract 7.3.3). The editor reads the provider and builds an
// EditorMenuContext when a menu opens (04-editor 6.11.5).
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
  });
  final List<EditorMenuItem> moreMenuItems; // PDF: export, share, print, search
  final List<EditorMenuItem> addPageSources; // PDF: insert pages from PDF
  final WidgetBuilder? appBarTrailing; // reserved, unused in this scope

  static const _items = ListEquality<EditorMenuItem>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorExtensions &&
          _items.equals(other.moreMenuItems, moreMenuItems) &&
          _items.equals(other.addPageSources, addPageSources) &&
          other.appBarTrailing == appBarTrailing;

  @override
  int get hashCode => Object.hash(
    _items.hash(moreMenuItems),
    _items.hash(addPageSources),
    appBarTrailing,
  );

  @override
  String toString() =>
      'EditorExtensions(more: $moreMenuItems, addPage: $addPageSources)';
}

final editorExtensionsProvider = Provider<EditorExtensions>(
  (ref) => const EditorExtensions(),
  name: 'editorExtensionsProvider',
);
