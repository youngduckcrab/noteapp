// m5-7/04-editor 8.2 E2-16 (6.15.1 — contract 7.2.4 R-1, R-2; E-5):
// RecordingLink.metaFor on CORE's FakeAudioRecorder (no real time — the
// recorder clock moves only by advance()).
import 'package:feature_editor/src/playback/recording_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

const _note = 'note-a';
const _other = 'note-b';
const _empty = ink.InkStrokeMeta();

ink.InkStrokeMeta _meta(
  FakeAudioRecorder r, {
  String noteId = _note,
  core.PenTool tool = core.PenTool.ballpoint,
}) => RecordingLink.metaFor(r, noteId, tool);

void main() {
  late core.NoteStore store;
  late FakeAudioRecorder recorder;

  setUp(() {
    store = createFakeNoteStore();
    recorder = FakeAudioRecorder(store: store);
  });
  tearDown(() => store.close());

  test('idle → empty meta', () {
    expect(recorder.status.phase, core.RecorderPhase.idle);
    expect(_meta(recorder), _empty);
  });

  test('recording this note → meta(recordingId, offsetNowMs())', () async {
    await recorder.start(recordingId: 'rec-1', noteId: _note);
    expect(recorder.status.phase, core.RecorderPhase.recording);
    expect(
      _meta(recorder),
      const ink.InkStrokeMeta(recordingId: 'rec-1', recordingOffsetMs: 0),
    );
    recorder.advance(const Duration(milliseconds: 1234));
    expect(
      _meta(recorder),
      const ink.InkStrokeMeta(recordingId: 'rec-1', recordingOffsetMs: 1234),
    );
    // Every pen tool but the laser links.
    for (final tool in core.PenTool.values) {
      if (tool == core.PenTool.laser) continue;
      expect(_meta(recorder, tool: tool).recordingId, 'rec-1', reason: '$tool');
    }
  });

  test('paused (by the user or interrupted) → empty meta', () async {
    await recorder.start(recordingId: 'rec-1', noteId: _note);
    recorder.advance(const Duration(seconds: 2));
    await recorder.pause();
    expect(recorder.status.phase, core.RecorderPhase.paused);
    expect(_meta(recorder), _empty);
    await recorder.resume();
    expect(_meta(recorder).recordingOffsetMs, 2000);
    recorder.interrupt();
    expect(recorder.status.interrupted, isTrue);
    expect(_meta(recorder), _empty);
  });

  test('another note records → empty meta (U12)', () async {
    await recorder.start(recordingId: 'rec-1', noteId: _other);
    recorder.advance(const Duration(seconds: 1));
    expect(_meta(recorder), _empty);
    expect(_meta(recorder, noteId: _other).recordingId, 'rec-1');
  });

  test('advance → the offset grows; a pause is left out of the audio '
      'timeline (R-2)', () async {
    await recorder.start(recordingId: 'rec-1', noteId: _note);
    recorder.advance(const Duration(milliseconds: 1500));
    expect(_meta(recorder).recordingOffsetMs, 1500);
    await recorder.pause();
    recorder.advance(const Duration(seconds: 30)); // paused: not counted
    await recorder.resume();
    expect(_meta(recorder).recordingOffsetMs, 1500);
    recorder.advance(const Duration(milliseconds: 700));
    expect(_meta(recorder).recordingOffsetMs, 2200);
  });

  test('laser → empty meta even while recording this note', () async {
    await recorder.start(recordingId: 'rec-1', noteId: _note);
    recorder.advance(const Duration(seconds: 1));
    expect(_meta(recorder, tool: core.PenTool.laser), _empty);
  });

  test('finishing (stop in progress) and after stop → empty meta', () async {
    // stop() stores the Recording row, so the note must exist.
    final note = await store.library.createNote(
      title: 'n',
      pages: const [core.PageDraft.blankA4],
    );
    await recorder.start(recordingId: 'rec-1', noteId: note.id);
    recorder.advance(const Duration(seconds: 1));
    expect(_meta(recorder, noteId: note.id).recordingOffsetMs, 1000);
    final stopping = recorder.stop();
    expect(recorder.status.phase, core.RecorderPhase.finishing);
    expect(_meta(recorder, noteId: note.id), _empty);
    final recording = await stopping;
    expect(recording?.id, 'rec-1');
    expect(recorder.status.phase, core.RecorderPhase.idle);
    expect(_meta(recorder, noteId: note.id), _empty);
  });
}
