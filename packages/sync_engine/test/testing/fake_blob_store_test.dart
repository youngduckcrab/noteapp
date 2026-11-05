import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/fake_time.dart';

final DateTime start = DateTime.utc(2026, 11, 1);
const Duration latency = Duration(milliseconds: 50);
const int mib = 1024 * 1024;

Uint8List bytesOf(int length, {int seed = 1}) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 31 + seed) % 251,
]);

String idOf(Uint8List bytes) => sha256.convert(bytes).toString();

Map<String, String> metaOf(Uint8List bytes) => {
  'sha256': idOf(bytes),
  'size': '${bytes.length}',
  'type': 'pdf',
};

final class Rig {
  Rig(this.async) {
    server = FakeSyncServer(clock: async.getClock(start));
    backend = server.connect(uid: 'user-1', link: link);
    store = server.blobsOf('user-1');
  }

  final FakeAsync async;
  late final FakeSyncServer server;
  final FakeNetworkLink link = FakeNetworkLink();
  late final FakeSyncBackend backend;
  late final FakeBlobStore store;

  RemoteBlobStore get blobs => backend.blobs;

  T run<T>(Future<T> future) => runFake(async, future);
  SyncErrorCode errorCode(Future<Object?> future) =>
      (runFakeError(async, future) as SyncBackendException).code;

  Future<void> upload(
    Uint8List bytes, {
    List<(int, int)>? progress,
    SyncCancelToken? cancel,
    Map<String, String>? metadata,
    String? path,
  }) => blobs.upload(
    path ?? blobs.pathFor(idOf(bytes)),
    bytes,
    contentType: 'application/pdf',
    metadata: metadata ?? metaOf(bytes),
    onProgress: progress == null ? null : (s, t) => progress.add((s, t)),
    cancel: cancel,
  );
}

void main() {
  test('pathFor and stat of a missing object', () {
    fakeAsync((async) {
      final r = Rig(async);
      final id = 'a' * 64;
      expect(r.blobs.pathFor(id), 'users/user-1/assets/$id');
      expect(r.store.pathFor(id), 'users/user-1/assets/$id');
      expect(r.run(r.blobs.stat(r.blobs.pathFor(id))), isNull);
      expect(r.link.callCount(FakeOp.stat), 1);
    });
  });

  test('upload: pieces with progress, then stat reports the object', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(2 * mib + mib ~/ 2);
      final progress = <(int, int)>[];
      r.run(r.upload(bytes, progress: progress));
      final total = bytes.length;
      expect(progress, [
        (0, total),
        (mib, total),
        (2 * mib, total),
        (total, total),
      ]);
      // Request + 3 pieces of 10 ms + response.
      expect(async.elapsed, latency * 2 + const Duration(milliseconds: 30));
      expect(r.store.uploadCount, 1);
      final path = r.blobs.pathFor(idOf(bytes));
      expect(r.store.objects[path], bytes);
      final info = r.run(r.blobs.stat(path))!;
      expect(info.path, path);
      expect(info.size, total);
      expect(info.sha256, idOf(bytes));
      expect(info.contentType, 'application/pdf');
    });
  });

  test('interrupted upload stores nothing; the retry succeeds', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(5 * mib);
      r.link.failNext(const FakeInterrupt(0.6), op: FakeOp.upload);
      final progress = <(int, int)>[];
      expect(
        r.errorCode(r.upload(bytes, progress: progress)),
        SyncErrorCode.network,
      );
      final cut = (bytes.length * 0.6).floor();
      expect(progress.last, (cut, bytes.length));
      expect(progress.every((p) => p.$1 <= cut), isTrue);
      expect(r.store.objects, isEmpty);
      expect(r.store.uploadCount, 0);

      r.run(r.upload(bytes));
      expect(r.store.uploadCount, 1);
      expect(r.link.callCount(FakeOp.upload), 2);
      expect(r.store.objects.values.single, bytes);
    });
  });

  test('uploading an existing object with the same sha256 succeeds without '
      'writing; other content at the path is denied', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(1000);
      r.run(r.upload(bytes));
      r.run(r.upload(bytes));
      expect(r.store.uploadCount, 1);
      final other = bytesOf(1001, seed: 2);
      expect(
        r.errorCode(
          r.upload(
            other,
            path: r.blobs.pathFor(idOf(bytes)),
            metadata: metaOf(bytes),
          ),
        ),
        SyncErrorCode.permissionDenied,
      );
      expect(r.store.objects.values.single, bytes);
    });
  });

  test('storage rules: own asset path and metadata sha256', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(10);
      final id = idOf(bytes);
      expect(
        r.errorCode(r.upload(bytes, path: 'users/user-2/assets/$id')),
        SyncErrorCode.permissionDenied,
      );
      expect(
        r.errorCode(r.upload(bytes, path: 'users/user-1/assets/not-hex')),
        SyncErrorCode.permissionDenied,
      );
      expect(
        r.errorCode(r.upload(bytes, metadata: {'sha256': 'b' * 64})),
        SyncErrorCode.permissionDenied,
      );
      expect(
        r.errorCode(r.blobs.stat('users/user-2/assets/$id')),
        SyncErrorCode.permissionDenied,
      );
      expect(r.store.objects, isEmpty);
    });
  });

  test('download: bytes, progress, maxBytes and missing objects', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(mib + 10);
      final path = r.blobs.pathFor(idOf(bytes));
      expect(
        r.errorCode(r.blobs.download(path, maxBytes: 1 << 30)),
        SyncErrorCode.notFound,
      );
      r.run(r.upload(bytes));
      expect(
        r.errorCode(r.blobs.download(path, maxBytes: bytes.length - 1)),
        SyncErrorCode.invalidArgument,
      );
      final progress = <(int, int)>[];
      final got = r.run(
        r.blobs.download(
          path,
          maxBytes: bytes.length,
          onProgress: (a, b) => progress.add((a, b)),
        ),
      );
      expect(got, bytes);
      expect(progress, [
        (0, bytes.length),
        (mib, bytes.length),
        (bytes.length, bytes.length),
      ]);
      expect(r.store.downloadCount, 1);
      // The returned bytes are a copy.
      got[0] ^= 0xff;
      expect(r.store.objects[path], bytes);
    });
  });

  test('interrupted download fails; the retry succeeds', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(3 * mib);
      final path = r.blobs.pathFor(idOf(bytes));
      r.run(r.upload(bytes));
      r.link.failNext(const FakeInterrupt(0.5), op: FakeOp.download);
      expect(
        r.errorCode(r.blobs.download(path, maxBytes: bytes.length)),
        SyncErrorCode.network,
      );
      expect(r.store.downloadCount, 0);
      expect(r.run(r.blobs.download(path, maxBytes: bytes.length)), bytes);
      expect(r.store.downloadCount, 1);
    });
  });

  test('going offline during a transfer fails it with network', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(5 * mib);
      final upload = r.upload(bytes);
      async.elapse(latency + const Duration(milliseconds: 25));
      r.link.setOnline(false);
      expect(r.errorCode(upload), SyncErrorCode.network);
      expect(r.store.objects, isEmpty);
    });
  });

  test('cancel before or during a transfer', () {
    fakeAsync((async) {
      final r = Rig(async);
      final bytes = bytesOf(5 * mib);
      final early = SyncCancelToken()..cancel();
      expect(
        r.errorCode(r.upload(bytes, cancel: early)),
        SyncErrorCode.cancelled,
      );

      final token = SyncCancelToken();
      final progress = <(int, int)>[];
      final upload = r.upload(bytes, cancel: token, progress: progress);
      async.elapse(latency + const Duration(milliseconds: 25));
      token.cancel();
      expect(r.errorCode(upload), SyncErrorCode.cancelled);
      expect(progress.last.$1, lessThan(bytes.length));
      expect(r.store.objects, isEmpty);
    });
  });

  test('faults on stat and the server-side store without the link', () {
    fakeAsync((async) {
      final r = Rig(async);
      r.link.failNext(
        const FakeErrorCode(SyncErrorCode.unavailable),
        op: FakeOp.stat,
      );
      final bytes = bytesOf(100);
      final path = r.store.pathFor(idOf(bytes));
      expect(r.errorCode(r.blobs.stat(path)), SyncErrorCode.unavailable);

      // Direct server access: no latency, no link calls.
      r.link.setOnline(false);
      r.run(
        r.store.upload(
          path,
          bytes,
          contentType: 'application/pdf',
          metadata: metaOf(bytes),
        ),
      );
      expect(r.run(r.store.stat(path))!.size, 100);
      expect(r.run(r.store.download(path, maxBytes: 100)), bytes);
      expect(r.link.callCount(FakeOp.upload), 0);

      // Tests may corrupt stored bytes; stat reports what is stored.
      r.store.objects[path] = Uint8List(7);
      expect(r.run(r.store.stat(path))!.size, 7);
      expect(r.run(r.store.stat(path))!.sha256, idOf(bytes));
    });
  });
}
