// lib/src/storage/v1_copy/v1_copy.dart (internal) — the v1 database copy made right before
// the v1 → v2 upgrade (m5-7/02-core 6.12.4, contract 7.2.7 C22-01·C22-02).
//
// * Native file database: VACUUM INTO '<path>-v1-backup.tmp' → rename '<path>-v1-backup'
//   (v1_copy_file_native.dart) — a v1 SQLite file that opens as it is.
// * Web: the canonical dump (db/canonical_dump.dart) in the blob store under
//   'db/v1-backup/<6 digits>' (≤ 4 MiB chunks), then LAST 'db/v1-backup/meta' — the copy is
//   complete only when meta is there. A VACUUM INTO copy inside the web VFS could never be
//   deleted and would be read into memory on every open (6.12.4).
// * New and in-memory databases get no copy.
//
// kv 'db.v1Copy' (KvKeys.v1Copy) records it: {createdAt, method, bytes, normalOpens} or,
// when the copy failed, {failed, at, method, normalOpens}. A failure never stops the upgrade.
// Lifetime: every open that ends without error adds one normal open; the first open with
// normalOpens ≥ 5 AND 7 days after the copy deletes it and the record (a failure record the
// same way). deleteLocalNoteData deletes the copy too; backups never hold it.
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../assets/blob_store.dart';
import '../../repo/status.dart';
import '../db/canonical_dump.dart';
import '../db/note_database.dart';
import '../kv_keys.dart';
import 'v1_copy_file.dart';

/// How the copy is stored (kv 'method').
enum V1CopyMethod { vacuum, dump }

/// Blob store key prefix of the web copy (6.11 blob prefixes).
const String kV1CopyBlobPrefix = 'db/v1-backup/';

/// The meta key of the web copy, written last.
const String kV1CopyMetaKey = '${kV1CopyBlobPrefix}meta';

/// Chunk size of the copy (both forms) — readV1DatabaseCopy hands out chunks of this size.
const int kV1CopyChunkBytes = 4 * 1024 * 1024;

/// Lifetime: normal opens and age before the automatic deletion (C22-02).
const int kV1CopyLifetimeOpens = 5;
const Duration kV1CopyLifetimeAge = Duration(days: 7);

/// The download name of a copy (dev_tools V1DatabaseCopyInfo.fileName).
String v1CopyFileName(V1CopyMethod method) => switch (method) {
  V1CopyMethod.vacuum => 'noteapp-v1-backup.sqlite',
  V1CopyMethod.dump => 'noteapp-v1-backup.sql.txt',
};

/// The blob key of chunk [index] of the web copy.
String v1CopyChunkKey(int index) =>
    '$kV1CopyBlobPrefix${index.toString().padLeft(6, '0')}';

/// The kv record of the copy.
final class V1CopyRecord {
  const V1CopyRecord({
    required this.method,
    required this.createdAt,
    required this.bytes,
    required this.normalOpens,
    this.failure,
  });

  final V1CopyMethod method;

  /// When the copy was made (for a failure: when it failed — kv 'at').
  final int createdAt;
  final int bytes;
  final int normalOpens;

  /// 'quota' | 'io' | 'other' when the copy could not be made.
  final String? failure;

  bool get isFailure => failure != null;

  V1CopyRecord withNormalOpens(int n) => V1CopyRecord(
    method: method,
    createdAt: createdAt,
    bytes: bytes,
    normalOpens: n,
    failure: failure,
  );

  String encode() => jsonEncode(
    failure == null
        ? {
            'createdAt': createdAt,
            'method': method.name,
            'bytes': bytes,
            'normalOpens': normalOpens,
          }
        : {
            'failed': failure,
            'at': createdAt,
            'method': method.name,
            'normalOpens': normalOpens,
          },
  );

  /// null when [text] is not a record of this form (it is then ignored and replaced).
  static V1CopyRecord? tryParse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map<String, Object?>) return null;
      final method = V1CopyMethod.values.asNameMap()[j['method']];
      final opens = j['normalOpens'];
      if (method == null || opens is! int) return null;
      final failed = j['failed'];
      if (failed is String) {
        final at = j['at'];
        if (at is! int) return null;
        return V1CopyRecord(
          method: method,
          createdAt: at,
          bytes: 0,
          normalOpens: opens,
          failure: failed,
        );
      }
      final createdAt = j['createdAt'];
      final bytes = j['bytes'];
      if (createdAt is! int || bytes is! int) return null;
      return V1CopyRecord(
        method: method,
        createdAt: createdAt,
        bytes: bytes,
        normalOpens: opens,
      );
    } on FormatException {
      return null;
    }
  }
}

/// The copy failure class of [error] (6.12.4: 'quota' | 'io' | 'other'). Errors that came
/// through a background isolate or the web worker are only text (1st-round T6), so this
/// reads the text.
String classifyV1CopyFailure(Object error) {
  final t = error.toString();
  final lower = t.toLowerCase();
  if (t.contains('SQLITE_FULL') ||
      lower.contains('database or disk is full') ||
      lower.contains('quotaexceeded') ||
      lower.contains('quota exceeded') ||
      lower.contains('no space left')) {
    return 'quota';
  }
  if (t.contains('SQLITE_IOERR') ||
      t.contains('SQLITE_CANTOPEN') ||
      t.contains('SQLITE_READONLY') ||
      lower.contains('disk i/o error') ||
      lower.contains('unable to open') ||
      lower.contains('readonly database') ||
      t.contains('FileSystemException') ||
      t.contains('PathNotFoundException') ||
      t.contains('PathAccessException')) {
    return 'io';
  }
  return 'other';
}

/// Where one store keeps its copy: the file next to [databasePath] (vacuum) or the blob
/// store [blobs] (dump).
final class V1CopyTarget {
  const V1CopyTarget.file(String this.databasePath)
    : method = V1CopyMethod.vacuum,
      blobs = null;
  const V1CopyTarget.blobs(BlobStore this.blobs)
    : method = V1CopyMethod.dump,
      databasePath = null;

  final V1CopyMethod method;
  final String? databasePath;
  final BlobStore? blobs;

  /// The target of a store: native file databases copy to a file, web databases (but the
  /// in-memory one) to the blob store; in-memory stores have none. [method] forces one
  /// (tests: the web form on the VM); null when it cannot be used here.
  static V1CopyTarget? of({
    required StorageBackend backend,
    required bool inMemory,
    required String? databasePath,
    required BlobStore blobs,
    V1CopyMethod? method,
  }) {
    if (inMemory) return null;
    final chosen =
        method ??
        switch (backend) {
          StorageBackend.nativeFile => V1CopyMethod.vacuum,
          StorageBackend.nativeMemory || StorageBackend.webInMemory => null,
          StorageBackend.webOpfsShared ||
          StorageBackend.webOpfsLocks ||
          StorageBackend.webSharedIndexedDb ||
          StorageBackend.webUnsafeIndexedDb => V1CopyMethod.dump,
        };
    return switch (chosen) {
      null => null,
      V1CopyMethod.vacuum =>
        databasePath == null ? null : V1CopyTarget.file(databasePath),
      V1CopyMethod.dump => V1CopyTarget.blobs(blobs),
    };
  }

  /// Makes the copy of [db] (a v1 database, outside a transaction); returns its bytes.
  /// [createdAt] goes into the web copy's meta.
  Future<int> make(GeneratedDatabase db, int createdAt) async {
    final path = databasePath;
    if (path != null) return makeV1CopyFile(db, path);
    final store = blobs!;
    // A copy cut before its meta is incomplete: start over (6.12.4 web test).
    await store.deletePrefix(kV1CopyBlobPrefix);
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var bytes = 0;
    var index = 0;
    await for (final chunk in canonicalDumpChunks(
      (sql, args) => _textColumn(db, sql, args),
      chunkBytes: kV1CopyChunkBytes,
    )) {
      // A copy, not a view: IndexedDB clones a typed array with its whole buffer.
      await store.put(v1CopyChunkKey(index++), Uint8List.fromList(chunk));
      hasher.add(chunk);
      bytes += chunk.length;
    }
    hasher.close();
    // Last: from here on the copy is complete.
    await store.put(
      kV1CopyMetaKey,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'createdAt': createdAt,
            'bytes': bytes,
            'chunkCount': index,
            'sha256': digest.value.toString(),
            'format': kCanonicalDumpHeader,
          }),
        ),
      ),
    );
    return bytes;
  }

  /// Whether the copy's bytes are there (web: its meta).
  Future<bool> exists() async {
    final path = databasePath;
    if (path != null) return v1CopyFileExists(path);
    return (await blobs!.get(kV1CopyMetaKey)) != null;
  }

  /// The copy in chunks of [kV1CopyChunkBytes]; StateError when it is not there.
  Stream<Uint8List> read() async* {
    final path = databasePath;
    if (path != null) {
      if (!v1CopyFileExists(path)) {
        throw StateError('The v1 database copy file is missing');
      }
      yield* readV1CopyFile(path, kV1CopyChunkBytes);
      return;
    }
    final store = blobs!;
    final metaBytes = await store.get(kV1CopyMetaKey);
    if (metaBytes == null) throw StateError('The v1 database copy is missing');
    final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, Object?>;
    final count = meta['chunkCount']! as int;
    for (var i = 0; i < count; i++) {
      final chunk = await store.get(v1CopyChunkKey(i));
      if (chunk == null) {
        throw StateError('Chunk $i of the v1 database copy is missing');
      }
      yield chunk;
    }
  }

  /// Deletes the copy's bytes (no-op when none).
  Future<void> delete() async {
    final path = databasePath;
    if (path != null) return deleteV1CopyFiles(path);
    await blobs!.deletePrefix(kV1CopyBlobPrefix);
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<List<String>> _textColumn(
  GeneratedDatabase db,
  String sql,
  List<Object?> args,
) async {
  final rows = await db
      .customSelect(sql, variables: [for (final a in args) _variable(a)])
      .get();
  return [for (final r in rows) r.data.values.first! as String];
}

Variable<Object> _variable(Object? value) => switch (value) {
  final String s => Variable<String>(s),
  final int i => Variable<int>(i),
  _ => throw ArgumentError.value(value, 'value', 'unsupported dump argument'),
};

/// The step-0 maker of [target] (NoteDatabase.v1Copy): makes the copy and returns its kv
/// record; on failure deletes what was written and returns a failure record.
V1CopyMaker v1CopyMakerOf(V1CopyTarget target, Clock clock) => (db) async {
  try {
    final now = clock.now().millisecondsSinceEpoch;
    final bytes = await target.make(db, now);
    return V1CopyRecord(
      method: target.method,
      createdAt: now,
      bytes: bytes,
      normalOpens: 0,
    ).encode();
  } on Object catch (e) {
    try {
      await target.delete();
    } on Object {
      // Best effort: an incomplete web copy has no meta and is replaced next time.
    }
    return V1CopyRecord(
      method: target.method,
      createdAt: clock.now().millisecondsSinceEpoch,
      bytes: 0,
      normalOpens: 0,
      failure: classifyV1CopyFailure(e),
    ).encode();
  }
};

/// The copy of one open store (dev_tools.dart and the open bookkeeping).
final class V1Copies {
  V1Copies(this._db, this._target, this._clock);

  final NoteDatabase _db;
  final V1CopyTarget? _target;
  final Clock _clock;

  Future<V1CopyRecord?> record() async {
    final row = await (_db.select(
      _db.kv,
    )..where((t) => t.key.equals(KvKeys.v1Copy))).getSingleOrNull();
    return row == null ? null : V1CopyRecord.tryParse(row.value);
  }

  /// One open ended without error: counts it, and deletes the copy at the end of its life.
  /// Never throws (bookkeeping must not fail an open).
  Future<void> countNormalOpen() async {
    try {
      final r = await record();
      if (r == null) return;
      final opens = r.normalOpens + 1;
      final age = _clock.now().millisecondsSinceEpoch - r.createdAt;
      if (opens >= kV1CopyLifetimeOpens &&
          age >= kV1CopyLifetimeAge.inMilliseconds) {
        await delete();
        return;
      }
      await _putRecord(r.withNormalOpens(opens));
    } on Object {
      // The next open tries again.
    }
  }

  /// The copy's bytes; StateError when there is no copy (none, or only a failure record).
  Stream<Uint8List> read() async* {
    final r = await record();
    final target = _target;
    if (r == null || r.isFailure || target == null) {
      throw StateError('This store has no v1 database copy');
    }
    yield* target.read();
  }

  /// Deletes the copy and its record; no-op when there is none.
  Future<void> delete() async {
    await _target?.delete();
    await _db.transaction(() async {
      await (_db.delete(
        _db.kv,
      )..where((t) => t.key.equals(KvKeys.v1Copy))).go();
    });
  }

  Future<void> _putRecord(V1CopyRecord r) => _db
      .into(_db.kv)
      .insertOnConflictUpdate(
        KvCompanion.insert(key: KvKeys.v1Copy, value: r.encode()),
      );
}
