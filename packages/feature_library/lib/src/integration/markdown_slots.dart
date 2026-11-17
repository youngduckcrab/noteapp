// lib/src/integration/markdown_slots.dart — (v2.17-md, C217M-11, m5-7/08-markdown 9) the
// slots of MD 문서 import and export. The app shell overrides both (markdown_wiring.dart —
// file picking and saving are pdf_io's, sharing is the app's); feature_library imports
// neither pdf_io nor feature_markdown (7.1 rule 1).
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:material_ui/material_ui.dart' show BuildContext;

/// 'MD 가져오기' into [folderId]: picks .md / .markdown / .txt files and creates one MD
/// 문서 per file. Returns the document to open (exactly one was imported) or null (cancel,
/// several imported, or every file refused — the flow showed its own message).
typedef LibraryMarkdownImportAction = Future<String?> Function(
  BuildContext context, {
  String? folderId,
});
final libraryMarkdownImportActionProvider =
    Provider<LibraryMarkdownImportAction?>(
      (ref) => null,
      name: 'libraryMarkdownImportActionProvider',
    ); // null → 'MD 가져오기' hidden

/// '.md로 내보내기' of the MD 문서 [noteId] (its text byte for byte). null → hidden.
typedef LibraryMarkdownExportAction = Future<void> Function(
  BuildContext context,
  String noteId,
);
final libraryMarkdownExportActionProvider =
    Provider<LibraryMarkdownExportAction?>(
      (ref) => null,
      name: 'libraryMarkdownExportActionProvider',
    );
