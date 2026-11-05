// lib/src/integration/pdf_slots.dart — contract 00-overview 7.2.18, 05-library 4.3.
// The app shell overrides both slots with pdf_io's importPdfAsNewNote /
// exportNotesAsPdf (FeatureWiringModule, contract 7.3.3); feature_library never
// imports pdf_io (7.1 rule 1).
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:material_ui/material_ui.dart' show BuildContext;

/// PDF import flow owned by pdf_io; returns the created note id or null (cancel / handled error).
typedef LibraryPdfImportAction = Future<String?> Function(
  BuildContext context, {
  String? folderId,
});
final libraryPdfImportActionProvider = Provider<LibraryPdfImportAction?>(
  (ref) => null,
  name: 'libraryPdfImportActionProvider',
); // null → menu disabled '준비 중'

/// Multi-select bulk export (F-01) owned by pdf_io; null → button hidden.
typedef LibraryPdfExportAction = Future<void> Function(
  BuildContext context,
  List<String> noteIds,
);
final libraryPdfExportActionProvider = Provider<LibraryPdfExportAction?>(
  (ref) => null,
  name: 'libraryPdfExportActionProvider',
);
