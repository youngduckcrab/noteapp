// media_io → editor slots (docs/plans/m5-7/01-infra.md 4.6.5, 6.5.2, 6.7;
// contract 7.2.12 / 7.3.3). The recording panel gets the panel context, the
// image importer exists only with sources (outside FEATURE_MEDIA — D2-15),
// the media dev section reads media_io's lines, and the draft recovery
// follows pendingDrafts() alone (oldest first, failures logged, the status
// never read — contract 7.2.4 v2.1 'UI only').
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/media_wiring.dart';

final class _FakeBuildContext extends Fake implements BuildContext {}

RecordingDraft _draft(String id, int startedAt) => RecordingDraft(
  draftId: 'd-$id',
  recordingId: id,
  noteId: 'n1',
  mimeType: 'audio/mp4',
  startedAt: startedAt,
  chunkCount: 1,
  bytes: 16,
  activeMs: 1000,
  updatedAt: startedAt + 1000,
);

/// pendingDrafts() → [drafts] as given; recoverDraft answers from
/// [results] (a Recording, null = nothing to keep, or an Error to throw).
/// Reading the status is a test failure: recovery must not look at it.
final class _ScriptedRecorder extends Fake implements AudioRecorderService {
  _ScriptedRecorder(this.drafts, this.results);

  final List<RecordingDraft> drafts;
  final Map<String, Object?> results;
  final List<String> recoverCalls = [];

  @override
  RecorderStatus get status =>
      throw TestFailure('recovery read status (contract 7.2.4: UI only)');

  @override
  Future<List<RecordingDraft>> pendingDrafts() async => drafts;

  @override
  Future<Recording?> recoverDraft(String draftId) async {
    recoverCalls.add(draftId);
    final result = results[draftId];
    if (result is Error) throw result;
    return result as Recording?;
  }
}

Recording _recording(String id) => Recording(
  id: id,
  noteId: 'n1',
  assetId: 'a-$id',
  durationMs: 1000,
  startedAt: 1,
  createdAt: 1,
  updatedAt: 1,
  title: '복구된 녹음',
);

void main() {
  test('mediaRecordingPanel → RecordingPanel(noteId, tapToSeek, '
      'onTapToSeekChanged: setTapToSeek, onClose: close)', () {
    final tapToSeek = ValueNotifier<bool>(true);
    addTearDown(tapToSeek.dispose);
    void setTapToSeek(bool value) {}
    void close() {}
    final widget = mediaRecordingPanel(
      _FakeBuildContext(),
      EditorPanelContext(
        noteId: 'n1',
        tapToSeek: tapToSeek,
        setTapToSeek: setTapToSeek,
        close: close,
      ),
    );
    expect(widget, isA<RecordingPanel>());
    final panel = widget as RecordingPanel;
    expect(panel.noteId, 'n1');
    expect(panel.tapToSeek, same(tapToSeek));
    expect(panel.onTapToSeekChanged, setTapToSeek);
    expect(panel.onClose, close);
  });

  test('mediaImageImporterOrNull: no sources → null (image insert hidden, '
      'E-7); with sources → those sources and importImageForNote', () {
    final sources = supportedImageSources();
    final importer = mediaImageImporterOrNull();
    if (sources.isEmpty) {
      // media_io before PDF's image work (R2-B4) and any platform without a
      // picker.
      expect(importer, isNull);
    } else {
      expect(importer!.sources, sources);
      expect(importer.pick, importImageForNote);
      expect(
        () => importer.sources.add(ImageImportSource.files),
        throwsUnsupportedError,
      );
    }
  });

  test('mediaDevOverlaySection: id media, title 녹음, the lines of '
      'mediaDevOverlayLinesProvider', () {
    final section = Provider<DevOverlaySection>(
      mediaDevOverlaySection,
      name: '_mediaSection',
    );
    final container = ProviderContainer.test();
    final value = container.read(section);
    expect((value.id, value.title), ('media', '녹음'));
    expect(value.lines, same(container.read(mediaDevOverlayLinesProvider)));
  });

  group('recoverPendingRecordings (6.5.2)', () {
    test('no drafts → 0, nothing logged', () async {
      final recorder = _ScriptedRecorder(const [], const {});
      final log = AppErrorLog();
      expect(await recoverPendingRecordings(recorder, log), 0);
      expect(recorder.recoverCalls, isEmpty);
      expect(log.totalCount, 0);
    });

    test('oldest first (startedAt), whatever order pendingDrafts() gives; '
        'the count leaves out drafts with nothing to keep (null)', () async {
      final recorder = _ScriptedRecorder(
        [_draft('late', 300), _draft('first', 100), _draft('empty', 200)],
        {'d-late': _recording('late'), 'd-first': _recording('first')},
      );
      final log = AppErrorLog();
      expect(await recoverPendingRecordings(recorder, log), 2);
      expect(recorder.recoverCalls, ['d-first', 'd-empty', 'd-late']);
      expect(log.totalCount, 0);
    });

    test('a failing draft → one record (source module, draft id), the next '
        'still runs', () async {
      final recorder = _ScriptedRecorder(
        [_draft('a', 1), _draft('b', 2), _draft('c', 3)],
        {
          'd-a': _recording('a'),
          'd-b': StateError('chunks missing'),
          'd-c': _recording('c'),
        },
      );
      final log = AppErrorLog();
      expect(await recoverPendingRecordings(recorder, log), 2);
      expect(recorder.recoverCalls, ['d-a', 'd-b', 'd-c']);
      final record = log.records.single;
      expect(record.source, AppErrorSource.module);
      expect(
        record.summary,
        'recoverDraft d-b failed: Bad state: chunks missing',
      );
      expect(record.stackTrace, isNotNull);
    });
  });
}
