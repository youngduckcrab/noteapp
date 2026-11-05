// lib/src/pen/style_ink.dart — contract 7.2.15 (03-ink 4.2).
import 'package:note_core/note_core.dart' as core;

import 'pen_profile.dart';

// --- style helpers on the CORE type ---
// wire value of HighlighterStraightening = name
enum HighlighterStraightening { off, snapOnLift, alwaysStraight }

abstract final class InkStyleExtras {
  static const String highlighterStraightening = 'hlStraight';
}

extension StrokeStyleInk on core.StrokeStyle {
  /// PenProfile.of(tool); P1 tools → ballpoint profile
  PenProfile get profile => PenProfile.of(tool);

  /// radius at width factor 1 (hover / size preview) = width / 2
  /// (= 2 · width · kNominalWidthQ).
  double get previewRadius => 2 * width * core.kNominalWidthQ;

  /// extras['hlStraight'] when it is one of the wire names; otherwise off
  /// (missing key, unknown value or another type). Meaningful for the
  /// highlighter only.
  HighlighterStraightening get highlighterStraightening {
    final value = extras[InkStyleExtras.highlighterStraightening];
    if (value is! String) return HighlighterStraightening.off;
    for (final v in HighlighterStraightening.values) {
      if (v.name == value) return v;
    }
    return HighlighterStraightening.off;
  }

  /// copyWith(extras: {...extras, 'hlStraight': value.name}); other extras keys are kept.
  core.StrokeStyle withHighlighterStraightening(
    HighlighterStraightening value,
  ) => copyWith(
    extras: {...extras, InkStyleExtras.highlighterStraightening: value.name},
  );
}
