// T17: FirebaseBlobStore (6.9) on hand-written firebase_storage fakes (firebase_storage_mocks
// does not resolve with firebase_storage 14, 7.2): the path, stat (metadata, missing → null,
// errors mapped), upload (content type + custom metadata the rules check, progress,
// cancel → task cancelled, errors mapped), download (size limit before reading, missing,
// progress, cancel). Then the backend factory of FirebaseSyncBindings on fake_cloud_firestore:
// persistence off once, one Storage, a backend per user.
import 'dart:async';
import 'dart:typed_data';

// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/src/firebase/backend_factory.dart';
import 'package:sync_engine/sync_engine.dart';

const _id = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _path = 'users/u1/assets/$_id';

FirebaseException _storageError(String code) =>
    FirebaseException(plugin: 'firebase_storage', code: code, message: 'm');

final class _Snapshot implements TaskSnapshot {
  _Snapshot(this.bytesTransferred, this.totalBytes);

  @override
  final int bytesTransferred;

  @override
  final int totalBytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Task implements UploadTask {
  final Completer<TaskSnapshot> done = Completer<TaskSnapshot>();
  // ignore: close_sinks — lives as long as the test's task.
  final StreamController<TaskSnapshot> events = StreamController.broadcast();
  int cancels = 0;

  Future<TaskSnapshot> get _future => done.future;

  @override
  Stream<TaskSnapshot> get snapshotEvents => events.stream;

  @override
  Future<bool> cancel() async {
    cancels++;
    if (!done.isCompleted) done.completeError(_storageError('canceled'));
    return true;
  }

  @override
  Future<S> then<S>(
    FutureOr<S> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);

  @override
  Future<TaskSnapshot> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _future.catchError(onError, test: test);

  @override
  Future<TaskSnapshot> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);

  @override
  Future<TaskSnapshot> timeout(
    Duration timeLimit, {
    FutureOr<TaskSnapshot> Function()? onTimeout,
  }) => _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Stream<TaskSnapshot> asStream() => _future.asStream();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Put {
  _Put(this.bytes, this.metadata, this.task);
  final Uint8List bytes;
  final SettableMetadata? metadata;
  final _Task task;
}

final class _Ref implements Reference {
  _Ref(this.storage, this.fullPath);

  @override
  final _Storage storage;

  @override
  final String fullPath;

  @override
  Future<FullMetadata> getMetadata() async {
    final error = storage.metadataError;
    if (error != null) throw error;
    final object = storage.objects[fullPath];
    if (object == null) throw _storageError('object-not-found');
    return FullMetadata({
      'fullPath': fullPath,
      'size': object.length,
      'contentType': 'application/pdf',
      'customMetadata': {'sha256': _id},
    });
  }

  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    final task = _Task();
    storage.puts.add(_Put(data, metadata, task));
    return task;
  }

  @override
  Future<Uint8List?> getData([int maxSize = 10485760]) {
    storage.reads.add(maxSize);
    return storage.read?.future ?? Future.value(storage.objects[fullPath]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Storage implements FirebaseStorage {
  final Map<String, Uint8List> objects = {};
  final List<_Put> puts = [];
  final List<int> reads = [];
  final List<String> refs = [];
  FirebaseException? metadataError;

  /// When set, getData waits for it.
  Completer<Uint8List?>? read;

  @override
  Reference ref([String? path]) {
    refs.add(path!);
    return _Ref(this, path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher _backendError(SyncErrorCode code) =>
    throwsA(isA<SyncBackendException>().having((e) => e.code, 'code', code));

void main() {
  late _Storage storage;
  late FirebaseBlobStore blobs;

  setUp(() {
    storage = _Storage();
    blobs = FirebaseBlobStore(storage: storage, uid: 'u1');
  });

  test('pathFor: users/{uid}/assets/{sha256}', () {
    expect(blobs.pathFor(_id), _path);
  });

  group('stat', () {
    test('metadata → RemoteBlobInfo; missing → null', () async {
      expect(await blobs.stat(_path), isNull);
      storage.objects[_path] = Uint8List(5);
      final info = (await blobs.stat(_path))!;
      expect(info.path, _path);
      expect(info.size, 5);
      expect(info.sha256, _id);
      expect(info.contentType, 'application/pdf');
    });

    test('other errors map with mapFirebaseError', () async {
      storage.metadataError = _storageError('unauthorized');
      await expectLater(
        blobs.stat(_path),
        _backendError(SyncErrorCode.permissionDenied),
      );
      storage.metadataError = _storageError('storage/retry-limit-exceeded');
      await expectLater(
        blobs.stat(_path),
        _backendError(SyncErrorCode.deadlineExceeded),
      );
    });
  });

  group('upload', () {
    test('putData with the content type and custom metadata; progress, then '
        'the full size at the end', () async {
      final bytes = Uint8List.fromList(List.filled(100, 7));
      final progress = <(int, int)>[];
      final upload = blobs.upload(
        _path,
        bytes,
        contentType: 'application/pdf',
        metadata: const {'sha256': _id, 'size': '100', 'type': 'pdf'},
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      await pumpEventQueue();
      final put = storage.puts.single;
      expect(storage.refs, [_path]);
      expect(put.bytes, bytes);
      expect(put.metadata!.contentType, 'application/pdf');
      expect(put.metadata!.customMetadata, {
        'sha256': _id,
        'size': '100',
        'type': 'pdf',
      });
      put.task.events
        ..add(_Snapshot(40, 100))
        ..add(_Snapshot(60, -1));
      await pumpEventQueue();
      put.task.done.complete(_Snapshot(100, 100));
      await upload;
      expect(progress, [(40, 100), (60, 100), (100, 100)]);
    });

    test('task errors map with mapFirebaseError', () async {
      final upload = blobs.upload(
        _path,
        Uint8List(3),
        contentType: 'image/png',
        metadata: const {'sha256': _id},
      );
      await pumpEventQueue();
      final task = storage.puts.single.task;
      task.events.addError(_storageError('quota-exceeded'));
      task.done.completeError(_storageError('quota-exceeded'));
      await expectLater(upload, _backendError(SyncErrorCode.resourceExhausted));
    });

    test('cancel: the task is cancelled → cancelled; a token cancelled before '
        'never starts a task', () async {
      final token = SyncCancelToken();
      final upload = blobs.upload(
        _path,
        Uint8List(3),
        contentType: 'image/png',
        metadata: const {'sha256': _id},
        cancel: token,
      );
      await pumpEventQueue();
      token.cancel();
      await expectLater(upload, _backendError(SyncErrorCode.cancelled));
      expect(storage.puts.single.task.cancels, 1);

      await expectLater(
        blobs.upload(
          _path,
          Uint8List(3),
          contentType: 'image/png',
          metadata: const {'sha256': _id},
          cancel: token,
        ),
        _backendError(SyncErrorCode.cancelled),
      );
      expect(storage.puts, hasLength(1));
    });
  });

  group('download', () {
    test('the bytes, getData(maxBytes), progress at start and end', () async {
      storage.objects[_path] = Uint8List.fromList([1, 2, 3, 4]);
      final progress = <(int, int)>[];
      final bytes = await blobs.download(
        _path,
        maxBytes: 10,
        onProgress: (received, total) => progress.add((received, total)),
      );
      expect(bytes, [1, 2, 3, 4]);
      expect(storage.reads, [10]);
      expect(progress, [(0, 4), (4, 4)]);
    });

    test('larger than maxBytes → invalidArgument before reading; missing → '
        'notFound', () async {
      storage.objects[_path] = Uint8List(11);
      await expectLater(
        blobs.download(_path, maxBytes: 10),
        _backendError(SyncErrorCode.invalidArgument),
      );
      expect(storage.reads, isEmpty);
      await expectLater(
        blobs.download('users/u1/assets/missing', maxBytes: 10),
        _backendError(SyncErrorCode.notFound),
      );
    });

    test('cancel while reading → cancelled; no data → notFound', () async {
      storage.objects[_path] = Uint8List(4);
      storage.read = Completer<Uint8List?>();
      final token = SyncCancelToken();
      final download = blobs.download(_path, maxBytes: 10, cancel: token);
      await pumpEventQueue();
      expect(storage.reads, [10]);
      token.cancel();
      await expectLater(download, _backendError(SyncErrorCode.cancelled));
      storage.read!.complete(Uint8List(4));

      storage.read = Completer<Uint8List?>()..complete(null);
      await expectLater(
        blobs.download(_path, maxBytes: 10),
        _backendError(SyncErrorCode.notFound),
      );
    });
  });

  group('firebaseBackendFactory (FirebaseSyncBindings.backendFactory)', () {
    test('persistence off once, one Firestore and Storage, a backend per '
        'user', () async {
      var firestores = 0;
      var storages = 0;
      final db = _SettingsFirestore();
      final factory = firebaseBackendFactory(
        firestore: () {
          firestores++;
          return db;
        },
        storage: () {
          storages++;
          return storage;
        },
        disablePersistence: true,
      );
      expect(firestores, 0);
      final alice = await factory(const AuthUser(uid: 'alice'));
      final bob = await factory(const AuthUser(uid: 'bob'));
      expect((firestores, storages), (1, 1));
      expect(db.applied, [isA<Settings>()]);
      expect(db.applied.single.persistenceEnabled, isFalse);
      expect(alice, isA<FirebaseSyncBackend>());
      expect((alice.uid, bob.uid), ('alice', 'bob'));
      expect(alice.blobs.pathFor(_id), 'users/alice/assets/$_id');
      expect(bob.blobs.pathFor(_id), 'users/bob/assets/$_id');

      await alice.commitChunks([
        ChunkWrite(
          id: 'c1',
          scope: 'lib',
          authorNodeId: '0123456789abcdef',
          recordCount: 1,
          format: 1,
          kind: ChunkKind.delta,
          maxHlc: 'h',
          payload: Uint8List(2),
        ),
      ]);
      final docs = await db.collection('users/alice/changes').get();
      expect(docs.docs.map((d) => d.id), ['c1']);
    });

    test('disablePersistence: false leaves the settings alone', () async {
      final db = _SettingsFirestore();
      final factory = firebaseBackendFactory(
        firestore: () => db,
        storage: () => storage,
        disablePersistence: false,
      );
      await factory(const AuthUser(uid: 'alice'));
      expect(db.applied, isEmpty);
    });
  });
}

/// fake_cloud_firestore has no settings; this one records them.
final class _SettingsFirestore extends FakeFirebaseFirestore {
  final List<Settings> applied = [];

  @override
  set settings(Settings settings) => applied.add(settings);
}
