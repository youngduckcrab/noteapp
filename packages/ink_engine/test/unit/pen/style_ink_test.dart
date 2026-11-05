// T02 (03-ink 8, 4.2): the INK reading of core.StrokeStyle (contract 7.2.15).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  final hl = core.StrokeStyle.defaultsFor(core.PenTool.highlighter);

  test('wire key and values', () {
    expect(InkStyleExtras.highlighterStraightening, 'hlStraight');
    expect(HighlighterStraightening.values.map((v) => v.name), [
      'off',
      'snapOnLift',
      'alwaysStraight',
    ]);
  });

  test('reads hlStraight', () {
    expect(hl.highlighterStraightening, HighlighterStraightening.off);
    for (final v in HighlighterStraightening.values) {
      final s = hl.copyWith(extras: {'hlStraight': v.name});
      expect(s.highlighterStraightening, v);
    }
  });

  test('missing key, unknown value or another type → off', () {
    for (final extras in <Map<String, Object?>>[
      const {},
      const {'hlStraight': 'sideways'},
      const {'hlStraight': 'SnapOnLift'},
      const {'hlStraight': 1},
      const {'hlStraight': true},
      const {'hlStraight': null},
      const {
        'hlStraight': ['snapOnLift'],
      },
    ]) {
      expect(
        hl.copyWith(extras: extras).highlighterStraightening,
        HighlighterStraightening.off,
        reason: '$extras',
      );
    }
  });

  test(
    'withHighlighterStraightening writes the name and keeps other extras',
    () {
      final s = hl.copyWith(
        extras: {'hlStraight': 'off', 'other': 3, 'x': 'y'},
      );
      final w = s.withHighlighterStraightening(
        HighlighterStraightening.alwaysStraight,
      );
      expect(w.extras, {'hlStraight': 'alwaysStraight', 'other': 3, 'x': 'y'});
      expect(
        w.highlighterStraightening,
        HighlighterStraightening.alwaysStraight,
      );
      // Only extras change.
      expect(w.copyWith(extras: s.extras), s);
      // The source style is not modified.
      expect(s.extras['hlStraight'], 'off');
      // Works on a style with no extras and on other tools (read-only meaning).
      final b = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
          .withHighlighterStraightening(HighlighterStraightening.snapOnLift);
      expect(b.extras, {'hlStraight': 'snapOnLift'});
      expect(b.highlighterStraightening, HighlighterStraightening.snapOnLift);
    },
  );

  test('previewRadius = width / 2 and profile = PenProfile.of(tool)', () {
    for (final tool in core.PenTool.values) {
      final s = core.StrokeStyle.defaultsFor(tool);
      expect(s.previewRadius, closeTo(s.width / 2, 1e-12));
      expect(s.previewRadius, 2 * s.width * core.kNominalWidthQ);
      expect(s.profile, PenProfile.of(tool));
    }
    final wide = core.StrokeStyle.defaultsFor(core.PenTool.marker)
        .copyWith(width: 30);
    expect(wide.previewRadius, 15);
  });
}
