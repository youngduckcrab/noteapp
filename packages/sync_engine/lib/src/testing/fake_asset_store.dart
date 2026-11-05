// Internal (not exported). CORE AssetStore over the fake device state (contract 7.2.11
// v1.3, 5.1.4 C-23, C-25).
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_core/note_core.dart';

import 'fake_sync_store.dart';

/// Lowercase hex SHA-256 of [bytes] (CORE AssetId).
String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

final class FakeAssetStore implements AssetStore {
  FakeAssetStore(this._s);

  final FakeStoreState _s;

  @override
  Future<Asset> put(
    Uint8List bytes, {
    required AssetType type,
    required String mimeType,
    String? fileName,
  }) async {
    _s.checkWrite('assets.put');
    final id = sha256Hex(bytes);
    final ref = EntityRef(EntityKind.asset, id);
    final newBytes = !_s.blobs.containsKey(id);
    if (newBytes) _s.blobs[id] = Uint8List.fromList(bytes);
    final row = _s.rows[ref];
    if (row != null) {
      final asset = row.entity as Asset;
      if (!asset.hasLocalBytes) {
        _s.putRow(
          VersionedEntity(asset.copyWith(hasLocalBytes: true), row.versions),
        );
      }
    } else {
      _s.transaction(
        (_) => _s.localCommit([
          (
            kind: EntityKind.asset,
            json: {
              'id': id,
              'ownerId': _s.ownerId,
              'type': type.name,
              'mimeType': mimeType,
              'size': bytes.length,
              'fileName': fileName,
              'storagePath': null,
              'createdAt': _s.millis,
              'deletedAt': null,
            },
            fields: const {kAllFields},
          ),
        ]),
      );
      _s.emitPendingCount();
      _s.emitLocalChange();
    }
    if (newBytes) _s.emitBytesArrived(id);
    return _s.rows[ref]!.entity as Asset;
  }

  @override
  Future<Asset?> getAsset(AssetId id) async =>
      _s.entityOf(EntityKind.asset, id) as Asset?;

  @override
  Future<Uint8List?> readBytes(AssetId id) async {
    final bytes = _s.blobs[id];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<bool> hasBytes(AssetId id) async => _s.blobs.containsKey(id);

  @override
  Future<void> putDownloadedBytes(AssetId id, Uint8List bytes) async {
    _s.checkWrite('assets.putDownloadedBytes');
    final actual = sha256Hex(bytes);
    if (actual != id) {
      throw AssetHashMismatchException(
        'downloaded bytes of $id hash to $actual',
      );
    }
    _s.blobs[id] = Uint8List.fromList(bytes);
    final ref = EntityRef(EntityKind.asset, id);
    final row = _s.rows[ref];
    if (row != null && !(row.entity as Asset).hasLocalBytes) {
      _s.putRow(
        VersionedEntity(
          (row.entity as Asset).copyWith(hasLocalBytes: true),
          row.versions,
        ),
      );
    }
    _s.emitBytesArrived(id);
  }

  @override
  Future<List<Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) async {
    final result = <Asset>[];
    for (final row in _s.rows.values) {
      final e = row.entity;
      if (e is! Asset || e.deletedAt != null) continue;
      if (hasLocalBytes != null && e.hasLocalBytes != hasLocalBytes) continue;
      if (uploaded != null && (e.storagePath != null) != uploaded) continue;
      result.add(e);
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  @override
  Future<void> markUploaded(AssetId id, String storagePath) async {
    _s.checkWrite('assets.markUploaded');
    final row = _s.rows[EntityRef(EntityKind.asset, id)];
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'unknown asset');
    }
    _s.transaction(
      (_) => _s.localCommit([
        (
          kind: EntityKind.asset,
          json: {...row.entity.toJson(), 'storagePath': storagePath},
          fields: const {'storagePath'},
        ),
      ]),
    );
    _s.emitPendingCount();
    _s.emitLocalChange();
  }

  @override
  Future<AssetStorageUsage> usage() async {
    var count = 0, bytes = 0;
    for (final row in _s.rows.values) {
      final e = row.entity;
      if (e is! Asset || e.deletedAt != null) continue;
      count++;
      final local = _s.blobs[e.id];
      if (local != null) bytes += local.length;
    }
    return AssetStorageUsage(
      assetCount: count,
      totalBytes: bytes,
      thumbnailBytes: 0,
    );
  }

  @override
  Stream<AssetId> get bytesArrived => _s.bytesArrived;
}
