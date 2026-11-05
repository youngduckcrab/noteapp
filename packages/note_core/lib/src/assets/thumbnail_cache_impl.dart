// lib/src/assets/thumbnail_cache_impl.dart (internal) — ThumbnailCache of the SQLite
// store (CORE 6.13): device-local records in the blob IndexedDB, never synced.
//
// Operations run one after another (a read after a write or a purge sees it).
// Pages purged from the trash lose their thumbnails after that commit (6.13).
import 'dart:async';

import '../common/ids.dart';
import 'asset_store.dart';
import 'blob_store.dart';

final class ThumbnailCacheImpl implements ThumbnailCache {
  ThumbnailCacheImpl(this._store);

  final ThumbnailStore _store;
  final StreamController<PageId> _updates = StreamController.broadcast();
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  @override
  Stream<PageId> get updates => _updates.stream;

  /// Runs [op] after every earlier operation.
  Future<T> _serial<T>(Future<T> Function() op) {
    if (_closed) return Future.error(StateError('The note store is closed'));
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _emit(PageId id) {
    if (!_updates.isClosed) _updates.add(id);
  }

  @override
  Future<PageThumbnail?> read(PageId pageId) =>
      _serial(() => _store.get(pageId));

  @override
  Future<void> write(PageThumbnail thumbnail) => _serial(() async {
    await _store.put(thumbnail);
    _emit(thumbnail.pageId);
  });

  @override
  Future<void> delete(PageId pageId) => _serial(() async {
    await _store.delete([pageId]);
    _emit(pageId);
  });

  /// Drops the thumbnails of purged pages (no updates event, like the fake store).
  /// A failure is not reported: the record is only a cache.
  void dropPurged(List<PageId> pageIds) {
    if (pageIds.isEmpty || _closed) return;
    unawaited(
      _serial(() => _store.delete(pageIds))
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// Sum of the stored image bytes (AssetStore.usage).
  Future<int> totalBytes() => _serial(_store.totalBytes);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _tail;
    await _updates.close();
  }
}
