// m5-7/04-editor 8.2 E2-17 (6.15.2 — contract R-4, R-5 (v2.1), PDF review
// M-8): PlaybackHighlightLogic with a recording output (no widgets, no
// Ticker).
import 'package:feature_editor/src/playback/playback_highlighter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

const _rec = 'rec-1';
const _rec2 = 'rec-2';

core.PlaybackStatus _status(core.PlaybackPhase phase, [String? id = _rec]) =>
    core.PlaybackStatus(phase: phase, recordingId: id, durationMs: 60000);

ink.InkPlaybackFocus _focus(
  int positionMs, {
  String id = _rec,
  ink.InkPlaybackStyle style = ink.InkPlaybackStyle.dimUnwritten,
}) =>
    ink.InkPlaybackFocus(recordingId: id, positionMs: positionMs, style: style);

void main() {
  late List<ink.InkPlaybackFocus?> outputs;
  late Set<String> noteIds;
  late ink.InkPlaybackStyle style;
  late PlaybackHighlightLogic logic;

  setUp(() {
    outputs = [];
    noteIds = {_rec, _rec2};
    style = ink.InkPlaybackStyle.dimUnwritten;
    logic = PlaybackHighlightLogic(
      output: outputs.add,
      noteRecordingIds: () => noteIds,
      style: () => style,
    );
  });

  /// open(): loading → ready at 0, as the panel / the recorder's stop does.
  void open([String id = _rec, int at = 0]) {
    expect(
      logic.onStatus(_status(core.PlaybackPhase.loading, id), positionMs: at),
      isFalse,
    );
    expect(
      logic.onStatus(_status(core.PlaybackPhase.ready, id), positionMs: at),
      isFalse,
    );
  }

  test('ready (opened only) → no focus; awaiting activation', () {
    open();
    expect(outputs, isEmpty);
    expect(logic.current, isNull);
    expect(logic.awaitingActivation, isTrue);
    // More status events at the open position change nothing.
    logic.onStatus(_status(core.PlaybackPhase.ready), positionMs: 0);
    logic.onTick(0);
    expect(outputs, isEmpty);
  });

  test('playing → focus, Ticker on; same position skipped; ticks follow', () {
    open();
    expect(
      logic.onStatus(_status(core.PlaybackPhase.playing), positionMs: 0),
      isTrue,
    );
    expect(outputs, [_focus(0)]);
    expect(logic.awaitingActivation, isFalse);
    logic.onTick(0); // same → nothing
    logic.onTick(16);
    logic.onTick(16);
    logic.onTick(33);
    expect(outputs, [_focus(0), _focus(16), _focus(33)]);
    expect(logic.current, _focus(33));
  });

  test(
    'paused → Ticker off, the last position stays; ready / completed too',
    () {
      open();
      logic.onStatus(_status(core.PlaybackPhase.playing), positionMs: 0);
      logic.onTick(1200);
      expect(
        logic.onStatus(_status(core.PlaybackPhase.paused), positionMs: 1250),
        isFalse,
      );
      expect(logic.current, _focus(1250));
      logic.onTick(1300); // paused: ticks are ignored
      expect(logic.current, _focus(1250));
      // A seek while paused (status event) → the new position, still shown.
      logic.onStatus(_status(core.PlaybackPhase.paused), positionMs: 4000);
      expect(logic.current, _focus(4000));
      expect(
        logic.onStatus(
          _status(core.PlaybackPhase.completed),
          positionMs: 60000,
        ),
        isFalse,
      );
      expect(logic.current, _focus(60000));
      // loading → as it is
      logic.onStatus(_status(core.PlaybackPhase.loading), positionMs: 0);
      expect(logic.current, _focus(60000));
    },
  );

  test(
    'after the open, positionMs changes (a seek from the panel) → active',
    () {
      open();
      expect(logic.current, isNull);
      // The panel's seek bar: no status event of its own — the driver polls.
      logic.onStatus(_status(core.PlaybackPhase.ready), positionMs: 7000);
      expect(logic.current, _focus(7000));
      expect(logic.awaitingActivation, isFalse);
    },
  );

  test('markSeek → active (the next status shows the focus)', () {
    open();
    logic.markSeek();
    expect(logic.awaitingActivation, isFalse);
    // Seek to the open position (0) still activates through markSeek.
    logic.onStatus(_status(core.PlaybackPhase.ready), positionMs: 0);
    expect(logic.current, _focus(0));
  });

  test('markSeek with nothing open does nothing', () {
    logic.markSeek();
    open();
    expect(logic.current, isNull);
    expect(logic.awaitingActivation, isTrue);
  });

  test('another recording opens → not active again, focus null', () {
    open();
    logic.onStatus(_status(core.PlaybackPhase.playing), positionMs: 0);
    logic.onTick(500);
    expect(logic.current, _focus(500));
    open(_rec2);
    expect(logic.current, isNull);
    expect(outputs.last, isNull);
    expect(logic.awaitingActivation, isTrue);
    logic.onStatus(_status(core.PlaybackPhase.playing, _rec2), positionMs: 0);
    expect(logic.current, _focus(0, id: _rec2));
  });

  test('the loading position is not taken as the open position', () {
    open();
    logic.onStatus(_status(core.PlaybackPhase.playing), positionMs: 0);
    logic.onTick(9000);
    // Another recording: loading still reports the old position 9000, then
    // ready at 0 — not a seek.
    logic.onStatus(
      _status(core.PlaybackPhase.loading, _rec2),
      positionMs: 9000,
    );
    logic.onStatus(_status(core.PlaybackPhase.ready, _rec2), positionMs: 0);
    expect(logic.current, isNull);
    expect(logic.awaitingActivation, isTrue);
  });

  test('closed (recordingId null), idle, failed, another note\'s recording → '
      'null, Ticker off; re-opened → not active', () {
    for (final close in [
      _status(core.PlaybackPhase.idle, null),
      _status(core.PlaybackPhase.idle),
      _status(core.PlaybackPhase.failed),
      _status(core.PlaybackPhase.playing, 'rec-of-another-note'),
    ]) {
      open();
      logic.onStatus(_status(core.PlaybackPhase.playing), positionMs: 0);
      logic.onTick(100);
      expect(logic.current, _focus(100), reason: '$close');
      expect(logic.onStatus(close, positionMs: 100), isFalse);
      expect(logic.current, isNull, reason: '$close');
      expect(logic.awaitingActivation, isFalse);
      logic.onTick(200);
      expect(logic.current, isNull);
    }
    open();
    expect(logic.current, isNull);
  });

  test('the recordings load later → the same status gives the focus', () {
    noteIds = {};
    logic.onStatus(_status(core.PlaybackPhase.playing), positionMs: 300);
    expect(logic.current, isNull);
    noteIds = {_rec};
    expect(
      logic.onStatus(_status(core.PlaybackPhase.playing), positionMs: 300),
      isTrue,
    );
    expect(logic.current, _focus(300));
  });

  test('the style comes from the setting at each output', () {
    open();
    logic.onStatus(_status(core.PlaybackPhase.paused), positionMs: 1000);
    logic.markSeek();
    logic.onStatus(_status(core.PlaybackPhase.paused), positionMs: 1000);
    expect(logic.current, _focus(1000));
    style = ink.InkPlaybackStyle.highlightRecent;
    logic.onStatus(_status(core.PlaybackPhase.paused), positionMs: 1000);
    expect(
      logic.current,
      _focus(1000, style: ink.InkPlaybackStyle.highlightRecent),
    );
  });
}
