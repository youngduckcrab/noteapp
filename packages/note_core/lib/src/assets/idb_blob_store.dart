// lib/src/assets/idb_blob_store.dart (internal) — the IndexedDB of asset chunks and
// thumbnails through idb_shim (CORE 6.13). The web passes idbFactoryBrowser; the VM
// passes an in-memory factory (newIdbFactoryMemory), so tests run the same code.
//
// Database '<WebStorageConfig.blobDatabaseName>' v1:
//   asset_chunks  key '<assetId>/<chunkIndex 6 digits>' → Uint8List
//   thumbnails    key pageId → {rev, w, h, mime, bytes}
import 'dart:async';
import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import '../common/ids.dart';
import 'asset_store.dart';
import 'blob_store.dart';

const String kAssetChunksStore = 'asset_chunks';
const String kThumbnailsStore = 'thumbnails';
const int kBlobDatabaseVersion = 1;

/// The blob IndexedDB of one note store. Opened on first use; a failed open is
/// retried by the next operation. Another connection asking for a version change
/// (deleteLocalNoteData in another tab) closes this one; the next use reopens.
final class IdbBlobDatabase implements BlobDatabase {
  IdbBlobDatabase(this._factory, this.name);

  final IdbFactory _factory;
  final String name;
  Future<Database>? _db;
  bool _closed = false;

  @override
  late final BlobStore chunks = _IdbBlobStore(this, kAssetChunksStore);
  @override
  late final ThumbnailStore thumbnails = _IdbThumbnailStore(this);

  Future<Database> _open() {
    if (_closed) {
      return Future.error(StateError('The blob database is closed'));
    }
    final open = _db ??= _factory
        .open(
          name,
          version: kBlobDatabaseVersion,
          onUpgradeNeeded: (e) {
            final db = e.database;
            if (!db.objectStoreNames.contains(kAssetChunksStore)) {
              db.createObjectStore(kAssetChunksStore);
            }
            if (!db.objectStoreNames.contains(kThumbnailsStore)) {
              db.createObjectStore(kThumbnailsStore);
            }
          },
        )
        .then((db) {
          db.onVersionChange.listen((_) {
            db.close();
            _db = null;
          });
          return db;
        });
    open.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_db, open)) _db = null;
      },
    );
    return open;
  }

  /// Runs [body] on [store] in one transaction and waits for it to complete.
  Future<T> run<T>(
    String store,
    String mode,
    Future<T> Function(ObjectStore s) body,
  ) async {
    final db = await _open();
    final txn = db.transaction(store, mode);
    final value = await body(txn.objectStore(store));
    await txn.completed;
    return value;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final db = _db;
    _db = null;
    if (db == null) return;
    try {
      (await db).close();
    } on Object {
      // Never opened: nothing to close.
    }
  }

  /// Deletes the database [name] of [factory] (6.18 deleteLocalNoteData).
  static Future<void> deleteDatabase(IdbFactory factory, String name) async {
    await factory.deleteDatabase(name);
  }
}

KeyRange _prefixRange(String prefix) =>
    KeyRange.bound(prefix, '$prefix￿', false, false);

final class _IdbBlobStore implements BlobStore {
  _IdbBlobStore(this._db, this._store);
  final IdbBlobDatabase _db;
  final String _store;

  @override
  Future<void> put(String key, Uint8List bytes) =>
      _db.run(_store, idbModeReadWrite, (s) => s.put(bytes, key));

  @override
  Future<Uint8List?> get(String key) =>
      _db.run(_store, idbModeReadOnly, (s) async {
        final v = await s.getObject(key);
        return v == null ? null : _bytesOf(v);
      });

  @override
  Future<List<Uint8List?>> getMany(List<String> keys) async {
    if (keys.isEmpty) return const [];
    return _db.run(_store, idbModeReadOnly, (s) async {
      final values = await Future.wait([for (final k in keys) s.getObject(k)]);
      return [for (final v in values) v == null ? null : _bytesOf(v)];
    });
  }

  @override
  Future<void> delete(String key) =>
      _db.run(_store, idbModeReadWrite, (s) => s.delete(key));

  @override
  Future<void> deletePrefix(String prefix) =>
      _db.run(_store, idbModeReadWrite, (s) => s.delete(_prefixRange(prefix)));

  @override
  Future<List<String>> keys(String prefix) =>
      _db.run(_store, idbModeReadOnly, (s) async {
        final keys = await s.getAllKeys(_prefixRange(prefix));
        return [for (final k in keys) k as String]..sort();
      });
}

Uint8List _bytesOf(Object v) => switch (v) {
  final Uint8List b => b,
  final List<Object?> l => Uint8List.fromList(l.cast<int>()),
  _ => throw FormatException('Not a byte value', v.runtimeType.toString()),
};

final class _IdbThumbnailStore implements ThumbnailStore {
  _IdbThumbnailStore(this._db);
  final IdbBlobDatabase _db;

  @override
  Future<void> put(PageThumbnail t) =>
      _db.run(kThumbnailsStore, idbModeReadWrite, (s) {
        return s.put(<String, Object?>{
          'rev': t.contentRevision,
          'w': t.width,
          'h': t.height,
          'mime': t.mimeType,
          'bytes': t.bytes,
        }, t.pageId);
      });

  @override
  Future<PageThumbnail?> get(PageId pageId) =>
      _db.run(kThumbnailsStore, idbModeReadOnly, (s) async {
        final v = await s.getObject(pageId);
        return v == null ? null : _thumbnailOf(pageId, v);
      });

  @override
  Future<void> delete(Iterable<PageId> pageIds) async {
    final ids = pageIds.toList();
    if (ids.isEmpty) return;
    await _db.run(kThumbnailsStore, idbModeReadWrite, (s) async {
      for (final id in ids) {
        await s.delete(id);
      }
    });
  }

  @override
  Future<int> totalBytes() =>
      _db.run(kThumbnailsStore, idbModeReadOnly, (s) async {
        var total = 0;
        for (final v in await s.getAll()) {
          final Object? bytes = v is Map ? v['bytes'] : null;
          if (bytes != null) total += _bytesOf(bytes).length;
        }
        return total;
      });
}

/// A stored record back to a thumbnail; null when it is not one (never written by
/// this version) — the cache then reads as empty for that page.
PageThumbnail? _thumbnailOf(PageId pageId, Object v) {
  if (v is! Map) return null;
  final Object? rev = v['rev'], w = v['w'], h = v['h'], mime = v['mime'];
  final Object? bytes = v['bytes'];
  if (rev is! num || w is! num || h is! num || mime is! String) return null;
  if (bytes == null) return null;
  return PageThumbnail(
    pageId: pageId,
    contentRevision: rev.toInt(),
    width: w.toInt(),
    height: h.toInt(),
    mimeType: mime,
    bytes: _bytesOf(bytes),
  );
}
