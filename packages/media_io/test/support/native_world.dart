// One device for the native recorder engine tests (m5-7/06-pdf 8.2 T33): the platform fakes of
// installFakeMediaPlatforms (the temp directory stands in for the app support directory),
// CORE's fake store with one note on a FakeAsync clock moved by hand, and a recording clock
// (FakeStopwatch) moved by hand — real async (dart:io file reads), no wall clock.
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/record/recorder_engine_native.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/tuning.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import 'fake_stopwatch.dart';

/// One device: the platform fakes, a store with one note, a hand-moved recording clock.
final class NativeWorld {
  NativeWorld() {
    store = core_testing.createFakeNoteStore(
      clock: time.getClock(DateTime.utc(2026, 11, 6, 9)),
    );
  }

  final MediaFakePlatforms fakes = installFakeMediaPlatforms();
  final FakeAsync time = FakeAsync();
  late final core.NoteStore store;
  late final core.NoteId noteId;
  Duration recorded = Duration.zero;
  final List<MediaRecorderService> _services = [];

  FakeRecordPlatform get record => fakes.record;
  String get recDir => '${fakes.directory}/${MediaTuning.nativeRecordingDir}';
  String pathOf(core.RecordingId id) =>
      '$recDir/${nativeRecordingFileName(id)}';

  Future<void> init() async {
    noteId = (await store.library.createNote(title: 'Lecture')).id;
  }

  /// A recorder service with a new native engine (a new app start).
  MediaRecorderService service({
    MediaIoConfig config = const MediaIoConfig(),
    NativeRecorderEngine? engine,
  }) {
    final s = MediaRecorderService(
      stores: () => RecorderStores.of(store),
      now: store.clock.now,
      config: config,
      engine: engine ?? NativeRecorderEngine(),
      stopwatch: () => FakeStopwatch(() => recorded),
    );
    _services.add(s);
    return s;
  }

  Future<void> dispose() async {
    for (final s in _services) {
      await s.dispose();
    }
    await store.close();
    fakes.dispose();
  }
}

Uint8List fileOf(int n) => Uint8List.fromList(List.generate(n, (i) => i % 251));
