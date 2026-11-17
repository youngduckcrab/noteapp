// lib/src/storage/drift_markdown_repository.dart — (v2.17-md) the real store's
// MarkdownRepository (m5-7/08-markdown 12.1, C217M-04).
//
// FOUNDATION PLACEHOLDER: every call fails with UnsupportedError until Track A (A-3) writes
// the md_docs table (DB schema v3) and replaces this class. The app does not wire the MD
// screen before then, so nothing calls it in production.
import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/note.dart';
import '../repo/markdown_repository.dart';
import 'drift_note_store.dart';

final class DriftMarkdownRepository implements MarkdownRepository {
  DriftMarkdownRepository(this.s);

  final DriftNoteStore s;

  static UnsupportedError get _pending =>
      UnsupportedError('MarkdownRepository of the SQLite store: Track A (A-3)');

  @override
  Stream<MarkdownDoc?> watch(NoteId id) => Stream.error(_pending);

  @override
  Future<MarkdownDoc?> get(NoteId id) => Future.error(_pending);

  @override
  Future<Note> create({
    FolderId? folderId,
    required String title,
    String text = '',
  }) => Future.error(_pending);

  @override
  Future<MarkdownSaveResult> saveText(
    NoteId id,
    String text, {
    required Hlc? baseVersion,
  }) => Future.error(_pending);

  @override
  Future<String> preview(
    NoteId id, {
    int maxChars = MarkdownLimits.previewChars,
  }) => Future.error(_pending);
}
