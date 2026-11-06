// PDF T36b — drafts that could not be recovered, draftLost and the web download (m5-7/06-pdf
// 6.10.3 · 6.10.4 · 6.13.2 · 6.13.4 last paragraph): media.recoverAttempts = 2 → the line shows →
// [다시 시도] sets the count back and calls pendingDrafts → recoverDraft; [⋯] → (web) the two-step
// download (prepare → [저장하기] saves synchronously inside the tap, the URL is revoked when the
// sheet closes; WebM gets its Duration patched) and [지우기] (confirm → discard); the failed-save
// download; the draftLost line.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/ui/strings_ko.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/panel_world.dart';

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

/// A draft of [noteId] with [bytes] and [attempts] in media.recoverAttempts.
Future<core.RecordingDraft> _draft(
  PanelWorld w, {
  String recordingId = 'rec-stuck',
  core.NoteId? noteId,
  String mimeType = 'audio/mp4',
  Uint8List? bytes,
  int attempts = 2,
}) async {
  final d = await w.store.recordingDrafts.begin(
    recordingId: recordingId,
    noteId: noteId ?? w.noteId,
    mimeType: mimeType,
    startedAt: DateTime(2026, 11, 5, 9, 30).millisecondsSinceEpoch,
  );
  await w.store.recordingDrafts.append(
    d.draftId,
    bytes ?? Uint8List.fromList(List.filled(3000, 7)),
    activeMs: 2000,
  );
  if (attempts > 0) {
    final all = await w.store.settings.get(MediaSettingKeys.recoverAttempts);
    await w.store.settings.set(MediaSettingKeys.recoverAttempts, {
      ...all,
      d.draftId: attempts,
    });
  }
  return (await w.store.recordingDrafts.listDrafts()).firstWhere(
    (x) => x.draftId == d.draftId,
  );
}

Finder get _line => find.text(MediaStringsKo.stuckDrafts);

Future<void> _openDraftMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip(MediaStringsKo.draftActions));
  await _frames(tester);
}

void main() {
  group('the stuck line', () {
    testWidgets('attempts 2 → the line with [다시 시도] and [⋯]', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await _draft(w);
      await w.pump(tester);
      expect(_line, findsOneWidget);
      expect(find.text(MediaStringsKo.retry), findsOneWidget);
      expect(find.byTooltip(MediaStringsKo.draftActions), findsOneWidget);
      // with the other rows (the idle consent line stays)
      expect(find.text(MediaStringsKo.consent), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('attempts 1, no attempts, or another note\'s draft → no line', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      final other = await w.store.library.createNote(title: 'Other');
      await _draft(w, recordingId: 'a', attempts: 1);
      await _draft(w, recordingId: 'b', attempts: 0);
      await _draft(w, recordingId: 'c', noteId: other.id);
      await w.pump(tester);
      expect(_line, findsNothing);
    });

    testWidgets(
      '[다시 시도] → count back to 0, then pendingDrafts → recoverDraft; the line goes',
      (tester) async {
        final w = await PanelWorld.create(scripted: true);
        addTearDown(w.dispose);
        final d = await _draft(w);
        w.scripted.pending = [d];
        w.scripted.onRecover = (id) async {
          // what a successful recovery does: the draft and its count go
          await w.store.recordingDrafts.discard(id);
          return null;
        };
        Map<String, Object?>? attemptsAtPending;
        w.scripted.beforePending = () async {
          attemptsAtPending = await w.store.settings.get(
            MediaSettingKeys.recoverAttempts,
          );
        };
        await w.pump(tester);
        w.scripted.calls.clear();
        await tester.tap(find.text(MediaStringsKo.retry));
        await settle(tester);
        expect(w.scripted.calls, [
          'pendingDrafts',
          'recoverDraft:${d.draftId}',
        ]);
        expect(
          await w.store.settings.get(MediaSettingKeys.recoverAttempts),
          isNot(contains(d.draftId)),
        );
        expect(attemptsAtPending, isNot(contains(d.draftId)));
        expect(_line, findsNothing);
      },
    );

    testWidgets(
      '[다시 시도] while the draft is still left out → no recoverDraft call',
      (tester) async {
        final w = await PanelWorld.create(scripted: true);
        addTearDown(w.dispose);
        await _draft(w);
        w.scripted.pending = const []; // e.g. another tab still holds its lock
        await w.pump(tester);
        w.scripted.calls.clear();
        await tester.tap(find.text(MediaStringsKo.retry));
        await settle(tester);
        expect(w.scripted.calls, ['pendingDrafts']);
        expect(
          _line,
          findsNothing,
          reason: 'the count is 0 now — automatic recovery again',
        );
      },
    );

    testWidgets('a failing recoverDraft is reported; the panel stays usable', (
      tester,
    ) async {
      final w = await PanelWorld.create(scripted: true);
      addTearDown(w.dispose);
      final d = await _draft(w);
      w.scripted.pending = [d];
      w.scripted.onRecover = (_) async => throw StateError('disk full');
      await w.pump(tester);
      await tester.tap(find.text(MediaStringsKo.retry));
      await settle(tester);
      final error = tester.takeException();
      expect(error, isA<StateError>());
      expect(
        find.text(MediaStringsKo.retry),
        findsNothing,
        reason: 'count 0 → not stuck',
      );
    });
  });

  group('[⋯] sheet', () {
    testWidgets('native (no download port): only [지우기]', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await _draft(w);
      await w.pump(tester);
      await _openDraftMenu(tester);
      expect(find.text(MediaStringsKo.discardDraft), findsOneWidget);
      expect(find.text(MediaStringsKo.downloadFile), findsNothing);
    });

    testWidgets('[지우기] → confirm text → discard; the count entry goes too', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      final d = await _draft(w);
      await w.pump(tester);
      await _openDraftMenu(tester);
      await tester.tap(find.text(MediaStringsKo.discardDraft));
      await _frames(tester);
      expect(find.text('이 녹음을 지울까요? 되돌릴 수 없어요.'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, MediaStringsKo.discardDraft),
      );
      await _frames(tester);
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
      expect(
        await w.store.settings.get(MediaSettingKeys.recoverAttempts),
        isNot(contains(d.draftId)),
      );
      expect(_line, findsNothing);
    });

    testWidgets('[지우기] then [취소] keeps the draft', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await _draft(w);
      await w.pump(tester);
      await _openDraftMenu(tester);
      await tester.tap(find.text(MediaStringsKo.discardDraft));
      await _frames(tester);
      await tester.tap(find.text(MediaStringsKo.cancel));
      await _frames(tester);
      expect(await w.store.recordingDrafts.listDrafts(), hasLength(1));
      expect(_line, findsOneWidget);
    });

    testWidgets(
      'web download, two steps: prepare → [저장하기] saves inside the tap → revoked on close',
      (tester) async {
        final downloads = FakeFileDownloads();
        final w = await PanelWorld.create(downloads: downloads);
        addTearDown(w.dispose);
        await _draft(w);
        await w.pump(tester);
        await _openDraftMenu(tester);
        expect(find.text(MediaStringsKo.discardDraft), findsOneWidget);
        await tester.tap(find.text(MediaStringsKo.downloadFile));
        await settle(tester);
        expect(downloads.log, ['prepare:녹음-20261105-0930.m4a:3000']);
        expect(find.text(MediaStringsKo.saveFile), findsOneWidget);
        await tester.tap(find.text(MediaStringsKo.saveFile));
        // synchronous in the tap: no pump between the tap and the save
        expect(downloads.log.last, 'save:녹음-20261105-0930.m4a');
        await settle(tester);
        await tester.tapAt(const Offset(20, 20)); // close the sheet (barrier)
        await _frames(tester);
        expect(downloads.log, [
          'prepare:녹음-20261105-0930.m4a:3000',
          'save:녹음-20261105-0930.m4a',
          'revoke:녹음-20261105-0930.m4a',
        ]);
        expect(
          await w.store.recordingDrafts.listDrafts(),
          hasLength(1),
          reason: 'downloading never deletes the draft',
        );
      },
    );

    testWidgets('a WebM draft is saved with its Duration patched (6.8.7)', (
      tester,
    ) async {
      final raw = File('test/support/fixtures/chrome_opus_r1.webm')
          .readAsBytesSync();
      final patched = File('test/support/fixtures/chrome_opus_r1_patched.webm')
          .readAsBytesSync();
      final downloads = FakeFileDownloads();
      final w = await PanelWorld.create(downloads: downloads);
      addTearDown(w.dispose);
      await _draft(w, mimeType: 'audio/webm;codecs=opus', bytes: raw);
      await w.pump(tester);
      await _openDraftMenu(tester);
      await tester.tap(find.text(MediaStringsKo.downloadFile));
      await settle(tester);
      expect(
        downloads.log.single,
        startsWith('prepare:녹음-20261105-0930.webm:'),
      );
      expect(downloads.prepared.single, patched);
    });
  });

  group('status line rows', () {
    testWidgets(
      'failed save on the web: [파일로 내려받기] for that recording\'s draft',
      (tester) async {
        final downloads = FakeFileDownloads();
        final w = await PanelWorld.create(scripted: true, downloads: downloads);
        addTearDown(w.dispose);
        await _draft(w, recordingId: 'live', attempts: 0);
        await w.pump(tester);
        w.scripted.emit(
          core.RecorderStatus(
            phase: core.RecorderPhase.idle,
            recordingId: 'live',
            noteId: w.noteId,
            error: const MediaIoException(MediaErrorCode.saveFailed),
          ),
        );
        await settle(tester);
        expect(find.text(MediaStringsKo.saveFailed), findsOneWidget);
        await tester.tap(find.text(MediaStringsKo.downloadFile));
        await settle(tester);
        expect(downloads.log, ['prepare:녹음-20261105-0930.m4a:3000']);
        await tester.tap(find.text(MediaStringsKo.saveFile));
        expect(downloads.log.last, 'save:녹음-20261105-0930.m4a');
        await settle(tester);
      },
    );

    testWidgets('failed save, native: no download button', (tester) async {
      final w = await PanelWorld.create(scripted: true);
      addTearDown(w.dispose);
      await w.pump(tester);
      w.scripted.emit(
        core.RecorderStatus(
          phase: core.RecorderPhase.idle,
          recordingId: 'live',
          noteId: w.noteId,
          error: const MediaIoException(MediaErrorCode.saveFailed),
        ),
      );
      await settle(tester);
      expect(find.text(MediaStringsKo.saveFailed), findsOneWidget);
      expect(find.text(MediaStringsKo.downloadFile), findsNothing);
    });

    testWidgets('draftLost: the other-window text; [녹음] stays', (tester) async {
      final w = await PanelWorld.create(scripted: true);
      addTearDown(w.dispose);
      await w.pump(tester);
      w.scripted.emit(
        const core.RecorderStatus(
          error: MediaIoException(MediaErrorCode.draftLost),
        ),
      );
      await settle(tester);
      expect(
        find.text('다른 창에서 이 녹음을 정리했어요. 지금까지의 녹음은 그 창의 녹음 목록에 있어요.'),
        findsOneWidget,
      );
      expect(find.text(MediaStringsKo.record), findsOneWidget);
    });
  });
}
