// m5-7/04-editor 8.2 E2-16 (6.15.4, 6.13.1 [🎤], 6.21 E-7): the mic button and
// the bottom panel slot (EditorExtensions.recordingPanel) with the test panel
// builder, CORE's FakeAudioRecorder for the recording dot.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/panel.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/ui/editor_body.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/panels/editor_panel_slot.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/mic_button.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_extensions.dart';
import '../helpers/pump_editor.dart';

Future<EditorTestHandles> _pump(
  WidgetTester tester,
  TestRecordingPanelBuilder panel, {
  EditorPanelBuilder? builder,
}) => pumpEditor(
  tester,
  fakeAudio: true,
  extensions: EditorExtensions(recordingPanel: builder ?? panel.builder),
);

/// (v2.15-ui) The toolbar [🎤] shows only while recording or with the panel
/// open; otherwise 녹음 is in [+].
Future<void> _tapMic(WidgetTester tester) async {
  if (find.byKey(MicButton.micKey).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(MicButton.micKey));
    await tester.pump();
    return;
  }
  await tester.tap(find.byKey(InsertMenu.buttonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(InsertMenu.recordingKey));
  await tester.pump();
}

/// Height of EditorBody's Column (the body the 40 % is measured on).
double _bodyHeight(WidgetTester tester) => tester
    .getSize(
      find
          .descendant(
            of: find.byType(EditorBody),
            matching: find.byType(LayoutBuilder),
          )
          .first,
    )
    .height;

Future<Map<String, Object?>?> _storedDevice(
  WidgetTester tester,
  EditorTestHandles h,
) async {
  Map<String, Object?>? stored;
  var done = false;
  unawaited(
    h.store.settings.get(EditorSettingKeys.deviceSettings).then((v) {
      stored = v;
      done = true;
    }),
  );
  for (var i = 0; i < 10 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue);
  return stored;
}

void main() {
  testWidgets('recordingPanel == null → no mic button, no 녹음 row, no slot', (
    tester,
  ) async {
    await pumpEditor(tester, fakeAudio: true);
    expect(find.byKey(MicButton.micKey), findsNothing);
    expect(find.byKey(InsertMenu.recordingKey), findsNothing);
    expect(find.byKey(EditorPanelSlot.slotKey), findsNothing);
  });

  testWidgets('mic → the slot opens under the page viewport with the panel '
      'context; ≤ 40 % of the body height; mic again → closed', (tester) async {
    final panel = TestRecordingPanelBuilder();
    final h = await _pump(tester, panel);
    // (v2.15-ui) not recording, panel closed: [🎤] is in [+] only.
    expect(find.byKey(MicButton.micKey), findsNothing);
    expect(find.byKey(EditorPanelSlot.slotKey), findsNothing);
    final viewportBefore = tester.getSize(find.byType(PageViewport)).height;

    await _tapMic(tester);
    expect(h.container.read(editorPanelProvider), isTrue);
    expect(find.byKey(EditorPanelSlot.slotKey), findsOneWidget);
    expect(find.byKey(testPanelKey), findsOneWidget);
    expect(panel.panelContexts, isNotEmpty);
    final context = panel.panelContexts.last;
    expect(context.noteId, h.noteId);
    expect(context.tapToSeek.value, isTrue); // EditorSettings default

    final slot = tester.getRect(find.byKey(EditorPanelSlot.slotKey));
    expect(slot.height, 120); // the test panel's own height
    expect(slot.height, lessThanOrEqualTo(0.4 * _bodyHeight(tester)));
    final viewport = tester.getRect(find.byType(PageViewport));
    expect(viewport.bottom, lessThanOrEqualTo(slot.top));
    expect(viewport.height, lessThan(viewportBefore));

    await _tapMic(tester);
    expect(h.container.read(editorPanelProvider), isFalse);
    expect(find.byKey(EditorPanelSlot.slotKey), findsNothing);
  });

  testWidgets('a panel taller than 40 % is cut to 40 % of the body height', (
    tester,
  ) async {
    final panel = TestRecordingPanelBuilder();
    await _pump(
      tester,
      panel,
      builder: (context, _) => const SizedBox(height: 2000),
    );
    await _tapMic(tester);
    final body = _bodyHeight(tester);
    final slot = tester.getSize(find.byKey(EditorPanelSlot.slotKey));
    expect(slot.height, closeTo(0.4 * body, 0.01));
    expect(tester.takeException(), isNull); // no overflow
  });

  testWidgets('setTapToSeek(false) → EditorSettings.tapToSeek, the device key '
      'after 500 ms and tapToSeek.value; a settings change is followed', (
    tester,
  ) async {
    final panel = TestRecordingPanelBuilder();
    final h = await _pump(tester, panel);
    await _tapMic(tester);
    final context = panel.panelContexts.last;

    await tester.tap(find.byKey(testPanelTapToSeekKey));
    await tester.pump();
    expect(h.container.read(editorSettingsProvider).tapToSeek, isFalse);
    expect(context.tapToSeek.value, isFalse);
    expect(
      tester.widget<Switch>(find.byKey(testPanelTapToSeekKey)).value,
      false,
    );

    await tester.pump(const Duration(milliseconds: 500));
    final stored = await _storedDevice(tester, h);
    expect(stored?['tapToSeek'], false);

    // Another writer (the settings screen) → the panel's notifier follows.
    h.container.read(editorSettingsProvider.notifier).setTapToSeek(true);
    await tester.pump();
    expect(context.tapToSeek.value, isTrue);
    expect(
      tester.widget<Switch>(find.byKey(testPanelTapToSeekKey)).value,
      true,
    );
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('close → the slot closes; a recording goes on', (tester) async {
    final panel = TestRecordingPanelBuilder();
    final h = await _pump(tester, panel);
    await h.audioRecorder!.start(recordingId: 'rec-1', noteId: h.noteId);
    await _tapMic(tester);
    await tester.tap(find.byKey(testPanelCloseKey));
    await tester.pump();
    expect(h.container.read(editorPanelProvider), isFalse);
    expect(find.byKey(EditorPanelSlot.slotKey), findsNothing);
    expect(h.audioRecorder!.status.phase, core.RecorderPhase.recording);
    expect(find.byKey(MicButton.recordingDotKey), findsOneWidget);
    await h.audioRecorder!.cancel();
  });

  testWidgets('the builder throws → reported (feature_editor) and one line '
      '\'녹음 패널을 열지 못했어요\'; reopening builds the panel', (tester) async {
    final panel = TestRecordingPanelBuilder()..throwNext = StateError('boom');
    await _pump(tester, panel);
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await _tapMic(tester);
      // Rebuilds while open do not call the builder again.
      await tester.pump();
    } finally {
      FlutterError.onError = previous;
    }
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
    expect(reported.single.library, 'feature_editor');
    expect(find.byKey(EditorPanelSlot.slotKey), findsOneWidget);
    expect(find.byKey(EditorPanelSlot.failedKey), findsOneWidget);
    expect(find.text(EditorStrings.recordingPanelFailed), findsOneWidget);
    expect(find.byKey(testPanelKey), findsNothing);

    await _tapMic(tester); // close
    await _tapMic(tester); // open again
    expect(find.byKey(EditorPanelSlot.failedKey), findsNothing);
    expect(find.byKey(testPanelKey), findsOneWidget);
  });

  testWidgets('mic button: this note records → mic + red dot (paused too); '
      'stopped → no dot; another note → grey dot and its tooltip', (
    tester,
  ) async {
    final panel = TestRecordingPanelBuilder();
    final h = await _pump(tester, panel);
    // (v2.15-ui) [🎤] is in the row while the panel is open.
    await _tapMic(tester);
    final recorder = h.audioRecorder!;
    final mic = find.byKey(MicButton.micKey);
    Finder icon(IconData data) =>
        find.descendant(of: mic, matching: find.byIcon(data));

    expect(icon(Icons.mic_none), findsOneWidget);
    expect(find.byKey(MicButton.recordingDotKey), findsNothing);
    expect(find.byKey(MicButton.otherNoteDotKey), findsNothing);

    await recorder.start(recordingId: 'rec-1', noteId: h.noteId);
    await tester.pump();
    expect(icon(Icons.mic), findsOneWidget);
    final dot = find.byKey(MicButton.recordingDotKey);
    expect(dot, findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: dot, matching: find.byType(DecoratedBox)),
    );
    expect(
      (box.decoration as BoxDecoration).color,
      MicButton.recordingDotColor,
    );
    expect(find.byTooltip(EditorStrings.recordingInOtherNote), findsNothing);

    await recorder.pause();
    await tester.pump();
    expect(find.byKey(MicButton.recordingDotKey), findsOneWidget);

    await recorder.cancel();
    await tester.pump();
    expect(find.byKey(MicButton.recordingDotKey), findsNothing);
    expect(icon(Icons.mic_none), findsOneWidget);

    await recorder.start(recordingId: 'rec-2', noteId: 'another-note');
    await tester.pump();
    expect(find.byKey(MicButton.recordingDotKey), findsNothing);
    final grey = find.byKey(MicButton.otherNoteDotKey);
    expect(grey, findsOneWidget);
    final greyBox = tester.widget<DecoratedBox>(
      find.descendant(of: grey, matching: find.byType(DecoratedBox)),
    );
    final scheme = Theme.of(tester.element(mic)).colorScheme;
    expect((greyBox.decoration as BoxDecoration).color, scheme.outline);
    expect(icon(Icons.mic_none), findsOneWidget);
    expect(
      find.descendant(
        of: mic,
        matching: find.byTooltip(EditorStrings.recordingInOtherNote),
      ),
      findsOneWidget,
    );
    await recorder.cancel();
  });
}
