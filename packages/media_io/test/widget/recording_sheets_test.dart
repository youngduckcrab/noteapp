// PDF T36b — the panel's bottom sheets (m5-7/06-pdf 6.13.1 · 6.13.3, 7.4.10 '높이 ≤ 50%'): the
// consent sheet (fixed text, media.consentShown written on [녹음 시작] only), the name sheet
// (trimmed 1–100 characters, empty = the default name, cancel keeps the name) and the delete
// confirmation (deleteRecording; the open recording is closed first).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/ui/sheets.dart';
import 'package:media_io/src/ui/strings_ko.dart';

import '../support/panel_world.dart';

/// Sheet open / close animations (no pumpAndSettle: the playback ticker may run).
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

Finder _menuOf(String id) => find.descendant(
  of: find.byKey(ValueKey('recording-$id')),
  matching: find.byTooltip(MediaStringsKo.recordingActions),
);

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tester.tap(_menuOf(id));
  await _frames(tester);
}

void _expectHalfHeight(WidgetTester tester) {
  final sheet = tester.getRect(find.byType(BottomSheet).last);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(sheet.height, lessThanOrEqualTo(screen.height * 0.5 + 0.5));
}

void main() {
  group('consent sheet (6.13.3 ①)', () {
    testWidgets('fixed text; [녹음 시작] writes media.consentShown and starts', (
      tester,
    ) async {
      final w = await PanelWorld.create(consentShown: false);
      addTearDown(w.dispose);
      await w.pump(tester);
      await tester.tap(find.text(MediaStringsKo.record));
      await _frames(tester);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('다른 사람의 목소리를 녹음할 때는 미리 동의를 받아 주세요.'),
        ),
        findsOneWidget,
      );
      _expectHalfHeight(tester);
      await tester.tap(find.text(MediaStringsKo.startRecording));
      await _frames(tester);
      expect(await w.store.settings.get(MediaSettingKeys.consentShown), isTrue);
      expect(w.recorder.status.noteId, w.noteId);
      unawaited(w.recorder.cancel());
      await settle(tester);
    });

    testWidgets(
      '[취소] writes nothing and does not start; the sheet shows again next time',
      (tester) async {
        final w = await PanelWorld.create(consentShown: false);
        addTearDown(w.dispose);
        await w.pump(tester);
        await tester.tap(find.text(MediaStringsKo.record));
        await _frames(tester);
        await tester.tap(find.text(MediaStringsKo.cancel));
        await _frames(tester);
        expect(
          await w.store.settings.get(MediaSettingKeys.consentShown),
          isFalse,
        );
        expect(w.recorder.status.recordingId, isNull);
        await tester.tap(find.text(MediaStringsKo.record));
        await _frames(tester);
        expect(find.text(MediaStringsKo.startRecording), findsOneWidget);
      },
    );

    testWidgets('already shown on this device → no sheet', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.pump(tester);
      await tester.tap(find.text(MediaStringsKo.record));
      await _frames(tester);
      expect(find.byType(BottomSheet), findsNothing);
      unawaited(w.recorder.cancel());
      await settle(tester);
    });
  });

  group('name sheet', () {
    test('normalizeRecordingTitle: trimmed, ≤ 100 runes, empty → null', () {
      expect(normalizeRecordingTitle('  강의 1  '), '강의 1');
      expect(normalizeRecordingTitle('   '), isNull);
      expect(normalizeRecordingTitle(''), isNull);
      expect(normalizeRecordingTitle('가' * 100), '가' * 100);
      expect(normalizeRecordingTitle('가' * 130), '가' * 100);
      final emoji = '😀' * 101; // 2 UTF-16 units per rune
      expect(normalizeRecordingTitle(emoji)!.runes.length, 100);
    });

    testWidgets('rename: the new trimmed title is saved and shown', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'r1', startedAt: 10);
      await w.pump(tester);
      await _openMenu(tester, 'r1');
      _expectHalfHeight(tester);
      await tester.tap(find.text(MediaStringsKo.rename));
      await _frames(tester);
      await tester.enterText(find.byType(TextField), '  화학 강의  ');
      await tester.tap(find.text(MediaStringsKo.save));
      await _frames(tester);
      expect((await w.store.recordings.getRecording('r1'))!.title, '화학 강의');
      expect(find.text('화학 강의'), findsOneWidget);
    });

    testWidgets('an empty name → the default name (title null)', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'r1', startedAt: 10, title: '예전 이름');
      await w.pump(tester);
      await _openMenu(tester, 'r1');
      await tester.tap(find.text(MediaStringsKo.rename));
      await _frames(tester);
      expect(find.widgetWithText(TextField, '예전 이름'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text(MediaStringsKo.save));
      await _frames(tester);
      expect((await w.store.recordings.getRecording('r1'))!.title, isNull);
      expect(find.text('녹음 1'), findsOneWidget);
    });

    testWidgets(
      'the field takes at most 100 characters; cancel keeps the name',
      (tester) async {
        final w = await PanelWorld.create();
        addTearDown(w.dispose);
        await w.seedRecording(id: 'r1', startedAt: 10, title: '그대로');
        await w.pump(tester);
        await _openMenu(tester, 'r1');
        await tester.tap(find.text(MediaStringsKo.rename));
        await _frames(tester);
        expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 100);
        await tester.enterText(find.byType(TextField), '바뀐 이름');
        await tester.tap(find.text(MediaStringsKo.cancel));
        await _frames(tester);
        expect((await w.store.recordings.getRecording('r1'))!.title, '그대로');
      },
    );
  });

  group('delete', () {
    testWidgets('confirm text; [삭제] → deleteRecording, gone from the list', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'old', startedAt: 10);
      await w.seedRecording(id: 'new', startedAt: 20);
      await w.pump(tester);
      expect(w.playback.status.recordingId, 'new');
      await _openMenu(tester, 'old');
      await tester.tap(find.text(MediaStringsKo.delete));
      await _frames(tester);
      expect(find.text('이 녹음을 지울까요? 녹음과 함께 쓴 필기는 그대로 남아요.'), findsOneWidget);
      _expectHalfHeight(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(FilledButton, MediaStringsKo.delete),
        ),
      );
      await _frames(tester);
      expect((await w.store.recordings.getRecording('old'))!.isDeleted, isTrue);
      expect(find.byKey(const ValueKey('recording-old')), findsNothing);
      expect(w.playback.calls, [
        'open:new',
      ], reason: 'not the open one → no close');
    });

    testWidgets('deleting the open recording closes the player first', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'r1', startedAt: 10);
      await w.pump(tester);
      await _openMenu(tester, 'r1');
      await tester.tap(find.text(MediaStringsKo.delete));
      await _frames(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, MediaStringsKo.delete),
      );
      await _frames(tester);
      expect(w.playback.calls, ['open:r1', 'close']);
      expect((await w.store.recordings.getRecording('r1'))!.isDeleted, isTrue);
    });

    testWidgets('[취소] keeps the recording', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.seedRecording(id: 'r1', startedAt: 10);
      await w.pump(tester);
      await _openMenu(tester, 'r1');
      await tester.tap(find.text(MediaStringsKo.delete));
      await _frames(tester);
      await tester.tap(find.text(MediaStringsKo.cancel));
      await _frames(tester);
      expect((await w.store.recordings.getRecording('r1'))!.isDeleted, isFalse);
      expect(w.playback.calls, ['open:r1']);
    });
  });
}
