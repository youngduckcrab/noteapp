// lib/src/import/import_types.dart — 06-pdf 4.6.
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

sealed class PdfImportTarget {
  const PdfImportTarget();
}

final class PdfImportAsNewNote extends PdfImportTarget {
  const PdfImportAsNewNote({this.folderId, this.title});
  final core.FolderId? folderId; // null = top level
  final String? title; // null → PdfImportSession.suggestedTitle
}

final class PdfImportIntoNote extends PdfImportTarget {
  const PdfImportIntoNote({required this.noteId, required this.position});
  final core.NoteId noteId;

  /// core.PageAfter(currentPageId) by default from the editor
  final core.PagePosition position;
}

@immutable
final class PdfImportResult {
  const PdfImportResult({
    required this.noteId,
    required this.insertedPageIds,
    required this.assetId,
    required this.sourcePageCount,
    required this.storedDecryptedCopy,
    required this.createdNewNote,
  });
  final core.NoteId noteId;
  final List<core.PageId> insertedPageIds;
  final core.AssetId assetId;
  final int sourcePageCount;

  /// user-password PDF stored without security (6.4)
  final bool storedDecryptedCopy;
  final bool createdNewNote;
  core.PageId get firstPageId => insertedPageIds.first;

  static const ListEquality<core.PageId> _ids = ListEquality<core.PageId>();

  /// The only value-equal result payload (no bytes): every field, insertedPageIds with
  /// ListEquality (contract 7.4.4).
  @override
  bool operator ==(Object other) =>
      other is PdfImportResult &&
      other.noteId == noteId &&
      _ids.equals(other.insertedPageIds, insertedPageIds) &&
      other.assetId == assetId &&
      other.sourcePageCount == sourcePageCount &&
      other.storedDecryptedCopy == storedDecryptedCopy &&
      other.createdNewNote == createdNewNote;

  @override
  int get hashCode => Object.hash(
    noteId,
    _ids.hash(insertedPageIds),
    assetId,
    sourcePageCount,
    storedDecryptedCopy,
    createdNewNote,
  );

  @override
  String toString() =>
      'PdfImportResult(noteId: $noteId, pages: ${insertedPageIds.length}, '
      'assetId: $assetId, sourcePageCount: $sourcePageCount, '
      'storedDecryptedCopy: $storedDecryptedCopy, '
      'createdNewNote: $createdNewNote)';
}
