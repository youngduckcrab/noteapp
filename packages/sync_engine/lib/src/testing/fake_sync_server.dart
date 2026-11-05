import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/profile.dart';
import '../backend/remote_chunk.dart';
import '../common/errors.dart';
import '../common/server_cursor.dart';
import '../model/records.dart';
import 'fake_blob_store.dart';
import 'fake_network.dart';
import 'fake_sync_backend.dart';

@immutable
final class StoredChunk {
  const StoredChunk(this.chunk, {required this.visibleAt});
  final RemoteChunk chunk;

  /// >= chunk.serverTime (late visibility).
  final ServerCursor visibleAt;
}

/// In-memory remote store shared by every simulated device (07-sync 4.11).
///
/// Server time is the injected [Clock] in microseconds, made strictly
/// increasing over all writes (a commit at the same virtual instant as the
/// previous write gets the previous time + 1 µs). One commit is atomic: every
/// chunk becomes visible together with the same serverTime, or nothing is
/// stored. Commits through FakeSyncBackend check the rules of 6.14 (chunk
/// fields and id, lost-ack rewrite = identical content, document size);
/// [commitRaw] stores without checks.
///
/// Counters per uid: [writeCount] = chunk documents written (profile and
/// device documents excluded), [readCount] = chunk documents served (fetch,
/// fetchScope, getChunks and every watch batch), [deleteCount] = chunk ids in
/// delete requests.
final class FakeSyncServer {
  FakeSyncServer({required this._clock});

  final Clock _clock;
  final Map<String, _UserData> _users = {};
  int _lastMicros = 0;
  Duration? _nextCommitDelay;

  /// Backend for one device; all calls go through [link] (latency, faults).
  FakeSyncBackend connect({
    required String uid,
    required FakeNetworkLink link,
  }) {
    if (uid.isEmpty) throw ArgumentError.value(uid, 'uid', 'must not be empty');
    return FakeSyncBackend.internal(server: this, uid: uid, link: link);
  }

  List<StoredChunk> chunksOf(String uid) =>
      _sorted(_users[uid]?.entries.values ?? const <_Entry>[])
          .map((e) => e.stored)
          .toList(growable: false);

  FakeBlobStore blobsOf(String uid) => _user(uid).blobs;

  /// uid → data, '$uid/$nodeId' → data.
  Map<String, Map<String, Object?>> profiles = {}, devices = {};

  /// Next commit's chunks become visible this much later than their serverTime.
  void delayVisibilityOfNextCommit(Duration delay) {
    if (delay.isNegative) {
      throw ArgumentError.value(delay, 'delay', 'must not be negative');
    }
    _nextCommitDelay = delay;
  }

  /// Stores chunks as if a device had committed them, bypassing any engine (S14b(b):
  /// records whose HLC is far ahead of the server time).
  void commitRaw(String uid, List<ChunkWrite> chunks) =>
      _store(_user(uid), chunks);

  int writeCount(String uid) => _users[uid]?.writes ?? 0;
  int readCount(String uid) => _users[uid]?.reads ?? 0;
  int deleteCount(String uid) => _users[uid]?.deletes ?? 0;

  /// Decodes every chunk of [uid] and merges with FieldMerge (purges applied).
  Map<EntityRef, UpsertRecord> mergedState(String uid) =>
      throw UnimplementedError('SYNC T4');

  // ---------------------------------------------------------------------------
  // Server side of FakeSyncBackend (no latency, no faults: the backend adds
  // them). Every method throws SyncBackendException like the real server.

  /// Current server time without advancing it.
  @internal
  ServerCursor get now {
    final micros = _clock.now().toUtc().microsecondsSinceEpoch;
    return ServerCursor(micros > _lastMicros ? micros : _lastMicros);
  }

  @internal
  void serveCommit(String uid, List<ChunkWrite> chunks) {
    if (chunks.length > _maxBatchWrites) {
      throw const SyncBackendException(
        SyncErrorCode.invalidArgument,
        'a batch holds at most 500 writes',
      );
    }
    final user = _user(uid);
    final staged = <String, ChunkWrite>{};
    for (final chunk in chunks) {
      final error = _ruleError(chunk, staged[chunk.id], user.entries[chunk.id]);
      if (error != null) throw error;
      staged[chunk.id] = chunk;
    }
    _store(user, chunks);
  }

  @internal
  ChunkPage serveFetch(
    String uid, {
    ServerCursor? since,
    Object? pageToken,
    required int limit,
  }) => _page(
    uid,
    (e) => since == null || e.stored.chunk.serverTime >= since,
    pageToken,
    limit,
  );

  @internal
  ChunkPage serveScope(
    String uid,
    String scope, {
    Object? pageToken,
    required int limit,
  }) => _page(uid, (e) => e.stored.chunk.scope == scope, pageToken, limit);

  @internal
  int serveCount(String uid, {ServerCursor? since}) =>
      (_users[uid]?.entries.values ?? const <_Entry>[])
          .where(
            (e) =>
                e.visible &&
                (since == null || e.stored.chunk.serverTime >= since),
          )
          .length;

  @internal
  List<RemoteChunk> serveGetChunks(String uid, List<String> ids) {
    final user = _user(uid);
    final found = <RemoteChunk>[];
    for (final id in LinkedHashSet<String>.of(ids)) {
      final entry = user.entries[id];
      if (entry != null) found.add(entry.stored.chunk);
    }
    user.reads += found.length;
    return found;
  }

  @internal
  void serveDelete(String uid, List<String> ids) {
    final user = _user(uid);
    final unique = LinkedHashSet<String>.of(ids);
    user.deletes += unique.length;
    unique.forEach(user.entries.remove);
  }

  @internal
  void serveProfile(String uid, UserProfile profile) {
    if (profile.uid != uid) {
      throw const SyncBackendException(
        SyncErrorCode.permissionDenied,
        'profile of another user',
      );
    }
    final time = _tick();
    final old = profiles[uid];
    profiles[uid] = {
      'email': profile.email,
      'displayName': profile.displayName,
      'createdAt': old?['createdAt'] ?? time,
      'lastSeenAt': time,
      'schema': 1,
    };
  }

  @internal
  ServerCursor serveDevice(String uid, DeviceInfo device) {
    if (!_nodeIdPattern.hasMatch(device.nodeId)) {
      throw SyncBackendException(
        SyncErrorCode.permissionDenied,
        'device id must be 16 lowercase hex digits: ${device.nodeId}',
      );
    }
    final time = _tick();
    final key = '$uid/${device.nodeId}';
    final old = devices[key];
    devices[key] = {
      'platform': device.platform.name,
      'appVersion': device.appVersion,
      'firstSeenAt': old?['firstSeenAt'] ?? time,
      'lastSeenAt': time,
      'cursorMicros': device.cursor?.micros,
    };
    return time;
  }

  /// Registers a live query of `serverTime >= since` and returns its initial
  /// result. [onBatch] receives later added or modified chunks of [uid]
  /// (never removals) until the returned cancel function is called.
  @internal
  (List<RemoteChunk>, void Function()) serveWatch(
    String uid, {
    ServerCursor? since,
    required void Function(List<RemoteChunk> batch) onBatch,
  }) {
    final user = _user(uid);
    final watch = _Watch(since, onBatch);
    final initial = _sorted(
      user.entries.values.where((e) => e.visible && watch.matches(e)),
    ).map((e) => e.stored.chunk).toList(growable: false);
    user.reads += initial.length;
    user.watches.add(watch);
    return (initial, () => user.watches.remove(watch));
  }

  // ---------------------------------------------------------------------------

  static const int _maxBatchWrites = 500;
  static const int _maxPayloadBytes = 1000000;
  static const int _maxDocumentBytes = 1048576;
  static final RegExp _nodeIdPattern = RegExp(r'^[0-9a-f]{16}$');
  static final RegExp _chunkIdPattern = RegExp(r'^[0-9a-f]{16}-[0-9a-f]{24}$');

  _UserData _user(String uid) => _users.putIfAbsent(
    uid,
    () => _UserData(FakeBlobStore.internal(uid: uid)),
  );

  ServerCursor _tick() {
    final micros = _clock.now().toUtc().microsecondsSinceEpoch;
    _lastMicros = micros > _lastMicros ? micros : _lastMicros + 1;
    return ServerCursor(_lastMicros);
  }

  void _store(_UserData user, List<ChunkWrite> chunks) {
    final serverTime = _tick();
    final delay = _nextCommitDelay;
    _nextCommitDelay = null;
    final visibleNow = delay == null || delay == Duration.zero;
    final visibleAt = visibleNow ? serverTime : serverTime.plus(delay);
    final entries = <_Entry>[];
    for (final chunk in chunks) {
      final entry = _Entry(
        StoredChunk(
          RemoteChunk(
            id: chunk.id,
            scope: chunk.scope,
            authorNodeId: chunk.authorNodeId,
            recordCount: chunk.recordCount,
            format: chunk.format,
            kind: chunk.kind,
            maxHlc: chunk.maxHlc,
            payload: Uint8List.fromList(chunk.payload),
            serverTime: serverTime,
          ),
          visibleAt: visibleAt,
        ),
        visible: visibleNow,
      );
      user.entries[chunk.id] = entry;
      entries.add(entry);
    }
    user.writes += chunks.length;
    if (visibleNow) {
      _notify(user, entries);
    } else {
      Timer(delay, () {
        final current = [
          for (final e in entries)
            if (identical(user.entries[e.stored.chunk.id], e)) e,
        ];
        for (final e in current) {
          e.visible = true;
        }
        _notify(user, current);
      });
    }
  }

  void _notify(_UserData user, List<_Entry> entries) {
    if (entries.isEmpty) return;
    for (final watch in List.of(user.watches)) {
      if (!user.watches.contains(watch)) continue;
      final batch = _sorted(entries.where(watch.matches))
          .map((e) => e.stored.chunk)
          .toList(growable: false);
      if (batch.isEmpty) continue;
      user.reads += batch.length;
      watch.onBatch(batch);
    }
  }

  ChunkPage _page(
    String uid,
    bool Function(_Entry entry) where,
    Object? pageToken,
    int limit,
  ) {
    if (limit < 1) {
      throw SyncBackendException(
        SyncErrorCode.invalidArgument,
        'limit must be positive: $limit',
      );
    }
    if (pageToken != null && pageToken is! _PageToken) {
      throw const SyncBackendException(
        SyncErrorCode.invalidArgument,
        'unknown page token',
      );
    }
    final after = pageToken as _PageToken?;
    final user = _user(uid);
    final matching = _sorted(
      user.entries.values.where(
        (e) =>
            e.visible &&
            where(e) &&
            (after == null || after.isBefore(e.stored.chunk)),
      ),
    );
    final page = matching
        .take(limit)
        .map((e) => e.stored.chunk)
        .toList(growable: false);
    user.reads += page.length;
    // Like the Firestore adapter: a full page always has a next token (the
    // next page may be empty).
    return ChunkPage(
      page,
      nextPageToken: page.length == limit
          ? _PageToken(page.last.serverTime.micros, page.last.id)
          : null,
    );
  }

  static List<_Entry> _sorted(Iterable<_Entry> entries) =>
      entries.toList()
        ..sort((a, b) => _compare(a.stored.chunk, b.stored.chunk));

  static int _compare(RemoteChunk a, RemoteChunk b) {
    final bySu = a.serverTime.compareTo(b.serverTime);
    return bySu != 0 ? bySu : a.id.compareTo(b.id);
  }

  static SyncBackendException? _ruleError(
    ChunkWrite chunk,
    ChunkWrite? staged,
    _Entry? stored,
  ) {
    SyncBackendException denied(String why) => SyncBackendException(
      SyncErrorCode.permissionDenied,
      'rules: $why (chunk ${chunk.id})',
    );
    if (_documentBytes(chunk) > _maxDocumentBytes) {
      return SyncBackendException(
        SyncErrorCode.invalidArgument,
        'document larger than 1 MiB (chunk ${chunk.id})',
      );
    }
    if (chunk.format < 1 || chunk.format > 16) return denied('fmt');
    if (chunk.scope.isEmpty || chunk.scope.length > 64) return denied('scope');
    if (!_nodeIdPattern.hasMatch(chunk.authorNodeId)) return denied('by');
    if (chunk.recordCount < 1 || chunk.recordCount > 5000) return denied('n');
    if (chunk.payload.length > _maxPayloadBytes) return denied('data size');
    if (chunk.maxHlc.length != 37) return denied('maxHlc');
    if (!_chunkIdPattern.hasMatch(chunk.id) ||
        chunk.id.substring(0, 16) != chunk.authorNodeId) {
      return denied('chunk id');
    }
    final previous = staged ?? stored?.stored.chunk;
    if (previous != null && !_sameContent(chunk, previous)) {
      return denied('rewrite may change only su');
    }
    return null;
  }

  static bool _sameContent(ChunkWrite a, Object b) => switch (b) {
    ChunkWrite() =>
      a.scope == b.scope &&
          a.authorNodeId == b.authorNodeId &&
          a.recordCount == b.recordCount &&
          a.format == b.format &&
          a.kind == b.kind &&
          a.maxHlc == b.maxHlc &&
          _bytesEqual(a.payload, b.payload),
    RemoteChunk() =>
      a.scope == b.scope &&
          a.authorNodeId == b.authorNodeId &&
          a.recordCount == b.recordCount &&
          a.format == b.format &&
          a.kind == b.kind &&
          a.maxHlc == b.maxHlc &&
          _bytesEqual(a.payload, b.payload),
    _ => false,
  };

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Firestore document size (6.4.2): name ~90 B + field names and values +
  /// 32 B.
  static int _documentBytes(ChunkWrite c) =>
      90 +
      32 +
      (4 + 8) + // fmt
      (6 + c.scope.length + 1) + // scope
      (3 + c.authorNodeId.length + 1) + // by
      (2 + 8) + // n
      (6 + 8) + // bytes
      (7 + c.maxHlc.length + 1) + // maxHlc
      (5 + c.kind.name.length + 1) + // kind
      (5 + c.payload.length) + // data
      (3 + 8); // su
}

final class _UserData {
  _UserData(this.blobs);
  final FakeBlobStore blobs;
  final Map<String, _Entry> entries = {};
  final List<_Watch> watches = [];
  int writes = 0, reads = 0, deletes = 0;
}

final class _Entry {
  _Entry(this.stored, {required this.visible});
  final StoredChunk stored;
  bool visible;
}

final class _Watch {
  _Watch(this.since, this.onBatch);
  final ServerCursor? since;
  final void Function(List<RemoteChunk> batch) onBatch;

  bool matches(_Entry e) =>
      since == null || e.stored.chunk.serverTime >= since!;
}

/// startAfter(serverTime, id) of the last chunk of the previous page.
final class _PageToken {
  const _PageToken(this.micros, this.id);
  final int micros;
  final String id;

  bool isBefore(RemoteChunk c) =>
      micros < c.serverTime.micros ||
      (micros == c.serverTime.micros && id.compareTo(c.id) < 0);
}

extension on ServerCursor {
  ServerCursor plus(Duration d) => ServerCursor(micros + d.inMicroseconds);
}
