// A NoteStore around the shared fake store (contract 7.6 createFakeNoteStore
// v2) that records the calls the indexer makes (6.9.7 — 'fresh page →
// loadPage 0') and can re-emit its change batches with another origin (the
// fake store has no remote path — 30 s quiet time for remote changes).
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

final class RecordingNoteStore implements core.NoteStore {
  RecordingNoteStore(this.inner) {
    _forward = inner.changes.listen((batch) {
      final origin = originOverride;
      _changes.add(
        origin == null
            ? batch
            : core.ChangeBatch(
                origin: origin,
                changes: batch.changes,
                committedAt: batch.committedAt,
              ),
      );
    });
  }

  final core.NoteStore inner;
  late final StreamSubscription<core.ChangeBatch> _forward;
  final StreamController<core.ChangeBatch> _changes =
      StreamController<core.ChangeBatch>.broadcast(sync: true);

  /// Set → every batch of [inner] is re-emitted with this origin.
  core.ChangeOrigin? originOverride;

  /// Thrown (once) by the next handwriting update — a CORE write failure.
  Object? failNextUpdate;

  // 'flush', 'stalePages:<note>', 'notesWithStalePages', 'forPage:<page>',
  // 'loadPage:<page>', 'update:<page>', 'removeForPage:<page>',
  // 'put:<page>' — in call order.
  final List<String> calls = [];

  /// Calls whose entry starts with [prefix].
  int count(String prefix) => calls.where((c) => c.startsWith(prefix)).length;

  /// The writes of the handwriting repository (update / removeForPage / put).
  int get handwritingWrites =>
      count('update:') + count('removeForPage:') + count('put:');

  @override
  late final core.NoteContentReader content = _Content(this);
  @override
  late final core.HandwritingRepository handwriting = _Handwriting(this);

  @override
  Stream<core.ChangeBatch> get changes => _changes.stream;

  @override
  Future<void> flush() {
    calls.add('flush');
    return inner.flush();
  }

  @override
  Future<void> close() async {
    await inner.close();
    // Not awaited (root-zone futures never complete under fake_async).
    unawaited(_forward.cancel());
    unawaited(_changes.close());
  }

  // ---- plain delegation ----
  @override
  core.OwnerId get ownerId => inner.ownerId;
  @override
  core.LibraryRepository get library => inner.library;
  @override
  core.TrashRepository get trash => inner.trash;
  @override
  core.PenPresetRepository get penPresets => inner.penPresets;
  @override
  core.SettingsRepository get settings => inner.settings;
  @override
  core.AssetStore get assets => inner.assets;
  @override
  core.ThumbnailCache get thumbnails => inner.thumbnails;
  @override
  core.SyncStore get sync => inner.sync;
  @override
  core.PersistenceStatus get persistenceStatus => inner.persistenceStatus;
  @override
  Stream<core.PersistenceStatus> get persistenceStatusStream =>
      inner.persistenceStatusStream;
  @override
  core.StorageInfo get storageInfo => inner.storageInfo;
  @override
  core.IdGenerator get ids => inner.ids;
  @override
  // The type is package:clock's Clock — not a dependency of this package.
  // ignore: always_declare_return_types
  get clock => inner.clock;
  @override
  Future<core.StorageInfo> refreshStorageInfo() => inner.refreshStorageInfo();
  @override
  Future<core.NoteSession> openSession(
    core.NoteId noteId, {
    core.NoteSessionOptions options = const core.NoteSessionOptions(),
  }) => inner.openSession(noteId, options: options);
  @override
  Future<Uint8List> exportBackupJson() => inner.exportBackupJson();
  @override
  core.RecordingRepository get recordings => inner.recordings;
  @override
  core.RecordingDraftStore get recordingDrafts => inner.recordingDrafts;
  @override
  core.SearchIndex get search => inner.search;
}

final class _Content implements core.NoteContentReader {
  _Content(this.s);
  final RecordingNoteStore s;

  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) =>
      s.inner.content.pagesOf(noteId);

  @override
  Future<core.PageContent> loadPage(core.PageId pageId) {
    s.calls.add('loadPage:$pageId');
    return s.inner.content.loadPage(pageId);
  }

  @override
  Future<core.Page?> getPage(core.PageId pageId) =>
      s.inner.content.getPage(pageId);
}

final class _Handwriting implements core.HandwritingRepository {
  _Handwriting(this.s);
  final RecordingNoteStore s;
  core.HandwritingRepository get _h => s.inner.handwriting;

  @override
  Future<core.HandwritingText?> forPage(core.PageId pageId) {
    s.calls.add('forPage:$pageId');
    return _h.forPage(pageId);
  }

  @override
  Stream<core.HandwritingText?> watchPage(core.PageId pageId) =>
      _h.watchPage(pageId);

  @override
  Future<void> put(core.HandwritingText value) {
    s.calls.add('put:${value.pageId}');
    return _h.put(value);
  }

  @override
  Future<core.HandwritingText?> update(
    core.PageId pageId,
    core.HandwritingText? Function(core.HandwritingText? current) transform,
  ) {
    s.calls.add('update:$pageId');
    final failure = s.failNextUpdate;
    if (failure != null) {
      s.failNextUpdate = null;
      return Future.error(failure);
    }
    return _h.update(pageId, transform);
  }

  @override
  Future<void> removeForPage(core.PageId pageId) {
    s.calls.add('removeForPage:$pageId');
    return _h.removeForPage(pageId);
  }

  @override
  Future<List<core.PageId>> stalePages(core.NoteId noteId) {
    s.calls.add('stalePages:$noteId');
    return _h.stalePages(noteId);
  }

  @override
  Future<List<core.NoteId>> notesWithStalePages() {
    s.calls.add('notesWithStalePages');
    return _h.notesWithStalePages();
  }
}
