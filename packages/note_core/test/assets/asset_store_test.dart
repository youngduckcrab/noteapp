// CORE T13 — AssetStoreImpl (6.13, contract 7.2.11 v1.3): SHA-256 ids, dedupe, 4 MiB
// chunks, hash mismatch, listAssets filters, bytesArrived, markUploaded outbox and
// ChangeBatch, and the write-Future rule around the blob store and the write queue.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/blob_store.dart';
import 'package:note_core/src/assets/idb_blob_store.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

const _mib = 1024 * 1024;

Uint8List _bytes(int length, [int seed = 0]) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (i * 7 + seed) % 256]);

String _sha(Uint8List b) => sha256.convert(b).toString();

/// A chunk store that throws on the [failAt]-th put (1-based); counts puts.
final class _FailingBlobStore implements BlobStore {
  _FailingBlobStore(this.inner, {required this.failAt});
  final BlobStore inner;
  final int failAt;
  int puts = 0;

  @override
  Future<void> put(String key, Uint8List bytes) async {
    puts++;
    if (puts == failAt) throw StateError('injected blob write failure');
    await inner.put(key, bytes);
  }

  @override
  Future<Uint8List?> get(String key) => inner.get(key);
  @override
  Future<void> delete(String key) => inner.delete(key);
  @override
  Future<void> deletePrefix(String prefix) => inner.deletePrefix(prefix);
  @override
  Future<List<String>> keys(String prefix) => inner.keys(prefix);
}

/// A remote asset's metadata only (the internal remote write path, 6.10.3).
Future<void> _putRemoteMeta(DriftNoteStore store, Asset asset) =>
    store.queue.run((tx) async {
      await tx.putRemote(
        asset,
        EntityFieldVersions(Hlc(1793750400000, 0, 'ffffffffffffffff')),
      );
    }, origin: ChangeOrigin.remote);

Asset _remoteAsset(Uint8List bytes, {String? storagePath = 'u/x.pdf'}) =>
    Asset.fromJson({
      'id': _sha(bytes),
      'ownerId': kLocalOwnerId,
      'type': 'pdf',
      'mimeType': 'application/pdf',
      'size': bytes.length,
      'fileName': 'r.pdf',
      'storagePath': storagePath,
      'createdAt': 5,
      'deletedAt': null,
      'version': Hlc(1793750400000, 0, 'ffffffffffffffff').toString(),
    });

/// The value of [f] after the microtasks of [async] ran (fake_async tests).
T? settled<T>(Future<T> f, FakeAsync async) {
  T? value;
  f.then((v) => value = v);
  async.flushMicrotasks();
  return value;
}

void main() {
  late DriftNoteStore store;
  late AssetStore assets;
  late List<AssetId> arrived;
  late List<ChangeBatch> batches;
  setUp(() async {
    store = await openStore();
    assets = store.assets;
    arrived = [];
    batches = [];
    assets.bytesArrived.listen(arrived.add);
    store.changes.listen(batches.add);
  });
  tearDown(() => store.close());

  Future<List<OutboxEntry>> outbox() => readOutbox(store.db);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<Asset> putPdf(Uint8List bytes, {String? fileName = 'a.pdf'}) =>
      assets.put(
        bytes,
        type: AssetType.pdf,
        mimeType: 'application/pdf',
        fileName: fileName,
      );

  test('put: id = SHA-256 hex, metadata row, outbox *, ChangeBatch, '
      'bytesArrived after the commit', () async {
    final bytes = _bytes(1000);
    final a = await putPdf(bytes);
    expect(a.id, _sha(bytes));
    expect(a.id, hasLength(64));
    expect(a.ownerId, kLocalOwnerId);
    expect(a.type, AssetType.pdf);
    expect(a.mimeType, 'application/pdf');
    expect(a.size, 1000);
    expect(a.fileName, 'a.pdf');
    expect(a.hasLocalBytes, isTrue);
    expect(a.storagePath, isNull);
    expect(a.version, isNotNull);
    expect(await assets.getAsset(a.id), a);
    expect(await assets.hasBytes(a.id), isTrue);
    expect(await assets.readBytes(a.id), bytes);
    final entries = await outbox();
    expect(entries, hasLength(1));
    expect(entries.single.kind, EntityKind.asset);
    expect(entries.single.entityId, a.id);
    expect(entries.single.changedFields, {kAllFields});
    await settle();
    expect(arrived, [a.id]);
    expect(batches, hasLength(1));
    expect(batches.single.origin, ChangeOrigin.local);
    expect(batches.single.changes.single.kind, EntityKind.asset);
    expect(batches.single.changes.single.id, a.id);
  });

  test('same bytes are stored once: the second put returns the same asset, '
      'no commit, no bytesArrived', () async {
    final bytes = _bytes(2000);
    final first = await putPdf(bytes);
    await settle();
    final commits = store.queue.debugTransactionCount;
    final second = await putPdf(Uint8List.fromList(bytes), fileName: 'b.pdf');
    await settle();
    expect(second, first);
    expect(second.fileName, 'a.pdf');
    expect(store.queue.debugTransactionCount, commits);
    expect(arrived, [first.id]);
    expect(await outbox(), hasLength(1));
    expect(await assets.listAssets(), [first]);
  });

  test('concurrent puts of the same bytes share one write', () async {
    final bytes = _bytes(3000);
    final results = await Future.wait([putPdf(bytes), putPdf(bytes)]);
    await settle();
    expect(results[0], results[1]);
    expect(arrived, [results[0].id]);
    expect(await outbox(), hasLength(1));
  });

  test('9 MiB: 3 chunks of 4 MiB, read back byte for byte', () async {
    final bytes = _bytes(9 * _mib, 3);
    final a = await putPdf(bytes);
    expect(a.size, 9 * _mib);
    final keys = await store.blobs.chunks.keys(chunkPrefix(a.id));
    expect(keys, [chunkKey(a.id, 0), chunkKey(a.id, 1), chunkKey(a.id, 2)]);
    final row = await (store.db.select(
      store.db.assets,
    )..where((t) => t.id.equals(a.id))).getSingle();
    expect(row.chunkCount, 3);
    expect(await assets.readBytes(a.id), bytes);
  });

  test('empty bytes are an asset with no chunk', () async {
    final a = await putPdf(Uint8List(0));
    expect(a.size, 0);
    expect(await assets.hasBytes(a.id), isTrue);
    expect(await assets.readBytes(a.id), Uint8List(0));
  });

  test('unknown id: getAsset / readBytes null, hasBytes false', () async {
    final id = 'f' * 64;
    expect(await assets.getAsset(id), isNull);
    expect(await assets.readBytes(id), isNull);
    expect(await assets.hasBytes(id), isFalse);
  });

  test('Asset.fromJson has hasLocalBytes == false', () {
    expect(_remoteAsset(_bytes(10)).hasLocalBytes, isFalse);
  });

  group('metadata-only (remote) assets', () {
    test(
      'listed with hasLocalBytes: false, no bytes until they arrive',
      () async {
        final bytes = _bytes(5000, 9);
        await _putRemoteMeta(store, _remoteAsset(bytes));
        final a = (await assets.getAsset(_sha(bytes)))!;
        expect(a.hasLocalBytes, isFalse);
        expect(await assets.listAssets(hasLocalBytes: false), [a]);
        expect(await assets.listAssets(hasLocalBytes: true), isEmpty);
        expect(await assets.readBytes(a.id), isNull);
        expect(await assets.hasBytes(a.id), isFalse);
      },
    );

    test('putDownloadedBytes: hasLocalBytes true (local column, no outbox, no '
        'ChangeBatch), bytes readable, then bytesArrived', () async {
      final bytes = _bytes(5 * _mib, 4);
      await _putRemoteMeta(store, _remoteAsset(bytes));
      await settle();
      batches.clear();
      final id = _sha(bytes);
      final before = (await assets.getAsset(id))!;
      await assets.putDownloadedBytes(id, bytes);
      final after = (await assets.getAsset(id))!;
      expect(after, before.copyWith(hasLocalBytes: true));
      expect(after.version, before.version);
      expect(await assets.readBytes(id), bytes);
      expect(await assets.hasBytes(id), isTrue);
      expect(await assets.listAssets(hasLocalBytes: false), isEmpty);
      expect(await outbox(), isEmpty);
      await settle();
      expect(arrived, [id]);
      expect(batches, isEmpty);
    });

    test(
      'putDownloadedBytes with bytes of another hash: '
      'AssetHashMismatchException, nothing stored, no bytesArrived',
      () async {
        final bytes = _bytes(100);
        await _putRemoteMeta(store, _remoteAsset(bytes));
        final id = _sha(bytes);
        final commits = store.queue.debugTransactionCount;
        await expectLater(
          assets.putDownloadedBytes(id, _bytes(100, 1)),
          throwsA(isA<AssetHashMismatchException>()),
        );
        await settle();
        expect(store.queue.debugTransactionCount, commits);
        expect(await store.blobs.chunks.keys(chunkPrefix(id)), isEmpty);
        expect((await assets.getAsset(id))!.hasLocalBytes, isFalse);
        expect(arrived, isEmpty);
      },
    );

    test('put of the same bytes completes a metadata-only row: hasLocalBytes, '
        'no outbox, bytesArrived', () async {
      final bytes = _bytes(700, 2);
      await _putRemoteMeta(store, _remoteAsset(bytes));
      final remote = (await assets.getAsset(_sha(bytes)))!;
      final a = await putPdf(bytes, fileName: 'mine.pdf');
      expect(a, remote.copyWith(hasLocalBytes: true));
      expect(a.fileName, 'r.pdf');
      expect(await assets.readBytes(a.id), bytes);
      expect(await outbox(), isEmpty);
      await settle();
      expect(arrived, [a.id]);
    });

    test(
      'putDownloadedBytes before the metadata: bytes kept, bytesArrived',
      () async {
        final bytes = _bytes(300, 5);
        final id = _sha(bytes);
        await assets.putDownloadedBytes(id, bytes);
        await settle();
        expect(arrived, [id]);
        expect(await assets.getAsset(id), isNull);
        expect(await hasAllChunks(store.blobs.chunks, id, 1), isTrue);
        expect(await store.assets.localStateOf(id, bytes.length), (
          hasLocalBytes: true,
          chunkCount: 1,
        ));
      },
    );
  });

  test('listAssets filters: hasLocalBytes, uploaded, owner, deleted', () async {
    final local = await putPdf(_bytes(10, 1));
    final uploadedBytes = _bytes(10, 2);
    final uploaded = await putPdf(uploadedBytes);
    await assets.markUploaded(uploaded.id, 'u/2.pdf');
    final remote = _remoteAsset(_bytes(10, 3), storagePath: 'u/3.pdf');
    await _putRemoteMeta(store, remote);
    final other = _remoteAsset(_bytes(10, 4));
    await _putRemoteMeta(
      store,
      Asset.fromJson({...other.toJson(), 'ownerId': 'someone-else'}),
    );
    final gone = _remoteAsset(_bytes(10, 5));
    await _putRemoteMeta(
      store,
      Asset.fromJson({...gone.toJson(), 'deletedAt': 9}),
    );
    final up = (await assets.getAsset(uploaded.id))!;
    final rem = (await assets.getAsset(remote.id))!;

    Future<Set<AssetId>> ids({bool? hasLocalBytes, bool? uploaded}) async => {
      for (final a in await assets.listAssets(
        hasLocalBytes: hasLocalBytes,
        uploaded: uploaded,
      ))
        a.id,
    };
    expect(await ids(), {local.id, up.id, rem.id});
    expect(await ids(hasLocalBytes: true), {local.id, up.id});
    expect(await ids(hasLocalBytes: false), {rem.id});
    expect(await ids(uploaded: true), {up.id, rem.id});
    expect(await ids(uploaded: false), {local.id});
    expect(await ids(hasLocalBytes: true, uploaded: false), {local.id});
    expect(up.storagePath, 'u/2.pdf');
  });

  group('markUploaded', () {
    test('records {storagePath} in the outbox and publishes '
        'ChangeBatch(origin: local); no bytesArrived', () async {
      final a = await putPdf(_bytes(64));
      await store.db.delete(store.db.outbox).go(); // acknowledged upload of '*'
      await settle();
      batches.clear();
      arrived.clear();
      await assets.markUploaded(a.id, 'users/local/assets/${a.id}');
      final after = (await assets.getAsset(a.id))!;
      expect(after.storagePath, 'users/local/assets/${a.id}');
      expect(after.hasLocalBytes, isTrue);
      expect(after.version!.compareTo(a.version!), greaterThan(0));
      final entry = (await outbox()).single;
      expect(entry.kind, EntityKind.asset);
      expect(entry.entityId, a.id);
      expect(entry.op, OutboxOp.upsert);
      expect(entry.changedFields, {'storagePath'});
      await settle();
      expect(batches, hasLength(1));
      expect(batches.single.origin, ChangeOrigin.local);
      expect(batches.single.changes.single.id, a.id);
      expect(arrived, isEmpty);
    });

    test(
      'an unknown asset: EntityNotFoundException, nothing written',
      () async {
        await expectLater(
          assets.markUploaded('e' * 64, 'p'),
          throwsA(isA<EntityNotFoundException>()),
        );
        expect(await outbox(), isEmpty);
      },
    );
  });

  test('usage: active assets, local bytes, thumbnail bytes', () async {
    expect(
      await assets.usage(),
      const AssetStorageUsage(assetCount: 0, totalBytes: 0, thumbnailBytes: 0),
    );
    await putPdf(_bytes(100, 1));
    await putPdf(_bytes(50, 2));
    await _putRemoteMeta(store, _remoteAsset(_bytes(30, 3)));
    await store.thumbnails.write(
      PageThumbnail(
        pageId: 'p1',
        contentRevision: 0,
        width: 1,
        height: 1,
        mimeType: 'image/png',
        bytes: _bytes(12),
      ),
    );
    expect(
      await assets.usage(),
      const AssetStorageUsage(
        assetCount: 3,
        totalBytes: 150,
        thumbnailBytes: 12,
      ),
    );
  });

  test('a reopened file store reads the bytes of its assets', () async {
    final dir = await Directory.systemTemp.createTemp('note_core_assets_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/notes.db';
    final first = await openStore(filePath: path);
    final bytes = _bytes(4 * _mib + 5, 8);
    final a = await first.assets.put(
      bytes,
      type: AssetType.pdf,
      mimeType: 'application/pdf',
    );
    await first.close();
    final again = await openStore(filePath: path);
    expect(await again.assets.hasBytes(a.id), isTrue);
    expect(await again.assets.readBytes(a.id), bytes);
    await again.close();
    // deleteLocalNoteData drops the blobs of that file too.
    await deleteLocalNoteData(NoteStoreConfig(nativeDatabasePath: path));
    final fresh = await openStore(filePath: path);
    addTearDown(fresh.close);
    expect(await fresh.assets.getAsset(a.id), isNull);
    expect(await fresh.blobs.chunks.keys(chunkPrefix(a.id)), isEmpty);
  });

  group('failures (contract 7.2.11 v1.2 / v1.3)', () {
    Future<(DriftNoteStore, _FailingBlobStore)> openFailing(int failAt) async {
      final factory = newIdbFactoryMemory();
      final chunks = _FailingBlobStore(
        IdbBlobDatabase(factory, 'noteapp_blobs').chunks,
        failAt: failAt,
      );
      final s = await DriftNoteStore.open(
        executor: NativeDatabase.memory(),
        storageInfo: const StorageInfo(backend: StorageBackend.nativeMemory),
        config: const NoteStoreConfig(
          inMemory: true,
          seedDefaultPenPresets: false,
        ),
        deviceNodeId: kTestNode,
        blobFactory: factory,
        assetChunks: chunks,
      );
      return (s, chunks);
    }

    test('a failed second chunk write of 9 MiB: put fails with that error at '
        'once (no retry), no metadata, no bytesArrived, outbox unchanged, the '
        'first chunk stays as an orphan', () async {
      final (s, chunks) = await openFailing(2);
      addTearDown(s.close);
      final got = <AssetId>[];
      s.assets.bytesArrived.listen(got.add);
      final bytes = _bytes(9 * _mib, 6);
      final id = _sha(bytes);
      await expectLater(
        s.assets.put(bytes, type: AssetType.pdf, mimeType: 'application/pdf'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'injected blob write failure',
          ),
        ),
      );
      await settle();
      expect(chunks.puts, 2, reason: 'no retry, no third chunk');
      expect(s.queue.debugTransactionCount, 0);
      expect(await s.assets.getAsset(id), isNull);
      expect(await readOutbox(s.db), isEmpty);
      expect(got, isEmpty);
      expect(await chunks.inner.keys(chunkPrefix(id)), [chunkKey(id, 0)]);
      expect(s.persistenceStatus.consecutiveFailures, 0);
    });

    test('a failed chunk write of putDownloadedBytes: that error at once, '
        'metadata unchanged', () async {
      final (s, chunks) = await openFailing(1);
      addTearDown(s.close);
      final bytes = _bytes(1000, 7);
      await _putRemoteMeta(s, _remoteAsset(bytes));
      final before = await s.assets.getAsset(_sha(bytes));
      final commits = s.queue.debugTransactionCount;
      await expectLater(
        s.assets.putDownloadedBytes(_sha(bytes), bytes),
        throwsStateError,
      );
      expect(s.queue.debugTransactionCount, commits);
      expect(await s.assets.getAsset(_sha(bytes)), before);
      expect(chunks.puts, 1);
    });
  });

  /// Advances fake time in 1 ms steps (the in-memory IndexedDB completes on 0.1 ms
  /// timers) until [done] or [maxMs]; returns the elapsed ms.
  int pumpUntil(FakeAsync async, bool Function() done, {int maxMs = 10000}) {
    var ms = 0;
    async.flushMicrotasks();
    while (!done() && ms < maxMs) {
      async.elapse(const Duration(milliseconds: 1));
      ms++;
    }
    expect(done(), isTrue, reason: 'condition not reached in $maxMs ms');
    return ms;
  }

  test('a failed metadata commit: put stays pending while the queue retries, '
      'completes after the successful commit, then bytesArrived', () {
    fakeAsync((async) {
      late DriftNoteStore s;
      openStore().then((v) => s = v);
      async.flushMicrotasks();
      final got = <AssetId>[];
      s.assets.bytesArrived.listen(got.add);
      s.queue.failNextCommits(2);
      Asset? done;
      Object? error;
      s.assets
          .put(_bytes(256), type: AssetType.image, mimeType: 'image/png')
          .then<void>(
            (a) => done = a,
            onError: (Object e) {
              error = e;
            },
          );
      pumpUntil(async, () => s.persistenceStatus.consecutiveFailures == 1);
      expect(done, isNull);
      // First retry after 100 ms fails again.
      final wait1 = pumpUntil(
        async,
        () => s.persistenceStatus.consecutiveFailures == 2,
      );
      expect(wait1, greaterThanOrEqualTo(100));
      expect(done, isNull);
      expect(got, isEmpty);
      expect(settled(s.assets.getAsset(_sha(_bytes(256))), async), isNull);
      // Second retry after 400 ms commits.
      final wait2 = pumpUntil(async, () => done != null || error != null);
      expect(wait2, greaterThanOrEqualTo(400));
      expect(error, isNull);
      expect(done!.id, _sha(_bytes(256)));
      async.flushMicrotasks();
      expect(got, [done!.id]);
      s.close();
      pumpUntil(async, () => async.pendingTimers.isEmpty);
    });
  });

  test(
    'markUploaded under a failing commit stays pending until it commits',
    () {
      fakeAsync((async) {
        late DriftNoteStore s;
        openStore().then((v) => s = v);
        async.flushMicrotasks();
        Asset? a;
        s.assets
            .put(_bytes(10), type: AssetType.image, mimeType: 'image/png')
            .then((v) => a = v);
        pumpUntil(async, () => a != null);
        s.queue.failNextCommits(1);
        var done = false;
        s.assets.markUploaded(a!.id, 'p').then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isFalse);
        expect(s.persistenceStatus.consecutiveFailures, 1);
        final waited = pumpUntil(async, () => done);
        expect(waited, greaterThanOrEqualTo(100));
        s.close();
        pumpUntil(async, () => async.pendingTimers.isEmpty);
      });
    },
  );

  test('after close: put fails with StateError', () async {
    final s = await openStore();
    await s.close();
    await expectLater(
      s.assets.put(_bytes(1), type: AssetType.image, mimeType: 'image/png'),
      throwsStateError,
    );
  });
}
