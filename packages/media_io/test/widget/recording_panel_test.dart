// PDF T36a — RecordingPanel ① (m5-7/06-pdf 6.13.1–6.13.4): the 6.13.2 rows for the recording
// row / status line / playback row, the 6.13.3 actions (open on show and after stop = open
// only — PDF-M8, start with consent, pause / resume, playback controls, tap-to-seek toggle,
// close), iPad Pro 13" portrait and landscape in the 40 % slot (no overflow, tap-target
// guidelines) and the narrow layout. CORE FakeAudioRecorder / FakeAudioPlayback + the fake
// store; a ScriptedRecorder for statuses the CORE fake cannot reach.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/ui/playback_bar.dart';
import 'package:media_io/src/ui/record_controls.dart';
import 'package:media_io/src/ui/strings_ko.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/ipad.dart';
import '../support/panel_world.dart';

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<ButtonStyleButton>(f).onPressed != null;

IconButton _icon(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first,
    );

/// Bottom sheet open / close animations (no pumpAndSettle: the playback ticker may run).
Future<void> _sheetFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

Future<void> _cancel(WidgetTester tester, PanelWorld w) async {
  unawaited(w.recorder.cancel());
  await settle(tester);
}

const core.RecorderStatus _recording = core.RecorderStatus(
  phase: core.RecorderPhase.recording,
  recordingId: 'r-live',
  noteId: 'n-other',
  activeMs: 4000,
);

void main() {
  group('6.13.2 rows', () {
    testWidgets('idle: [녹음] and the fixed consent line', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.pump(tester);
      expect(_button(MediaStringsKo.record), findsOneWidget);
      expect(_enabled(tester, _button(MediaStringsKo.record)), isTrue);
      expect(find.text('다른 사람의 목소리를 녹음할 때는 미리 동의를 받아 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(MediaStringsKo.recordSemantics),
        findsOneWidget,
      );
      expect(find.byType(PlaybackBar), findsNothing, reason: 'nothing open');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'unsupported: record disabled, text; list playback still works',
      (tester) async {
        final w = await PanelWorld.create(
          support: core.AudioSupport.unsupported,
        );
        addTearDown(w.dispose);
        await w.seedRecording(id: 'r1', startedAt: 1000);
        await w.pump(tester);
        expect(_enabled(tester, _button(MediaStringsKo.record)), isFalse);
        expect(find.text('이 기기에서 녹음할 수 없어요'), findsOneWidget);
        expect(_icon(tester, MediaStringsKo.play).onPressed, isNotNull);
      },
    );

    testWidgets('permission denied: record asks again, the native text', (
      tester,
    ) async {
      final w = await PanelWorld.create(
        support: core.AudioSupport.permissionDenied,
        scripted: true,
      );
      addTearDown(w.dispose);
      await w.pump(tester);
      expect(
        find.text('마이크 권한이 없어요. 설정 → 필기노트 → 마이크에서 허용해 주세요.'),
        findsOneWidget,
      );
      expect(_enabled(tester, _button(MediaStringsKo.record)), isTrue);
      await tester.tap(_button(MediaStringsKo.record));
      await settle(tester);
      expect(w.scripted.calls, ['checkSupport', 'checkSupport(request)']);
    });

    testWidgets('starting / finishing: progress and the texts', (tester) async {
      final w = await PanelWorld.create(scripted: true);
      addTearDown(w.dispose);
      await w.pump(tester);
      w.scripted.emit(
        core.RecorderStatus(
          phase: core.RecorderPhase.starting,
          recordingId: 'r',
          noteId: w.noteId,
        ),
      );
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('녹음을 준비하고 있어요…'), findsOneWidget);
      w.scripted.emit(
        core.RecorderStatus(
          phase: core.RecorderPhase.finishing,
          recordingId: 'r',
          noteId: w.noteId,
        ),
      );
      await settle(tester);
      expect(find.text('녹음을 저장하고 있어요…'), findsOneWidget);
    });

    testWidgets(
      'recording (this note): [일시정지][정지], clock, 녹음 중; playback disabled',
      (tester) async {
        final w = await PanelWorld.create();
        addTearDown(w.dispose);
        final r1 = await w.seedRecording(id: 'r1', startedAt: 1000);
        await w.pump(tester);
        await tester.tap(_button(MediaStringsKo.record));
        await settle(tester);
        expect(w.recorder.status.phase, core.RecorderPhase.recording);
        w.fakeRecorder.advance(const Duration(seconds: 3));
        await settle(tester);
        expect(_button(MediaStringsKo.pause), findsOneWidget);
        expect(_button(MediaStringsKo.stop), findsOneWidget);
        expect(find.text('00:03'), findsOneWidget);
        expect(find.text(MediaStringsKo.recordingNow), findsOneWidget);
        // the panel opened r1 on show; while recording the row stays but is disabled
        expect(w.playback.calls, ['open:${r1.id}']);
        final play = _icon(tester, MediaStringsKo.noPlayWhileRecording);
        expect(play.onPressed, isNull);
        expect(_icon(tester, MediaStringsKo.back10).onPressed, isNull);
        await _cancel(tester, w);
      },
    );

    testWidgets('paused by a hidden tab: [이어서][정지] + [이어서 녹음]', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.pump(tester);
      await tester.tap(_button(MediaStringsKo.record));
      await settle(tester);
      w.fakeRecorder
        ..advance(const Duration(seconds: 2))
        ..interrupt();
      await settle(tester);
      expect(find.text('화면을 벗어나 녹음이 멈췄어요. 이어서 녹음할까요?'), findsOneWidget);
      expect(_button(MediaStringsKo.resume), findsOneWidget);
      expect(_button(MediaStringsKo.stop), findsOneWidget);
      await tester.tap(
        find.widgetWithText(TextButton, MediaStringsKo.resumeRecording),
      );
      await settle(tester);
      expect(w.recorder.status.phase, core.RecorderPhase.recording);
      expect(find.text(MediaStringsKo.hiddenTab), findsNothing);
      await _cancel(tester, w);
    });

    for (final (code, text) in [
      (MediaErrorCode.microphoneLost, '마이크가 끊겨 이어서 녹음할 수 없어요. 정지해서 저장해 주세요.'),
      (MediaErrorCode.storageBacklog, '저장이 밀려 녹음을 멈췄어요'),
    ]) {
      testWidgets('paused by ${code.name}: [정지] only', (tester) async {
        final w = await PanelWorld.create(scripted: true);
        addTearDown(w.dispose);
        await w.pump(tester);
        w.scripted.emit(
          core.RecorderStatus(
            phase: core.RecorderPhase.paused,
            recordingId: 'r',
            noteId: w.noteId,
            activeMs: 61000,
            interrupted: true,
            error: MediaIoException(code),
          ),
        );
        await settle(tester);
        expect(find.text(text), findsOneWidget);
        expect(_button(MediaStringsKo.stop), findsOneWidget);
        expect(_button(MediaStringsKo.resume), findsNothing);
        expect(_button(MediaStringsKo.pause), findsNothing);
        expect(find.text('01:01'), findsOneWidget);
      });
    }

    testWidgets('another note records: record disabled + [그 녹음 정지]', (
      tester,
    ) async {
      final w = await PanelWorld.create(scripted: true);
      addTearDown(w.dispose);
      final mine = await w.seedRecording(id: 'mine', startedAt: 5);
      await w.pump(tester);
      w.scripted.emit(_recording);
      await settle(tester);
      expect(find.text('다른 노트에서 녹음 중이에요'), findsOneWidget);
      expect(_enabled(tester, _button(MediaStringsKo.record)), isFalse);
      expect(w.playback.calls, ['open:${mine.id}']);
      w.scripted.stopResult = core.Recording(
        id: 'r-live',
        noteId: 'n-other',
        assetId: 'a',
        durationMs: 4000,
        startedAt: 9,
        createdAt: 9,
        updatedAt: 9,
      );
      await tester.tap(_button(MediaStringsKo.stopOther));
      await settle(tester);
      expect(w.scripted.calls.last, 'stop');
      expect(w.playback.calls, [
        'open:${mine.id}',
      ], reason: 'the other note\'s recording is not opened here');
    });

    for (final (code, text) in [
      (MediaErrorCode.saveFailed, '녹음을 저장하지 못했어요. 앱을 다시 열면 복구해요.'),
      (
        MediaErrorCode.draftLost,
        '다른 창에서 이 녹음을 정리했어요. 지금까지의 녹음은 그 창의 녹음 목록에 있어요.',
      ),
    ]) {
      testWidgets('idle with ${code.name}: [녹음] + text', (tester) async {
        final w = await PanelWorld.create(scripted: true);
        addTearDown(w.dispose);
        await w.pump(tester);
        w.scripted.emit(core.RecorderStatus(error: MediaIoException(code)));
        await settle(tester);
        expect(find.text(text), findsOneWidget);
        expect(_enabled(tester, _button(MediaStringsKo.record)), isTrue);
      });
    }

    test('statusLineFor: web texts and the format warning (pure)', () {
      const noteId = 'n';
      core.RecorderStatus st(core.RecorderPhase p, {bool playable = true}) =>
          core.RecorderStatus(
            phase: p,
            recordingId: 'r',
            noteId: noteId,
            crossPlatformPlayable: playable,
          );
      String? text(
        core.RecorderStatus s, {
        core.AudioSupport? support,
        Object? local,
        bool web = true,
      }) => statusLineFor(
        status: s,
        noteId: noteId,
        support: support,
        localError: local,
        web: web,
      ).text;

      expect(
        text(st(core.RecorderPhase.recording, playable: false)),
        '이 브라우저 녹음은 아이패드 앱에서 재생되지 않을 수 있어요',
      );
      expect(
        text(st(core.RecorderPhase.recording, playable: false), web: false),
        isNull,
      );
      expect(
        text(
          const core.RecorderStatus(),
          support: core.AudioSupport.unsupported,
        ),
        '이 브라우저에서는 녹음할 수 없어요',
      );
      expect(
        text(
          const core.RecorderStatus(),
          support: core.AudioSupport.permissionPermanentlyDenied,
        ),
        '브라우저에서 이 사이트의 마이크 사용을 허용해 주세요.',
      );
      expect(
        text(
          const core.RecorderStatus(),
          local: const MediaIoException(MediaErrorCode.microphoneNotFound),
        ),
        '마이크를 찾지 못했어요',
      );
      expect(
        text(
          const core.RecorderStatus(),
          local: const MediaIoException(MediaErrorCode.microphoneBusy),
        ),
        '다른 앱이 마이크를 쓰고 있어요',
      );
      expect(
        recordRowMode(
          const core.RecorderStatus(
            phase: core.RecorderPhase.paused,
            noteId: noteId,
          ),
          noteId,
          null,
        ),
        RecordRowMode.pausedResumable,
        reason: 'paused by the user',
      );
      expect(nextPlaybackSpeed(1.0), 1.25);
      expect(nextPlaybackSpeed(2.0), 0.5);
      expect(nextPlaybackSpeed(0.9), 1.0);
      expect(
        [
          for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            MediaStringsKo.speedLabel(s),
        ],
        ['0.5×', '0.75×', '1.0×', '1.25×', '1.5×', '2.0×'],
      );
    });
  });

  group('6.13.3 actions', () {
    testWidgets('on show: open the most recent recording only (PDF-M8)', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'old', startedAt: 1000);
      await w.seedRecording(id: 'new', startedAt: 2000);
      final other = await w.store.library.createNote(title: 'Other');
      await w.seedRecording(id: 'other', startedAt: 3000, noteId: other.id);
      await w.pump(tester);
      expect(w.playback.calls, ['open:new']);
      expect(w.playback.positionMs(), 0);
      expect(w.playback.status.phase, core.PlaybackPhase.ready);
      expect(find.byType(PlaybackBar), findsOneWidget);
      expect(find.text('00:00 / 01:00'), findsOneWidget);
    });

    testWidgets(
      'on show: nothing when this note\'s recording is open already',
      (tester) async {
        final w = await PanelWorld.create();
        addTearDown(w.dispose);
        final old = await w.seedRecording(id: 'old', startedAt: 1000);
        await w.seedRecording(id: 'new', startedAt: 2000);
        await w.playback.open(old);
        await w.pump(tester);
        expect(w.playback.calls, ['open:old']);
      },
    );

    testWidgets('on show: nothing while recording, nothing for an empty list', (
      tester,
    ) async {
      final w = await PanelWorld.create(scripted: true);
      addTearDown(w.dispose);
      await w.seedRecording(id: 'r', startedAt: 1);
      w.scripted.emit(
        core.RecorderStatus(
          phase: core.RecorderPhase.recording,
          recordingId: 'x',
          noteId: w.noteId,
        ),
      );
      await w.pump(tester);
      expect(w.playback.calls, isEmpty);

      final empty = await PanelWorld.create();
      addTearDown(empty.dispose);
      await empty.pump(tester);
      expect(empty.playback.calls, isEmpty);
    });

    testWidgets('정지 직후 흐림 없음: stop → open:<id> only, position 0, ready', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.pump(tester);
      expect(w.playback.calls, isEmpty);
      await tester.tap(_button(MediaStringsKo.record));
      await settle(tester);
      final id = w.recorder.status.recordingId!;
      w.fakeRecorder.advance(
        const Duration(seconds: 3),
      ); // strokes written meanwhile
      await settle(tester);
      await tester.tap(_button(MediaStringsKo.stop));
      await settle(tester);
      expect(w.recorder.status.phase, core.RecorderPhase.idle);
      expect(w.playback.calls, ['open:$id']);
      expect(w.playback.positionMs(), 0);
      expect(w.playback.status.phase, core.PlaybackPhase.ready);
      expect(w.playback.status.durationMs, 3000);
      expect(find.byType(PlaybackBar), findsOneWidget);
    });

    testWidgets('first record: the consent sheet, then the key and start', (
      tester,
    ) async {
      final w = await PanelWorld.create(consentShown: false);
      addTearDown(w.dispose);
      final r = await w.seedRecording(id: 'r', startedAt: 1);
      await w.pump(tester);
      await w.playback.play();
      await settle(tester);
      await tester.tap(_button(MediaStringsKo.record));
      await _sheetFrames(tester);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('다른 사람의 목소리를 녹음할 때는 미리 동의를 받아 주세요.'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, MediaStringsKo.startRecording),
      );
      await _sheetFrames(tester);
      expect(await w.store.settings.get(MediaSettingKeys.consentShown), isTrue);
      expect(w.recorder.status.phase, core.RecorderPhase.recording);
      expect(w.recorder.status.noteId, w.noteId);
      expect(w.recorder.status.recordingId, isNotEmpty);
      // playback paused before start (6.13.3 ③)
      expect(w.playback.calls, ['open:${r.id}', 'play', 'pause']);
      await _cancel(tester, w);
    });

    testWidgets('consent cancelled: no start, the key stays false', (
      tester,
    ) async {
      final w = await PanelWorld.create(consentShown: false);
      addTearDown(w.dispose);
      await w.pump(tester);
      await tester.tap(_button(MediaStringsKo.record));
      await _sheetFrames(tester);
      await tester.tap(find.widgetWithText(TextButton, MediaStringsKo.cancel));
      await _sheetFrames(tester);
      expect(w.recorder.status.phase, core.RecorderPhase.idle);
      expect(
        await w.store.settings.get(MediaSettingKeys.consentShown),
        isFalse,
      );
    });

    testWidgets('pause / resume buttons', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.pump(tester);
      await tester.tap(_button(MediaStringsKo.record));
      await settle(tester);
      await tester.tap(_button(MediaStringsKo.pause));
      await settle(tester);
      expect(w.recorder.status.phase, core.RecorderPhase.paused);
      expect(w.recorder.status.interrupted, isFalse);
      expect(find.text(MediaStringsKo.hiddenTab), findsNothing);
      await tester.tap(_button(MediaStringsKo.resume));
      await settle(tester);
      expect(w.recorder.status.phase, core.RecorderPhase.recording);
      await _cancel(tester, w);
    });

    testWidgets('playback row: play / pause, ±10 s, scrubber, speed cycle', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'r', startedAt: 1);
      await w.pump(tester);
      await tester.tap(find.byTooltip(MediaStringsKo.play));
      await settle(tester);
      expect(w.playback.status.phase, core.PlaybackPhase.playing);
      await tester.tap(find.byTooltip(MediaStringsKo.forward10));
      await settle(tester);
      await tester.tap(find.byTooltip(MediaStringsKo.forward10));
      await settle(tester);
      await tester.tap(find.byTooltip(MediaStringsKo.back10));
      await settle(tester);
      await tester.tap(find.byTooltip(MediaStringsKo.pausePlayback));
      await settle(tester);
      expect(w.playback.calls, [
        'open:r',
        'play',
        'seek:10000',
        'seek:20000',
        'seek:10000',
        'pause',
      ]);
      expect(find.text('00:10 / 01:00'), findsOneWidget);

      // scrubber: dragging moves only the thumb; the seek comes on release
      final before = w.playback.calls.length;
      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(w.playback.calls.length, before, reason: 'no seek while dragging');
      await gesture.up();
      await settle(tester);
      expect(w.playback.calls.length, before + 1);
      expect(w.playback.calls.last, startsWith('seek:'));

      await tester.tap(find.text('1.0×'));
      await settle(tester);
      await tester.tap(find.text('1.25×'));
      await settle(tester);
      expect(w.playback.calls.sublist(w.playback.calls.length - 2), [
        'speed:1.25',
        'speed:1.5',
      ]);
      expect(find.text('1.5×'), findsOneWidget);
    });

    testWidgets(
      'position text follows positionMs() every 200 ms while playing',
      (tester) async {
        final w = await PanelWorld.create();
        addTearDown(w.dispose);
        await w.seedRecording(id: 'r', startedAt: 1);
        await w.pump(tester);
        await tester.tap(find.byTooltip(MediaStringsKo.play));
        await settle(tester);
        w.playback.setPositionMs(12000);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.text('00:12 / 01:00'), findsOneWidget);
        w.playback.setPositionMs(13000);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('00:12 / 01:00'), findsOneWidget, reason: '< 200 ms');
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('00:13 / 01:00'), findsOneWidget);
        await tester.tap(find.byTooltip(MediaStringsKo.pausePlayback));
        await settle(tester);
      },
    );

    testWidgets(
      'tap-to-seek toggle reports the flip; the panel keeps no value',
      (tester) async {
        final w = await PanelWorld.create();
        addTearDown(w.dispose);
        await w.seedRecording(id: 'r', startedAt: 1);
        await w.pump(tester);
        await tester.tap(find.byTooltip(MediaStringsKo.tapToSeek));
        await settle(tester);
        expect(w.tapToSeekChanges, [true]);
        expect(_icon(tester, MediaStringsKo.tapToSeek).isSelected, isFalse);
        w.tapToSeek.value = true; // EDITOR stores it
        await settle(tester);
        expect(_icon(tester, MediaStringsKo.tapToSeek).isSelected, isTrue);
        await tester.tap(find.byTooltip(MediaStringsKo.tapToSeek));
        await settle(tester);
        expect(w.tapToSeekChanges, [true, false]);
      },
    );

    testWidgets('close: onClose, the recording goes on', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.pump(tester);
      await tester.tap(_button(MediaStringsKo.record));
      await settle(tester);
      await tester.tap(find.byTooltip(MediaStringsKo.close));
      await settle(tester);
      expect(w.closes, 1);
      expect(w.recorder.status.phase, core.RecorderPhase.recording);
      await _cancel(tester, w);
    });
  });

  group('layout', () {
    for (final landscape in [false, true]) {
      testWidgets(
        'iPad 13" ${landscape ? 'landscape' : 'portrait'}: 40 % slot, no overflow, guidelines',
        (tester) async {
          final w = await PanelWorld.create();
          addTearDown(w.dispose);
          await w.seedRecording(id: 'r', startedAt: 1);
          await w.pump(tester, landscape: landscape);
          final size = landscape ? ipad13Landscape : ipad13Portrait;
          expect(
            tester.getSize(find.byType(RecordControls)).width,
            lessThanOrEqualTo(size.width),
          );
          expect(tester.takeException(), isNull);
          await expectTapTargetGuidelines(tester);
          // recording state too
          await tester.tap(_button(MediaStringsKo.record));
          await settle(tester);
          expect(tester.takeException(), isNull);
          await expectTapTargetGuidelines(tester);
          await _cancel(tester, w);
        },
      );
    }

    testWidgets('narrow (< 600): speed and tap-to-seek on a second line', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'r', startedAt: 1);
      await w.pump(tester, width: 500);
      expect(tester.takeException(), isNull);
      final play = tester.getCenter(find.byTooltip(MediaStringsKo.play));
      final speed = tester.getCenter(find.text('1.0×'));
      expect(speed.dy, greaterThan(play.dy + 20));

      final wide = await PanelWorld.create();
      addTearDown(wide.dispose);
      await wide.seedRecording(id: 'r', startedAt: 1);
      await wide.pump(tester, width: 800);
      final play2 = tester.getCenter(find.byTooltip(MediaStringsKo.play));
      final speed2 = tester.getCenter(find.text('1.0×'));
      expect((speed2.dy - play2.dy).abs(), lessThan(4));
    });
  });
}
