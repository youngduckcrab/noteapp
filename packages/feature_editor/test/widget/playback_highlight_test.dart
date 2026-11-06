// m5-7/04-editor 8.2 E2-17 (6.15.2 — contract R-4, R-5 (v2.1), I-9; PDF
// review M-8 → EDITOR-M8): PlaybackHighlightDriver with CORE's
// FakeAudioPlayback / FakeAudioRecorder — the focus on every mounted INK
// controller (getter playbackFocus), the Ticker, new mounts, app hidden, and
// no dimming right after a recording stops.
import 'dart:convert';
import 'dart:typed_data';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/panel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_extensions.dart';
import '../helpers/pump_editor.dart';

const _rec = 'rec-1';

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  int pages = 3,
  EditorSettings? settings,
}) async {
  final panel = TestRecordingPanelBuilder();
  final h = await pumpEditor(
    tester,
    pages: pages,
    fakeAudio: true,
    recordings: const [RecordingSeed(id: _rec)],
    extensions: EditorExtensions(recordingPanel: panel.builder),
    settings: settings,
  );
  await _loadRecordings(tester);
  return h;
}

/// Lets the note's recording list (noteRecordingsProvider) load.
Future<void> _loadRecordings(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<core.Recording> _recording(
  WidgetTester tester,
  EditorTestHandles h,
  String id,
) async {
  core.Recording? found;
  await h.store.recordings.getRecording(id).then((r) => found = r);
  await tester.pump();
  return found!;
}

/// The playbackFocus of every mounted page controller.
List<ink.InkPlaybackFocus?> _focuses(EditorTestHandles h) => [
  for (final m in h.mountedPages.all) m.controller.playbackFocus,
];

ink.InkPlaybackFocus _focus(int positionMs, [String id = _rec]) =>
    ink.InkPlaybackFocus(recordingId: id, positionMs: positionMs);

void main() {
  testWidgets('playing + setPositionMs → the next frame puts the focus on '
      'every mounted controller; frames keep following', (tester) async {
    final h = await _pump(tester);
    final playback = h.audioPlayback!;
    expect(h.mountedPages.all.length, greaterThanOrEqualTo(2));
    await playback.open(await _recording(tester, h, _rec));
    await tester.pump();
    expect(_focuses(h), everyElement(isNull)); // opened only (R-5)
    await playback.play();
    await tester.pump();
    playback.setPositionMs(1500);
    await tester.pump();
    expect(_focuses(h), everyElement(_focus(1500)));
    playback.setPositionMs(1600);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_focuses(h), everyElement(_focus(1600)));
    await playback.close();
    await tester.pump();
  });

  testWidgets('paused → the Ticker stops and the focus stays; the recording '
      'closes → null', (tester) async {
    final h = await _pump(tester);
    final playback = h.audioPlayback!;
    await playback.open(await _recording(tester, h, _rec));
    await playback.play();
    await tester.pump();
    playback.setPositionMs(2000);
    await tester.pump();
    await playback.pause();
    await tester.pump();
    expect(_focuses(h), everyElement(_focus(2000)));
    // No frame is scheduled by the driver any more.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    playback.setPositionMs(2500); // no event, Ticker off → unchanged
    await tester.pump(const Duration(milliseconds: 100));
    expect(_focuses(h), everyElement(_focus(2000)));

    await playback.close();
    await tester.pump();
    expect(_focuses(h), everyElement(isNull));
  });

  testWidgets('another note\'s recording playing → no focus', (tester) async {
    final h = await _pump(tester);
    final other = await h.store.library.createNote(
      title: 'other',
      pages: const [core.PageDraft.blankA4],
    );
    final asset = await h.store.assets.put(
      Uint8List.fromList(utf8.encode('other audio')),
      type: core.AssetType.audio,
      mimeType: 'audio/webm',
    );
    final recording = await h.store.recordings.createRecording(
      id: 'rec-other',
      noteId: other.id,
      assetId: asset.id,
      durationMs: 30000,
      startedAt: 1000,
    );
    await tester.pump();
    final playback = h.audioPlayback!;
    await playback.open(recording);
    await playback.play();
    await tester.pump();
    playback.setPositionMs(1000);
    await tester.pump();
    expect(_focuses(h), everyElement(isNull));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await playback.close();
    await tester.pump();
  });

  testWidgets('a page mounted later gets the current focus', (tester) async {
    final h = await _pump(tester, pages: 12);
    final playback = h.audioPlayback!;
    await playback.open(await _recording(tester, h, _rec));
    await playback.play();
    await tester.pump();
    playback.setPositionMs(3000);
    await tester.pump();
    await playback.pause();
    await tester.pump();
    final before = {for (final m in h.mountedPages.all) m.pageId};
    await h.viewport.jumpToPage(10, animate: false);
    await h.settlePages();
    final fresh = [
      for (final m in h.mountedPages.all)
        if (!before.contains(m.pageId)) m,
    ];
    expect(fresh, isNotEmpty);
    for (final m in fresh) {
      expect(m.isLoaded.value, isTrue);
      expect(m.controller.playbackFocus, _focus(3000), reason: m.pageId);
    }
    await playback.close();
    await tester.pump();
  });

  testWidgets('app hidden → the Ticker stops (playback may go on); shown → '
      'it follows again', (tester) async {
    final h = await _pump(tester);
    final playback = h.audioPlayback!;
    await playback.open(await _recording(tester, h, _rec));
    await playback.play();
    await tester.pump();
    playback.setPositionMs(1000);
    await tester.pump();
    expect(_focuses(h), everyElement(_focus(1000)));

    // resumed → inactive → hidden (AppLifecycleListener.onHide).
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    playback.setPositionMs(4000);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_focuses(h), everyElement(_focus(1000)));

    // hidden → inactive (onShow) → resumed.
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_focuses(h), everyElement(_focus(4000)));
    await playback.close();
    await tester.pump();
  });

  testWidgets('no dimming right after a recording stops: record → stop → the '
      'player opens it (ready) → null; the panel open (ready) → null; play → '
      'focus', (tester) async {
    final h = await _pump(tester);
    final recorder = h.audioRecorder!;
    final playback = h.audioPlayback!;
    await recorder.start(recordingId: 'rec-new', noteId: h.noteId);
    recorder.advance(const Duration(seconds: 5));
    core.Recording? stopped;
    await recorder.stop().then((r) => stopped = r);
    await _loadRecordings(tester);
    expect(stopped?.id, 'rec-new');
    // The media panel's automatic open after stop.
    await playback.open(stopped!);
    await tester.pump();
    expect(playback.status.phase, core.PlaybackPhase.ready);
    expect(_focuses(h), everyElement(isNull));

    // Opening the panel (media opens the latest recording, ready).
    h.container.read(editorPanelProvider.notifier).open();
    await tester.pump();
    await playback.open(stopped!);
    await tester.pump(const Duration(milliseconds: 300)); // a poll or more
    expect(_focuses(h), everyElement(isNull));

    await playback.play();
    await tester.pump();
    expect(_focuses(h), everyElement(_focus(0, 'rec-new')));
    await playback.close();
    await tester.pump();
  });

  testWidgets(
    'a seek from the panel (no status event) → active within a poll',
    (tester) async {
      final h = await _pump(tester);
      final playback = h.audioPlayback!;
      h.container.read(editorPanelProvider.notifier).open();
      await tester.pump();
      await playback.open(await _recording(tester, h, _rec));
      await tester.pump();
      expect(_focuses(h), everyElement(isNull));
      playback.setPositionMs(8000); // the panel's seek bar
      await tester.pump(const Duration(milliseconds: 260));
      expect(_focuses(h), everyElement(_focus(8000)));
      await playback.close();
      await tester.pump();
    },
  );

  testWidgets('the highlight style setting is handed over as it is', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      settings: const EditorSettings(
        playbackHighlight: ink.InkPlaybackStyle.highlightRecent,
      ),
    );
    final playback = h.audioPlayback!;
    await playback.open(await _recording(tester, h, _rec));
    await playback.play();
    await tester.pump();
    playback.setPositionMs(500);
    await tester.pump();
    expect(
      _focuses(h),
      everyElement(
        const ink.InkPlaybackFocus(
          recordingId: _rec,
          positionMs: 500,
          style: ink.InkPlaybackStyle.highlightRecent,
        ),
      ),
    );
    await playback.pause();
    await tester.pump();
    h.container
        .read(editorSettingsProvider.notifier)
        .setPlaybackHighlight(ink.InkPlaybackStyle.dimUnwritten);
    await tester.pump();
    expect(_focuses(h), everyElement(_focus(500)));
    await playback.close();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
