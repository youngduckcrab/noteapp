// test/support/panel_world.dart — the RecordingPanel test world (m5-7/06-pdf 6.13.4): the CORE
// fake store, CORE FakeAudioRecorder / FakeAudioPlayback (or a ScriptedRecorder for statuses the
// fake cannot reach — microphone lost, backlog, another note), the panel in the EDITOR slot
// (40 % of an iPad Pro 13" height) and a recording seeder.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/providers.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import 'ipad.dart';

/// A recorder whose status the test sets ([emit]); logs calls. stop() returns [stopResult].
final class ScriptedRecorder implements core.AudioRecorderService {
  ScriptedRecorder({this.support = core.AudioSupport.supported});

  core.AudioSupport support;
  core.RecorderStatus _status = const core.RecorderStatus();
  final StreamController<core.RecorderStatus> _ctrl =
      StreamController.broadcast(sync: true);

  /// 'checkSupport', 'checkSupport(request)', 'start:{id}', 'pause', 'resume', 'stop', 'cancel'.
  final List<String> calls = [];
  core.Recording? stopResult;

  void emit(core.RecorderStatus status) {
    _status = status;
    _ctrl.add(status);
  }

  @override
  core.RecorderStatus get status => _status;

  @override
  Stream<core.RecorderStatus> get statusStream => Stream.multi((c) {
    c.add(_status);
    final sub = _ctrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  @override
  Future<core.AudioSupport> checkSupport({
    bool requestPermission = false,
  }) async {
    calls.add(requestPermission ? 'checkSupport(request)' : 'checkSupport');
    return support;
  }

  @override
  Future<void> start({
    required core.RecordingId recordingId,
    required core.NoteId noteId,
  }) async => calls.add('start:$recordingId');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<core.Recording?> stop() async {
    calls.add('stop');
    return stopResult;
  }

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  int? offsetNowMs() => null;

  @override
  Future<List<core.RecordingDraft>> pendingDrafts() async => const [];

  @override
  Future<core.Recording?> recoverDraft(String draftId) async => null;
}

final class PanelWorld {
  PanelWorld._(this.store, this.recorder, this.playback, this.noteId);

  /// A fake store with one note. [scripted] → a ScriptedRecorder instead of the CORE fake.
  static Future<PanelWorld> create({
    core.AudioSupport support = core.AudioSupport.supported,
    bool scripted = false,
    bool consentShown = true,
  }) async {
    final store = core_testing.createFakeNoteStore();
    final core.AudioRecorderService recorder = scripted
        ? ScriptedRecorder(support: support)
        : core_testing.FakeAudioRecorder(store: store, support: support);
    final note = await store.library.createNote(title: 'Lecture');
    if (consentShown) {
      await store.settings.set(MediaSettingKeys.consentShown, true);
    }
    return PanelWorld._(
      store,
      recorder,
      core_testing.FakeAudioPlayback(),
      note.id,
    );
  }

  final core.NoteStore store;
  final core.AudioRecorderService recorder;
  final core_testing.FakeAudioPlayback playback;
  final core.NoteId noteId;
  final ValueNotifier<bool> tapToSeek = ValueNotifier(false);
  final List<bool> tapToSeekChanges = [];
  int closes = 0;

  core_testing.FakeAudioRecorder get fakeRecorder =>
      recorder as core_testing.FakeAudioRecorder;
  ScriptedRecorder get scripted => recorder as ScriptedRecorder;

  /// A recording row (with an audio asset) of [noteId] (default: this world's note).
  Future<core.Recording> seedRecording({
    required String id,
    required int startedAt,
    int durationMs = 60000,
    core.NoteId? noteId,
  }) async {
    final asset = await store.assets.put(
      utf8.encode('audio:$id'),
      type: core.AssetType.audio,
      mimeType: 'audio/mp4',
    );
    return store.recordings.createRecording(
      id: id,
      noteId: noteId ?? this.noteId,
      assetId: asset.id,
      durationMs: durationMs,
      startedAt: startedAt,
    );
  }

  Widget app({double? width}) => ProviderScope(
    key: ObjectKey(this),
    overrides: [
      core.noteStoreProvider.overrideWithValue(store),
      core.audioRecorderServiceProvider.overrideWithValue(recorder),
      core.audioPlaybackServiceProvider.overrideWithValue(playback),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final size = MediaQuery.sizeOf(context);
            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: width ?? size.width,
                height: size.height * 0.4,
                child: RecordingPanel(
                  noteId: noteId,
                  tapToSeek: tapToSeek,
                  onTapToSeekChanged: tapToSeekChanges.add,
                  onClose: () => closes++,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  /// Pumps the panel on an iPad Pro 13" and lets the first statuses / list arrive.
  Future<void> pump(
    WidgetTester tester, {
    bool landscape = false,
    double? width,
  }) async {
    await pumpOnIpad(tester, app(width: width), landscape: landscape);
    await settle(tester);
  }

  void dispose() => tapToSeek.dispose();
}

/// A few frames for streams, post-frame callbacks and the fake store (no animations wait).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
