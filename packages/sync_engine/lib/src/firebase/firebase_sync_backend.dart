// The Firestore adapter of SyncBackend (6.4.1, 6.4.6). Paths: users/{uid} (profile),
// users/{uid}/devices/{nodeId}, users/{uid}/changes/{chunkId} (immutable chunks, su =
// serverTimestamp). Every call has a timeout and maps errors with mapFirebaseError.
import 'dart:async';

// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;

import '../backend/blob_store.dart';
import '../backend/profile.dart';
import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../common/errors.dart';
import '../common/server_cursor.dart';
import 'chunk_fields.dart';
import 'firebase_error_mapper.dart';
import 'firestore_chunk_mapper.dart';

final class FirebaseSyncBackend implements SyncBackend {
  FirebaseSyncBackend({
    required FirebaseFirestore firestore,
    required this.blobs,
    required this.uid,
    this._timeout = const Duration(seconds: 30),
  }) : _db = firestore;

  // implements SyncBackend (6.4.6)
  @override
  final String uid;

  @override
  final RemoteBlobStore blobs;

  final FirebaseFirestore _db;
  final Duration _timeout;
  bool _closed = false;

  /// Deletes per WriteBatch (6.4.6).
  static const int _deleteBatch = 400;

  /// Concurrent document reads of getChunks (6.4.6).
  static const int _getConcurrency = 10;

  DocumentReference<Map<String, dynamic>> get _user =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> get _changes =>
      _user.collection(FirestoreChunkMapper.collection);

  /// (su, id) order.
  static Query<Map<String, dynamic>> _ordered(Query<Map<String, dynamic>> q) =>
      q.orderBy(ChunkFields.su).orderBy(FieldPath.documentId);

  /// su >= [since] (null = everything).
  Query<Map<String, dynamic>> _from(ServerCursor? since) => since == null
      ? _changes
      : _changes.where(
          ChunkFields.su,
          isGreaterThanOrEqualTo: ChunkFields.timestampOf(since),
        );

  Future<T> _call<T>(Future<T> Function() body) async {
    if (_closed) {
      throw const SyncBackendException(
        SyncErrorCode.cancelled,
        'backend closed',
      );
    }
    try {
      return await body().timeout(_timeout);
    } on Object catch (e, s) {
      throw mapFirebaseError(e, stackTrace: s);
    }
  }

  /// Pending (su null) and malformed documents are left out.
  static List<RemoteChunk> _chunksOf(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) => [
    for (final d in docs)
      if (d.data() case final data?)
        ?FirestoreChunkMapper.fromFirestore(d.id, data),
  ];

  Future<ChunkPage> _page(
    Query<Map<String, dynamic>> query,
    Object? pageToken,
    int limit,
  ) => _call(() async {
    // Cursor before limit: the same query in Firestore, and the order fake_cloud_firestore
    // applies the two in.
    var q = query;
    if (pageToken is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(pageToken);
    }
    final docs = (await q.limit(limit).get()).docs;
    return ChunkPage(
      _chunksOf(docs),
      // Opaque token: the last document snapshot (6.4.6).
      nextPageToken: docs.isNotEmpty && docs.length >= limit ? docs.last : null,
    );
  });

  @override
  Future<void> commitChunks(List<ChunkWrite> chunks) => _call(() {
    final batch = _db.batch();
    for (final c in chunks) {
      batch.set(_changes.doc(c.id), FirestoreChunkMapper.toFirestore(c));
    }
    return batch.commit();
  });

  @override
  Future<ChunkPage> fetchChunks({
    ServerCursor? since,
    Object? pageToken,
    int limit = 50,
  }) => _page(_ordered(_from(since)), pageToken, limit);

  /// The first snapshot is emitted even when empty; later ones only with added or modified
  /// chunks. Errors are SyncBackendExceptions (the stream ends with the error).
  @override
  Stream<List<RemoteChunk>> watchChunks({ServerCursor? since}) {
    var first = true;
    return _ordered(_from(since))
        .snapshots()
        .map((snapshot) {
          final batch = _chunksOf([
            for (final change in snapshot.docChanges)
              if (change.type != DocumentChangeType.removed) change.doc,
          ]);
          final emit = first || batch.isNotEmpty;
          first = false;
          return emit ? batch : null;
        })
        .where((batch) => batch != null)
        .cast<List<RemoteChunk>>()
        .handleError(
          (Object e, StackTrace s) =>
              Error.throwWithStackTrace(mapFirebaseError(e, stackTrace: s), s),
        );
  }

  @override
  Future<int?> countChunks({ServerCursor? since}) =>
      _call(() async => (await _from(since).count().get()).count);

  @override
  Future<ChunkPage> fetchScope(
    String scope, {
    Object? pageToken,
    int limit = 50,
  }) => _page(
    _ordered(_changes.where(ChunkFields.scope, isEqualTo: scope)),
    pageToken,
    limit,
  );

  @override
  Future<void> deleteChunks(List<String> ids) => _call(() async {
    for (var i = 0; i < ids.length; i += _deleteBatch) {
      final end = i + _deleteBatch < ids.length ? i + _deleteBatch : ids.length;
      final batch = _db.batch();
      for (final id in ids.sublist(i, end)) {
        batch.delete(_changes.doc(id));
      }
      await batch.commit();
    }
  });

  /// createdAt on the first write only (one read to know).
  @override
  Future<void> upsertProfile(UserProfile profile) => _call(() async {
    final existing = await _user.get();
    await _user.set({
      'email': profile.email,
      'displayName': profile.displayName,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'schema': 1,
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });

  /// Writes lastSeenAt = serverTimestamp, reads it back from the server (the clock probe,
  /// 6.2.4); firstSeenAt is set from it once.
  @override
  Future<ServerCursor> upsertDevice(DeviceInfo device) => _call(() async {
    final ref = _user.collection('devices').doc(device.nodeId);
    await ref.set({
      'platform': device.platform.name,
      'appVersion': device.appVersion,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'cursorMicros': device.cursor?.micros,
    }, SetOptions(merge: true));
    final data = (await ref.get(const GetOptions(source: Source.server)))
        .data();
    final seen = data?['lastSeenAt'];
    if (seen is! Timestamp) {
      throw const SyncBackendException(
        SyncErrorCode.dataLoss,
        'device document without lastSeenAt',
      );
    }
    if (data?['firstSeenAt'] == null) {
      await ref.update({'firstSeenAt': seen});
    }
    return ChunkFields.cursorOf(seen);
  });

  /// Missing ids are left out; [_getConcurrency] reads at a time.
  @override
  Future<List<RemoteChunk>> getChunks(List<String> ids) => _call(() async {
    final out = <RemoteChunk>[];
    for (var i = 0; i < ids.length; i += _getConcurrency) {
      final end = i + _getConcurrency < ids.length
          ? i + _getConcurrency
          : ids.length;
      final docs = await Future.wait([
        for (final id in ids.sublist(i, end)) _changes.doc(id).get(),
      ]);
      out.addAll(_chunksOf(docs.where((d) => d.exists)));
    }
    return out;
  });

  /// Later calls fail with cancelled; open watch streams end when their listener cancels.
  @override
  Future<void> close() async => _closed = true;
}
