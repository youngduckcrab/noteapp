// PDF T36b — the recordings list of RecordingPanel (m5-7/06-pdf 6.13.1): names ('녹음 N' by
// startedAt order, title), the '복구됨' badge (title == MediaTuning.recoveredTitle — 6.10.1), the
// WebM warning, date · length · size (Asset.size) and the total (audioBytesOf), newest first, tap
// = open only (PDF-M8), iPad portrait / landscape in the 40 % slot. Pure helpers too.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/tuning.dart';
import 'package:media_io/src/ui/recording_list.dart';
import 'package:media_io/src/ui/strings_ko.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/ipad.dart';
import '../support/panel_world.dart';

core.Recording _rec(String id, int startedAt, {String? title}) =>
    core.Recording(
      id: id,
      noteId: 'n',
      assetId: 'a-$id',
      durationMs: 1000,
      startedAt: startedAt,
      createdAt: startedAt,
      updatedAt: startedAt,
      title: title,
    );

/// 2026-11-05 14:02 local.
final int _t1402 = DateTime(2026, 11, 5, 14, 2).millisecondsSinceEpoch;
final int _t0910 = DateTime(2026, 11, 5, 9, 10).millisecondsSinceEpoch;
final int _t0800 = DateTime(2026, 11, 4, 8, 0).millisecondsSinceEpoch;

Future<PanelWorld> _three() async {
  final w = await PanelWorld.create();
  await w.seedRecording(
    id: 'r1',
    startedAt: _t0800,
    durationMs: 180000,
    mimeType: 'audio/webm;codecs=opus',
    bytes: 1400000,
  );
  await w.seedRecording(
    id: 'r2',
    startedAt: _t0910,
    durationMs: 740000,
    bytes: 5600000,
    title: MediaTuning.recoveredTitle,
  );
  await w.seedRecording(
    id: 'r3',
    startedAt: _t1402,
    durationMs: 2700000,
    bytes: 20600000,
  );
  return w;
}

Finder _row(String id) => find.byKey(ValueKey('recording-$id'));

void main() {
  group('pure helpers', () {
    test(
      "recordingDisplayNames: title, else '녹음 N' by startedAt (then id)",
      () {
        final names = recordingDisplayNames([
          _rec('c', 30),
          _rec('a', 10),
          _rec('b', 20, title: '회의'),
          _rec('d', 30),
        ]);
        expect(names, {'a': '녹음 1', 'b': '회의', 'c': '녹음 3', 'd': '녹음 4'});
      },
    );

    test('formatBytes: decimal units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1400), '1 KB');
      expect(formatBytes(512000), '512 KB');
      expect(formatBytes(1400000), '1.4 MB');
      expect(formatBytes(20600000), '20.6 MB');
      expect(formatBytes(2500000000), '2.5 GB');
    });

    test('dateTime: local month, day, hh:mm', () {
      expect(
        MediaStringsKo.dateTime(DateTime(2026, 11, 5, 9, 4)),
        '11월 5일 09:04',
      );
    });
  });

  group('list rows', () {
    testWidgets(
      'newest first; names, badge, webm warning, date · length · size, total',
      (tester) async {
        final w = await _three();
        addTearDown(w.dispose);
        await w.pump(tester);

        final top = tester.getTopLeft(_row('r3')).dy;
        final mid = tester.getTopLeft(_row('r2')).dy;
        final low = tester.getTopLeft(_row('r1')).dy;
        expect(top < mid && mid < low, isTrue, reason: 'startedAt descending');

        expect(
          find.descendant(of: _row('r3'), matching: find.text('녹음 3')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _row('r3'),
            matching: find.text('11월 5일 14:02 · 45:00 · 20.6 MB'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: _row('r2'), matching: find.text('복구된 녹음')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _row('r2'),
            matching: find.text(MediaStringsKo.recoveredBadge),
          ),
          findsOneWidget,
        );
        expect(
          find.text(MediaStringsKo.recoveredBadge),
          findsOneWidget,
          reason: 'only r2',
        );
        expect(
          find.descendant(
            of: _row('r1'),
            matching: find.text(
              '11월 4일 08:00 · 03:00 · 1.4 MB\n${MediaStringsKo.webmWarning}',
            ),
          ),
          findsOneWidget,
        );
        expect(find.textContaining(MediaStringsKo.webmWarning), findsOneWidget);
        expect(find.text('이 노트의 녹음 3개 · 27.6 MB'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a renamed recovered recording loses the badge; numbering stays',
      (tester) async {
        final w = await _three();
        addTearDown(w.dispose);
        await w.store.recordings.renameRecording('r2', '강의 정리');
        await w.pump(tester);
        expect(find.text(MediaStringsKo.recoveredBadge), findsNothing);
        expect(find.text('강의 정리'), findsOneWidget);
        expect(find.text('녹음 1'), findsOneWidget);
        expect(find.text('녹음 3'), findsOneWidget);
      },
    );

    testWidgets('only this note: another note\'s recordings are not listed', (
      tester,
    ) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      final other = await w.store.library.createNote(title: 'Other');
      await w.seedRecording(id: 'mine', startedAt: 10);
      await w.seedRecording(id: 'theirs', startedAt: 20, noteId: other.id);
      await w.pump(tester);
      expect(_row('mine'), findsOneWidget);
      expect(_row('theirs'), findsNothing);
      expect(find.textContaining('이 노트의 녹음 1개'), findsOneWidget);
    });

    testWidgets('no recordings → no list and no total', (tester) async {
      final w = await PanelWorld.create();
      addTearDown(w.dispose);
      await w.pump(tester);
      expect(find.byType(ListTile), findsNothing);
      expect(find.textContaining('이 노트의 녹음'), findsNothing);
    });

    testWidgets(
      'a new recording appears after stop (the list follows the store)',
      (tester) async {
        final w = await PanelWorld.create();
        addTearDown(w.dispose);
        await w.pump(tester);
        await w.seedRecording(id: 'late', startedAt: 99);
        await settle(tester);
        expect(_row('late'), findsOneWidget);
        expect(find.text('녹음 1'), findsOneWidget);
      },
    );
  });

  group('tap = open only (PDF-M8)', () {
    testWidgets(
      'tapping another row opens it: calls are open: only, no play / seek',
      (tester) async {
        final w = await _three();
        addTearDown(w.dispose);
        await w.pump(tester);
        expect(w.playback.calls, [
          'open:r3',
        ], reason: 'the latest opens on show');
        await tester.tap(find.text('녹음 1'));
        await settle(tester);
        expect(w.playback.calls, ['open:r3', 'open:r1']);
        expect(w.playback.status.recordingId, 'r1');
        final open = tester.widget<ListTile>(_row('r1'));
        expect(open.selected, isTrue);
        expect(tester.widget<ListTile>(_row('r3')).selected, isFalse);
      },
    );

    testWidgets('while recording, rows do not open', (tester) async {
      final w = await _three();
      addTearDown(w.dispose);
      await w.pump(tester);
      await w.recorder.start(recordingId: 'live', noteId: w.noteId);
      await settle(tester);
      expect(tester.widget<ListTile>(_row('r1')).onTap, isNull);
      await w.recorder.cancel();
      await settle(tester);
    });
  });

  for (final landscape in [false, true]) {
    testWidgets(
      'iPad ${landscape ? 'landscape 1376×1032' : 'portrait 1032×1376'}: no overflow, tap targets',
      (tester) async {
        final w = await _three();
        addTearDown(w.dispose);
        await w.pump(tester, landscape: landscape);
        expect(tester.takeException(), isNull);
        await expectTapTargetGuidelines(tester);
      },
    );
  }

  testWidgets('narrow width (480): no overflow', (tester) async {
    final w = await _three();
    addTearDown(w.dispose);
    await w.pump(tester, width: 480);
    expect(tester.takeException(), isNull);
  });
}
