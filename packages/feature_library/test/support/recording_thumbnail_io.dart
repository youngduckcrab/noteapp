// test/support/recording_thumbnail_io.dart — L11: logging wrappers around the
// CORE reads / cache the cover thumbnail scheduler uses (6.15.3), so tests can
// see which calls a check made. Web-safe.
import 'package:note_core/note_core.dart';

/// Logs `getPage <id>`, `loadPage <id>` and `pagesOf <id>`, then delegates.
final class RecordingContentReader implements NoteContentReader {
  RecordingContentReader(this._inner);

  final NoteContentReader _inner;
  final List<String> log = [];

  /// The getPage entries of [log] (one per scheduler job).
  List<String> get getPageCalls => [
    for (final e in log)
      if (e.startsWith('getPage ')) e,
  ];

  @override
  Future<Page?> getPage(PageId pageId) {
    log.add('getPage $pageId');
    return _inner.getPage(pageId);
  }

  @override
  Future<PageContent> loadPage(PageId pageId) {
    log.add('loadPage $pageId');
    return _inner.loadPage(pageId);
  }

  @override
  Future<List<Page>> pagesOf(NoteId noteId) {
    log.add('pagesOf $noteId');
    return _inner.pagesOf(noteId);
  }
}

/// Logs `read <id>` and `write <id> rev:<contentRevision>`, then delegates.
final class RecordingThumbnailCache implements ThumbnailCache {
  RecordingThumbnailCache(this._inner);

  final ThumbnailCache _inner;
  final List<String> log = [];

  /// The write entries of [log].
  List<String> get writes => [
    for (final e in log)
      if (e.startsWith('write ')) e,
  ];

  @override
  Future<PageThumbnail?> read(PageId pageId) {
    log.add('read $pageId');
    return _inner.read(pageId);
  }

  @override
  Future<void> write(PageThumbnail thumbnail) {
    log.add('write ${thumbnail.pageId} rev:${thumbnail.contentRevision}');
    return _inner.write(thumbnail);
  }

  @override
  Future<void> delete(PageId pageId) => _inner.delete(pageId);

  @override
  Stream<PageId> get updates => _inner.updates;
}
