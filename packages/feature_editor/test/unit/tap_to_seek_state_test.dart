// m5-7/04-editor 8.2 E2-17 (6.3.5 'tap-to-seek state' — contract 7.2.4 R-5
// (v2.1)): tapToSeekActive over every combination — recorder phase 5 ×
// player phase 7 × panel 2 × kind 2 × setting 2 × 'the open recording is
// this note's' 2 — against the rule written out row by row, plus the named
// rows of the plan (review M-3).
import 'package:feature_editor/src/playback/tap_to_seek.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

const _rec = 'rec-1';

bool _active({
  required TapKind kind,
  bool setting = true,
  core.RecorderPhase recorder = core.RecorderPhase.idle,
  bool panelOpen = false,
  core.PlaybackPhase phase = core.PlaybackPhase.ready,
  bool thisNote = true,
  String? recordingId = _rec,
}) => tapToSeekActive(
  kind: kind,
  tapToSeekSetting: setting,
  recorderPhase: recorder,
  panelOpen: panelOpen,
  playback: core.PlaybackStatus(
    phase: phase,
    recordingId: recordingId,
    durationMs: 60000,
  ),
  noteRecordingIds: thisNote ? {_rec, 'rec-other'} : {'rec-other'},
);

/// The rule, one condition per line (R-5 (v2.1), 6.3.5).
bool _expected({
  required TapKind kind,
  required bool setting,
  required core.RecorderPhase recorder,
  required bool panelOpen,
  required core.PlaybackPhase phase,
  required bool thisNote,
}) {
  if (!setting) return false; // tapToSeek off
  if (recorder != core.RecorderPhase.idle) return false; // recording
  if (!thisNote) return false; // another note's recording
  // Nothing open to play from.
  if (phase == core.PlaybackPhase.idle) return false;
  if (phase == core.PlaybackPhase.failed) return false;
  final playingOrPaused =
      phase == core.PlaybackPhase.playing || phase == core.PlaybackPhase.paused;
  if (kind == TapKind.penDot) return playingOrPaused; // dots: playing only
  return panelOpen || playingOrPaused; // finger: or the panel is open
}

void main() {
  test('every combination (5 × 7 × 2 × 2 × 2 × 2 = 560)', () {
    var count = 0;
    var taken = 0;
    for (final recorder in core.RecorderPhase.values) {
      for (final phase in core.PlaybackPhase.values) {
        for (final panelOpen in [false, true]) {
          for (final kind in TapKind.values) {
            for (final setting in [false, true]) {
              for (final thisNote in [false, true]) {
                final want = _expected(
                  kind: kind,
                  setting: setting,
                  recorder: recorder,
                  panelOpen: panelOpen,
                  phase: phase,
                  thisNote: thisNote,
                );
                expect(
                  _active(
                    kind: kind,
                    setting: setting,
                    recorder: recorder,
                    panelOpen: panelOpen,
                    phase: phase,
                    thisNote: thisNote,
                  ),
                  want,
                  reason:
                      'recorder $recorder, player $phase, panel $panelOpen, '
                      '$kind, setting $setting, this note $thisNote',
                );
                count++;
                if (want) taken++;
              }
            }
          }
        }
      }
    }
    expect(count, 560);
    // finger: panel open × {loading, ready, playing, paused, completed} +
    // panel closed × {playing, paused} = 7; pen dot: 2 × {playing, paused} = 4.
    expect(taken, 11);
  });

  group('named rows (review M-3, 6.15.3)', () {
    test('① right after a recording stops (player ready), panel closed → '
        'neither a finger tap nor a pen dot is taken', () {
      expect(_active(kind: TapKind.finger), isFalse);
      expect(_active(kind: TapKind.penDot), isFalse);
    });

    test(
      '② panel open + ready → a finger tap is taken, a pen dot is a dot',
      () {
        expect(_active(kind: TapKind.finger, panelOpen: true), isTrue);
        expect(_active(kind: TapKind.penDot, panelOpen: true), isFalse);
      },
    );

    test('③ recording (and starting / paused / finishing) → nothing is taken, '
        'even while playing with the panel open', () {
      for (final recorder in core.RecorderPhase.values) {
        if (recorder == core.RecorderPhase.idle) continue;
        for (final kind in TapKind.values) {
          expect(
            _active(
              kind: kind,
              recorder: recorder,
              panelOpen: true,
              phase: core.PlaybackPhase.playing,
            ),
            isFalse,
            reason: '$recorder $kind',
          );
        }
      }
    });

    test('playing / paused → both kinds are taken; the setting off → none', () {
      for (final phase in [
        core.PlaybackPhase.playing,
        core.PlaybackPhase.paused,
      ]) {
        for (final kind in TapKind.values) {
          expect(_active(kind: kind, phase: phase), isTrue);
          expect(_active(kind: kind, phase: phase, setting: false), isFalse);
        }
      }
    });

    test('no open recording (recordingId null) or another note\'s → none', () {
      for (final kind in TapKind.values) {
        expect(
          _active(
            kind: kind,
            phase: core.PlaybackPhase.playing,
            panelOpen: true,
            recordingId: null,
          ),
          isFalse,
        );
        expect(
          _active(
            kind: kind,
            phase: core.PlaybackPhase.playing,
            thisNote: false,
          ),
          isFalse,
        );
      }
    });

    test('the note\'s recordings not loaded yet (empty set) → none', () {
      expect(
        tapToSeekActive(
          kind: TapKind.finger,
          tapToSeekSetting: true,
          recorderPhase: core.RecorderPhase.idle,
          panelOpen: true,
          playback: const core.PlaybackStatus(
            phase: core.PlaybackPhase.playing,
            recordingId: _rec,
          ),
          noteRecordingIds: const {},
        ),
        isFalse,
      );
    });
  });

  test('tapToSeekPositionMs = max(0, offset − preRoll)', () {
    expect(tapToSeekPositionMs(5000, 1500), 3500);
    expect(tapToSeekPositionMs(1000, 1500), 0);
    expect(tapToSeekPositionMs(1500, 1500), 0);
    expect(tapToSeekPositionMs(4000, 0), 4000);
    expect(tapToSeekPositionMs(10000, 3000), 7000);
  });
}
