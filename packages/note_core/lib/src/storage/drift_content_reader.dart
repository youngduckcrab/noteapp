// lib/src/storage/drift_content_reader.dart (internal) — NoteContentReader on SQLite
// (CORE 4.5: committed state, read outside sessions — PDF export, thumbnails).
import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../edit/command_resolver.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../repo/content_reader.dart';
import '../session/page_content.dart';
import 'db/note_database.dart';
import 'row_mappers.dart';

final class DriftContentReader implements NoteContentReader {
  DriftContentReader(this._db);
  final NoteDatabase _db;

  @override
  Future<List<Page>> pagesOf(NoteId noteId) async {
    final rows = await (_db.select(
      _db.pages,
    )..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())).get();
    return List<Page>.unmodifiable(
      <Page>[for (final r in rows) pageOf(r)]..sort(comparePages),
    );
  }

  @override
  Future<PageContent> loadPage(PageId pageId) async {
    final row = await (_db.select(
      _db.pages,
    )..where((t) => t.id.equals(pageId))).getSingleOrNull();
    if (row == null) {
      throw EntityNotFoundException('Page $pageId does not exist');
    }
    final strokes = await (_db.select(
      _db.strokes,
    )..where((t) => t.pageId.equals(pageId) & t.deletedAt.isNull())).get();
    return PageContent(
      page: pageOf(row),
      strokes: [for (final r in strokes) strokeOf(r)]
        ..sort(Stroke.compareOrder),
      revision: 0,
    );
  }

  @override
  Future<Page?> getPage(PageId pageId) async {
    final row =
        await (_db.select(_db.pages)
              ..where((t) => t.id.equals(pageId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : pageOf(row);
  }
}
