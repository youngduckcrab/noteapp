// S09 (9.1.2, 6.9): a 50 MB PDF. (a) B sees waitingForUpload → remoteReady, then downloads
// on request → local, same bytes. (b) B imports the same PDF → still one upload. (c) the
// upload stops at 60 % → retried and done.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

const int kPdfBytes = 50 * 1000 * 1000;

Uint8List pdfBytes({int seed = 1}) {
  final out = Uint8List(kPdfBytes);
  for (var i = 0; i < kPdfBytes; i += 4096) {
    out[i] = (i ~/ 4096 + seed) % 256;
  }
  return out;
}

/// Plain loop: matcher's deep equality is slow on 50 MB.
bool sameBytes(Uint8List? a, Uint8List b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  syncScenario('S09 (a) waitingForUpload → remoteReady → downloading → local, '
      '(b) the same PDF on B is not uploaded again', (h) {
    final a = h.device('A');
    final b = h.device('B');
    h.settle();
    final bytes = pdfBytes();
    final note = a.createNote('PDF note');
    final id = h.run(a.putAsset(bytes));
    elapseUntil(
      h,
      () => entityOn<Asset>(b, EntityKind.asset, id) != null,
      max: const Duration(seconds: 5),
    );
    final states = <AssetAvailabilityState>[];
    var closed = false;
    final sub = b.engine.assets
        .watch(id)
        .listen((v) => states.add(v.state), onDone: () => closed = true);
    h.settle();
    expect(states, [
      AssetAvailabilityState.waitingForUpload,
      AssetAvailabilityState.remoteReady,
    ]);
    expect(h.run(b.engine.assets.ensureLocal(id)), isTrue);
    h.settle();
    // queued may be passed over between two reads of the watch.
    expect(
      states.sublist(2),
      everyElement(
        isIn(const {
          AssetAvailabilityState.queued,
          AssetAvailabilityState.downloading,
          AssetAvailabilityState.local,
        }),
      ),
    );
    expect(states, contains(AssetAvailabilityState.downloading));
    expect(states.last, AssetAvailabilityState.local);
    expect(closed, isTrue);
    expect(sameBytes(h.run(b.store.assets.readBytes(id)), bytes), isTrue);
    expect(noteOn(b, note).title, 'PDF note');

    // (b) B imports the same file: already uploaded (its record has storagePath).
    expect(h.run(b.putAsset(bytes)), id);
    h.settle();
    expect(h.server.blobsOf('user-1').uploadCount, 1);
    expect(b.link.callCount(FakeOp.upload), 0);
    h.checkConverged([a, b]);
    unawaited(sub.cancel());
  });

  syncScenario('S09 (b) both import the same PDF before either uploaded it', (
    h,
  ) {
    final a = h.device('A');
    final b = h.device('B');
    h.settle();
    final bytes = pdfBytes(seed: 2);
    final id = h.run(a.putAsset(bytes));
    expect(h.run(b.putAsset(bytes)), id);
    h.settle();
    expect(h.server.blobsOf('user-1').uploadCount, 1);
    for (final d in [a, b]) {
      expect(entityOn<Asset>(d, EntityKind.asset, id)!.storagePath, isNotNull);
    }
    h.checkConverged([a, b]);
  });

  syncScenario('S09 (c) the upload stops at 60 % and is retried', (h) {
    final a = h.device('A');
    final b = h.device('B');
    h.settle();
    a.link.failNext(const FakeInterrupt(0.6), op: FakeOp.upload);
    final bytes = pdfBytes(seed: 3);
    final id = h.run(a.putAsset(bytes));
    h.settle();
    expect(a.link.callCount(FakeOp.upload), 2);
    final path = entityOn<Asset>(b, EntityKind.asset, id)!.storagePath!;
    expect(sameBytes(h.server.blobsOf('user-1').objects[path], bytes), isTrue);
    expect(h.run(b.engine.assets.ensureLocal(id)), isTrue);
    expect(sameBytes(h.run(b.store.assets.readBytes(id)), bytes), isTrue);
    h.checkConverged([a, b]);
  });
}
