// The playback service (m5-7/06-pdf 6.11, 4.2.3; 8.2 T34). Two worlds:
// ① the app's player (JustAudioPlayerPort → just_audio) over FakeJustAudioPlatform, the native
//    play cache in a temp directory and CORE's fake store — open state order, the remote fetch
//    (a fake RemoteAssetFetcher here: media_io cannot use pdf_io's test helpers), iOS + webm,
//    format errors, clamping, completed, play while recording, close, media.playbackSpeed;
//    nothing here asserts on real time.
// ② a scripted player over fake time (test/support/fake_engines.dart) — positionMs
//    extrapolation, the web's preload: false (length from the row, a seek before the first
//    play), the stop hand-off (P-B), player errors while open, a second open overtaking a first.
// Plus the native duration probe (6.6.4) and the format-error classification.
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/playback/audio_source_native.dart';
import 'package:media_io/src/playback/duration_probe.dart';
import 'package:media_io/src/playback/handoff_blob.dart';
import 'package:media_io/src/playback/playback_service.dart';
import 'package:media_io/src/playback/player_port.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/fake_engines.dart';

/// An AssetStore whose bytes are 'not on this device' until [local] (the fetcher sets it), and
/// that counts getAsset / readBytes.
final class GatedAssets implements core.AssetStore {
  GatedAssets(this.inner);
  final core.AssetStore inner;
  bool local = true;
  int metaReads = 0;
  int byteReads = 0;

  @override
  Future<core.Asset?> getAsset(core.AssetId id) {
    metaReads++;
    return inner.getAsset(id);
  }

  @override
  Future<Uint8List?> readBytes(core.AssetId id) async {
    byteReads++;
    return local ? inner.readBytes(id) : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ensureLocal answers [answer] and, when true, makes the bytes local.
final class FakeRemoteAssetFetcher implements core.RemoteAssetFetcher {
  FakeRemoteAssetFetcher(this.assets, {this.answer = true});
  final GatedAssets assets;
  final bool answer;
  final List<core.AssetId> asked = [];

  @override
  Future<bool> ensureLocal(core.AssetId id) async {
    asked.add(id);
    if (answer) assets.local = true;
    return answer;
  }

  @override
  Stream<core.RemoteAssetProgress> watch(core.AssetId id) =>
      const Stream.empty();
}

core.Recording recordingOf(
  core.Asset asset, {
  String id = 'rec-1',
  int durationMs = 1234,
}) => core.Recording(
  id: id,
  noteId: 'note-1',
  assetId: asset.id,
  durationMs: durationMs,
  startedAt: 1,
  createdAt: 1,
  updatedAt: 1,
);

/// ① The app's player over FakeJustAudioPlatform.
final class JustAudioWorld {
  JustAudioWorld() {
    player = FakeJustAudioPlatform.install();
    dir = Directory.systemTemp.createTempSync('media_io_play_');
    assets = GatedAssets(store.assets);
  }

  final core.NoteStore store = core_testing.createFakeNoteStore();
  late final FakeJustAudioPlatform player;
  late final Directory dir;
  late final GatedAssets assets;
  core.RemoteAssetFetcher? fetcher;
  bool recorderActive = false;

  late final JustAudioPlaybackService service = JustAudioPlaybackService(
    assets: () => assets,
    settings: () => store.settings,
    fetcher: () => fetcher,
    recorderActive: () => recorderActive,
    sources: NativeAudioSources(cacheRoot: () async => dir.path),
  );

  late final List<core.PlaybackStatus> statuses = _listen();
  List<core.PlaybackStatus> _listen() {
    final out = <core.PlaybackStatus>[];
    service.statusStream.listen(out.add);
    return out;
  }

  List<core.PlaybackPhase> get phases => [for (final s in statuses) s.phase];

  Future<core.Asset> put({
    String mimeType = 'audio/mp4',
    int length = 64,
    int seed = 1,
  }) => store.assets.put(
    Uint8List.fromList(List.generate(length, (i) => (i * seed + 7) & 0xFF)),
    type: core.AssetType.audio,
    mimeType: mimeType,
    fileName: 'rec.m4a',
  );

  String cachePath(core.Asset asset, [String ext = 'm4a']) =>
      '${dir.path}/media_io/play/${asset.id}.$ext';

  String uriOf(core.Asset asset, [String ext = 'm4a']) =>
      Uri.file(cachePath(asset, ext)).toString();

  /// Waits until the service reaches [phase].
  Future<void> until(core.PlaybackPhase phase) async {
    if (service.status.phase == phase) return;
    await service.statusStream.firstWhere((s) => s.phase == phase);
  }

  Future<void> dispose() async {
    await service.dispose();
    await store.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

void justAudioTest(String name, Future<void> Function(JustAudioWorld w) body) {
  test(name, () async {
    final w = JustAudioWorld();
    try {
      await body(w);
    } finally {
      await w.dispose();
    }
  });
}

/// ② A scripted player over fake time.
final class ScriptedWorld {
  ScriptedWorld(
    this.async, {
    bool preload = true,
    bool rowLength = false,
    this.handoff,
  }) : sources = FakeAudioSources(
         preload: preload,
         usesRecordingDuration: rowLength,
       ) {
    port = FakePlayerPort(now: () => async.elapsed);
    assets = GatedAssets(store.assets);
    service = JustAudioPlaybackService(
      assets: () => assets,
      settings: () => store.settings,
      player: () => port,
      sources: sources,
      handoff: handoff,
    );
  }

  final FakeAsync async;
  final core.NoteStore store = core_testing.createFakeNoteStore();
  final FakeAudioSources sources;
  final PlaybackHandoff? handoff;
  late final FakePlayerPort port;
  late final GatedAssets assets;
  late final JustAudioPlaybackService service;

  T wait<T>(Future<T> f) {
    T? out;
    Object? error;
    var done = false;
    f.then(
      (v) {
        out = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    for (var i = 0; i < 100 && !done; i++) {
      async.flushMicrotasks();
      async.elapse(Duration.zero);
    }
    if (error case final e?) Error.throwWithStackTrace(e, StackTrace.current);
    expect(done, isTrue, reason: 'the future did not complete');
    return out as T;
  }

  core.Asset put({String mimeType = 'audio/webm;codecs=opus'}) => wait(
    store.assets.put(
      Uint8List.fromList(List.generate(48, (i) => i)),
      type: core.AssetType.audio,
      mimeType: mimeType,
    ),
  );

  void close() {
    wait(service.dispose());
    wait(store.close());
  }
}

void scriptedTest(
  String name,
  void Function(ScriptedWorld w) body, {
  bool preload = true,
  bool rowLength = false,
  PlaybackHandoff? Function()? handoff,
}) {
  test(name, () {
    fakeAsync((async) {
      final w = ScriptedWorld(
        async,
        preload: preload,
        rowLength: rowLength,
        handoff: handoff?.call(),
      );
      body(w);
      w.close();
    });
  });
}

void main() {
  // just_audio's AudioPlayer sets up audio_session's method channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('over just_audio (FakeJustAudioPlatform)', () {
    justAudioTest('open: idle → loading → ready; the native length is the '
        "player's; the cache file is written once", (w) async {
      final asset = await w.put();
      w.player.durations[w.uriOf(asset)] = const Duration(milliseconds: 1500);
      w.statuses;
      await w.service.open(recordingOf(asset));
      await pumpEventQueue(); // statusStream delivers asynchronously
      expect(w.phases, [
        core.PlaybackPhase.idle,
        core.PlaybackPhase.loading,
        core.PlaybackPhase.ready,
      ]);
      expect(w.service.status.recordingId, 'rec-1');
      expect(w.service.status.durationMs, 1500);
      expect(w.service.status.speed, 1.0);
      expect(w.service.status.error, isNull);
      expect(w.player.calls, contains('load:${w.uriOf(asset)}'));
      expect(
        File(w.cachePath(asset)).readAsBytesSync(),
        await w.store.assets.readBytes(asset.id),
      );
      expect(w.service.positionMs(), 0);

      // The same asset again: the cache file is reused (no byte read).
      final reads = w.assets.byteReads;
      await w.service.open(recordingOf(asset, id: 'rec-2'));
      expect(w.service.status.phase, core.PlaybackPhase.ready);
      expect(w.service.status.recordingId, 'rec-2');
      expect(w.assets.byteReads, reads);
    });

    justAudioTest('play → playing, pause → paused, the end → completed (positionMs = the length), '
        'play again starts at 0', (w) async {
      final asset = await w.put();
      w.player.durations[w.uriOf(asset)] = const Duration(milliseconds: 1500);
      await w.service.open(recordingOf(asset));
      await w.service.play();
      await w.until(core.PlaybackPhase.playing);
      expect(w.service.positionMs(), inInclusiveRange(0, 1500));
      await w.service.pause();
      await w.until(core.PlaybackPhase.paused);
      // Paused: the position is the player's, without extrapolation.
      w.player.setPosition(const Duration(milliseconds: 700));
      await pumpEventQueue();
      expect(w.service.positionMs(), 700);
      await w.service.play();
      await w.until(core.PlaybackPhase.playing);
      // Playing: extrapolated from 700, never past the length.
      expect(w.service.positionMs(), inInclusiveRange(700, 1500));
      w.player.complete();
      await w.until(core.PlaybackPhase.completed);
      expect(w.service.positionMs(), 1500);
      await w.service.play();
      await w.until(core.PlaybackPhase.playing);
      expect(w.player.calls, contains('seek:0'));
    });

    justAudioTest(
      'seekMs and setSpeed are clamped; the speed is remembered for '
      'the next open (media.playbackSpeed)',
      (w) async {
        final asset = await w.put();
        w.player.durations[w.uriOf(asset)] = const Duration(milliseconds: 1500);
        await w.service.open(recordingOf(asset));
        await w.service.seekMs(-5);
        await w.service.seekMs(99999);
        expect(w.player.calls, containsAllInOrder(['seek:0', 'seek:1500']));
        await w.service.setSpeed(3);
        expect(w.service.status.speed, 2.0);
        await w.service.setSpeed(0.1);
        expect(w.service.status.speed, 0.5);
        expect(w.player.calls, containsAllInOrder(['speed:2.0', 'speed:0.5']));
        await pumpEventQueue();
        expect(await w.store.settings.get(MediaSettingKeys.playbackSpeed), 0.5);

        await w.service.close();
        await w.service.open(recordingOf(asset, id: 'rec-2'));
        expect(w.service.status.speed, 0.5);
        expect(w.player.calls.last, 'speed:0.5');

        // Out-of-range stored values are clamped too.
        await w.store.settings.set(MediaSettingKeys.playbackSpeed, 9.0);
        await w.service.open(recordingOf(asset, id: 'rec-3'));
        expect(w.service.status.speed, 2.0);
      },
    );

    justAudioTest('nothing open: pause / seekMs / setSpeed do nothing, '
        'positionMs is 0', (w) async {
      await w.service.pause();
      await w.service.seekMs(100);
      await w.service.setSpeed(2);
      await w.service.play();
      expect(w.service.status, const core.PlaybackStatus());
      expect(w.service.positionMs(), 0);
      expect(w.player.calls, isEmpty);
    });

    justAudioTest('bytes not on this device: the fetcher brings them → opens', (
      w,
    ) async {
      final asset = await w.put();
      w.assets.local = false;
      final fetcher = FakeRemoteAssetFetcher(w.assets);
      w.fetcher = fetcher;
      await w.service.open(recordingOf(asset));
      expect(fetcher.asked, [asset.id]);
      expect(w.service.status.phase, core.PlaybackPhase.ready);
      expect(File(w.cachePath(asset)).existsSync(), isTrue);
    });

    justAudioTest('bytes not on this device and the fetcher has none / no '
        'fetcher → failed (assetMissing)', (w) async {
      final asset = await w.put();
      w.assets.local = false;
      w.fetcher = FakeRemoteAssetFetcher(w.assets, answer: false);
      await w.service.open(recordingOf(asset));
      expect(w.service.status.phase, core.PlaybackPhase.failed);
      expect(
        (w.service.status.error! as MediaIoException).code,
        MediaErrorCode.assetMissing,
      );
      expect(w.service.status.unsupportedFormat, isFalse);

      w.fetcher = null;
      await w.service.open(recordingOf(asset, id: 'rec-2'));
      expect(w.service.status.phase, core.PlaybackPhase.failed);
      expect(w.service.status.recordingId, 'rec-2');
      expect(w.player.calls.where((c) => c.startsWith('load:')), isEmpty);
      expect(File(w.cachePath(asset)).existsSync(), isFalse);
    });

    justAudioTest('no asset row → failed (assetMissing)', (w) async {
      final asset = await w.put();
      await w.service.open(
        core.Recording(
          id: 'rec-x',
          noteId: 'note-1',
          assetId: 'f' * 64,
          durationMs: 10,
          startedAt: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      expect(w.service.status.phase, core.PlaybackPhase.failed);
      expect(
        (w.service.status.error! as MediaIoException).code,
        MediaErrorCode.assetMissing,
      );
      expect(asset.id, isNot('f' * 64));
    });

    justAudioTest('iOS native + webm → failed + unsupportedFormat without '
        'opening', (w) async {
      final asset = await w.put(mimeType: 'audio/webm;codecs=opus');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await w.service.open(recordingOf(asset));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(w.service.status.phase, core.PlaybackPhase.failed);
      expect(w.service.status.unsupportedFormat, isTrue);
      expect(
        (w.service.status.error! as MediaIoException).code,
        MediaErrorCode.unsupportedFormat,
      );
      expect(w.assets.byteReads, 0);
      expect(w.player.calls.where((c) => c.startsWith('load:')), isEmpty);

      // Android plays the same webm (it opens).
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await w.service.open(recordingOf(asset, id: 'rec-2'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(w.service.status.phase, core.PlaybackPhase.ready);
      expect(w.player.calls, contains('load:${w.uriOf(asset, 'webm')}'));
    });

    justAudioTest('a player format error → failed + unsupportedFormat', (
      w,
    ) async {
      final asset = await w.put();
      w.player.failNextLoad();
      await w.service.open(recordingOf(asset));
      expect(w.service.status.phase, core.PlaybackPhase.failed);
      expect(w.service.status.unsupportedFormat, isTrue);
      expect(
        (w.service.status.error! as MediaIoException).code,
        MediaErrorCode.unsupportedFormat,
      );
      // The next open works again.
      await w.service.open(recordingOf(asset, id: 'rec-2'));
      expect(w.service.status.phase, core.PlaybackPhase.ready);
      expect(w.service.status.unsupportedFormat, isFalse);
      expect(w.service.status.error, isNull);
    });

    justAudioTest('play() does nothing while the recorder is active '
        '(CP-PDF-10)', (w) async {
      final asset = await w.put();
      await w.service.open(recordingOf(asset));
      w.recorderActive = true;
      await w.service.play();
      await pumpEventQueue();
      expect(w.service.status.phase, core.PlaybackPhase.ready);
      expect(w.player.calls, isNot(contains('play')));
      w.recorderActive = false;
      await w.service.play();
      await w.until(core.PlaybackPhase.playing);
    });

    justAudioTest('close → idle; positionMs 0; play does nothing', (w) async {
      final asset = await w.put();
      await w.service.open(recordingOf(asset));
      await w.service.play();
      await w.until(core.PlaybackPhase.playing);
      await w.service.close();
      expect(w.service.status, const core.PlaybackStatus());
      expect(w.service.positionMs(), 0);
      await w.service.play();
      expect(w.service.status.phase, core.PlaybackPhase.idle);
      // The cache file stays for the next open (6.11.3).
      expect(File(w.cachePath(asset)).existsSync(), isTrue);
    });

    justAudioTest(
      'dispose → idle, the player disposed; dispose twice is fine',
      (w) async {
        final asset = await w.put();
        await w.service.open(recordingOf(asset));
        await w.service.dispose();
        await w.service.dispose();
        expect(w.service.status.phase, core.PlaybackPhase.idle);
        expect(w.player.calls, contains('disposePlayer'));
        expect(() => w.service.open(recordingOf(asset)), throwsStateError);
      },
    );
  });

  group('scripted player (fake time)', () {
    scriptedTest('positionMs extrapolates while playing, × speed, up to the '
        'length; completed = the length', (w) {
      final asset = w.put();
      w.port.lengths['mem:${asset.id}'] = const Duration(milliseconds: 1500);
      w.wait(w.service.open(recordingOf(asset)));
      expect(w.service.status.durationMs, 1500);
      w.wait(w.service.play());
      expect(w.service.status.phase, core.PlaybackPhase.playing);
      w.async.elapse(const Duration(milliseconds: 400));
      expect(w.service.positionMs(), 400);
      w.wait(w.service.setSpeed(2));
      w.async.elapse(const Duration(milliseconds: 100));
      expect(w.service.positionMs(), 600);
      w.wait(w.service.pause());
      w.async.elapse(const Duration(seconds: 5));
      expect(w.service.positionMs(), 600);
      expect(w.service.status.phase, core.PlaybackPhase.paused);
      w.wait(w.service.play());
      w.async.elapse(const Duration(seconds: 5));
      expect(w.service.positionMs(), 1500);
      w.port.complete();
      expect(w.service.status.phase, core.PlaybackPhase.completed);
      expect(w.service.positionMs(), 1500);
      // At the end the service pauses the player, so a seek does not play again.
      w.async.flushMicrotasks();
      expect(w.port.snapshot.playing, isFalse);
      w.wait(w.service.seekMs(300));
      expect(w.service.status.phase, core.PlaybackPhase.paused);
      expect(w.service.positionMs(), 300);
    });

    scriptedTest(
      'web preload: false — the length is the row\'s, a seek before the first '
      'play is applied by that play',
      (w) {
        final asset = w.put();
        w.port.lengths['mem:${asset.id}'] = null; // the player knows no length
        w.wait(w.service.open(recordingOf(asset, durationMs: 2222)));
        expect(w.service.status.phase, core.PlaybackPhase.ready);
        expect(w.service.status.durationMs, 2222);
        expect(w.port.calls, contains('load(deferred):mem:${asset.id}'));
        w.wait(w.service.seekMs(700));
        expect(w.service.positionMs(), 700);
        expect(w.port.calls.where((c) => c.startsWith('seek')), isEmpty);
        w.wait(w.service.play());
        expect(w.port.calls, containsAllInOrder(['seek:700', 'play']));
        w.async.elapse(const Duration(milliseconds: 250));
        expect(w.service.positionMs(), 950);
        // Once playing, seeks go to the player.
        w.wait(w.service.seekMs(100));
        expect(w.port.calls.last, 'seek:100');
      },
      preload: false,
      rowLength: true,
    );

    scriptedTest(
      '(P-B) the stop hand-off: the next open of that asset reads no bytes; '
      'used once',
      (w) {
        final asset = w.put();
        w.handoff!.offer(asset.id, Uint8List(64), 'audio/webm');
        expect(w.handoff!.holds, isTrue);
        w.wait(w.service.open(recordingOf(asset)));
        expect(w.service.status.phase, core.PlaybackPhase.ready);
        expect(w.sources.handoffs.single, 'blob of 64 bytes');
        expect(w.assets.metaReads, 0);
        expect(w.assets.byteReads, 0);
        expect(w.handoff!.holds, isFalse);
        w.wait(w.service.open(recordingOf(asset, id: 'rec-2')));
        expect(w.sources.handoffs.last, isNull);
        expect(w.assets.byteReads, 1);
      },
      handoff: () => PlaybackHandoff(
        blobOf: (bytes, _) => 'blob of ${bytes.length} bytes',
        minBytes: 32,
      ),
    );

    test('PlaybackHandoff: smaller than minBytes or no Blob (native) → '
        'nothing; another asset\'s open drops it', () {
      final made = <int>[];
      final h = PlaybackHandoff(
        blobOf: (bytes, _) {
          made.add(bytes.length);
          return 'blob';
        },
        minBytes: 10,
      );
      h.offer('a', Uint8List(9), 'audio/webm');
      expect(h.holds, isFalse);
      expect(made, isEmpty);
      h.offer('a', Uint8List(10), 'audio/webm');
      expect(h.take('b'), isNull);
      expect(h.holds, isFalse);
      h.offer('a', Uint8List(10), 'audio/webm');
      expect(h.take('a'), 'blob');
      expect(h.take('a'), isNull);
      final native = PlaybackHandoff(minBytes: 1);
      native.offer('a', Uint8List(10), 'audio/mp4');
      expect(native.holds, isFalse); // createHandoffBlob is null off the web
    });

    scriptedTest('a player error while open → failed (+ unsupportedFormat '
        'for a format error)', (w) {
      final asset = w.put();
      w.wait(w.service.open(recordingOf(asset)));
      w.wait(w.service.play());
      w.port.fail(const PlayerFailure(formatError: true));
      expect(w.service.status.phase, core.PlaybackPhase.failed);
      expect(w.service.status.unsupportedFormat, isTrue);
      w.wait(w.service.open(recordingOf(asset, id: 'rec-2')));
      w.port.fail(const PlayerFailure(formatError: false));
      expect(w.service.status.phase, core.PlaybackPhase.failed);
      expect(w.service.status.unsupportedFormat, isFalse);
      expect(
        (w.service.status.error! as MediaIoException).code,
        MediaErrorCode.playbackFailed,
      );
    });

    scriptedTest('a second open overtakes a first one still loading', (w) {
      final a = w.put();
      final b = w.put(mimeType: 'audio/mp4');
      final gate = w.port.loadGate = Completer<void>();
      final first = w.service.open(recordingOf(a, id: 'rec-a'));
      w.async.flushMicrotasks();
      expect(w.service.status.phase, core.PlaybackPhase.loading);
      w.port.loadGate = null;
      final second = w.service.open(recordingOf(b, id: 'rec-b'));
      gate.complete();
      w.wait(first);
      w.wait(second);
      expect(w.service.status.phase, core.PlaybackPhase.ready);
      expect(w.service.status.recordingId, 'rec-b');
    });
  });

  group('duration probe (6.6.4, native)', () {
    test('the length the player reads; null / 0 / a failure → null; the '
        'probe player is disposed', () {
      fakeAsync((async) {
        int? probe(FakePlayerPort port) {
          int? out;
          probeDurationMs('/r.m4a', player: () => port).then((v) => out = v);
          async.flushMicrotasks();
          expect(port.disposed, isTrue);
          return out;
        }

        final p1 = FakePlayerPort(now: () => async.elapsed)
          ..lengths['/r.m4a'] = const Duration(milliseconds: 1500);
        expect(probe(p1), 1500);
        final p2 = FakePlayerPort(now: () => async.elapsed)
          ..lengths['/r.m4a'] = null;
        expect(probe(p2), isNull);
        final p3 = FakePlayerPort(now: () => async.elapsed)
          ..lengths['/r.m4a'] = Duration.zero;
        expect(probe(p3), isNull);
        final p4 = FakePlayerPort(now: () => async.elapsed)
          ..failNextLoad = const PlayerFailure(formatError: true);
        expect(probe(p4), isNull);
      });
    });

    test('a load that does not answer within durationProbeTimeout → null', () {
      fakeAsync((async) {
        final port = FakePlayerPort(now: () => async.elapsed)
          ..loadGate = Completer<void>();
        var done = false;
        int? out = -1;
        probeDurationMs('/r.m4a', player: () => port).then((v) {
          out = v;
          done = true;
        });
        async.elapse(const Duration(milliseconds: 4999));
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(done, isTrue);
        expect(out, isNull);
        expect(port.disposed, isTrue);
      });
    });

    test('over just_audio (FakeJustAudioPlatform)', () async {
      final fake = FakeJustAudioPlatform.install();
      fake.durations[Uri.file('/tmp/r.m4a').toString()] = const Duration(
        milliseconds: 2500,
      );
      expect(await probeDurationMs('/tmp/r.m4a'), 2500);
      fake.failNextLoad();
      expect(await probeDurationMs('/tmp/r.m4a'), isNull);
    });
  });

  test('format errors (6.11.2)', () {
    bool f(int code, {String? message, bool web = false, TargetPlatform? on}) =>
        isPlayerFormatError(
          code: code,
          message: message,
          web: web,
          platform: on ?? TargetPlatform.android,
        );
    expect(f(4, web: true), isTrue);
    expect(f(3, web: true), isTrue);
    expect(f(2, web: true), isFalse);
    expect(f(0), isTrue);
    expect(f(1), isFalse);
    expect(f(-11828, on: TargetPlatform.iOS), isTrue);
    expect(f(-11800, on: TargetPlatform.iOS), isFalse);
    expect(f(9999999, message: 'unsupported'), isTrue);
    expect(f(9999999, message: 'Source error: Unrecognized format'), isTrue);
    expect(
      f(9999999, message: 'connection reset', on: TargetPlatform.linux),
      isFalse,
    );
  });
}
