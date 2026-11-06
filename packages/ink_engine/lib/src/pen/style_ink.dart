// lib/src/pen/style_ink.dart — contract 7.2.15 (03-ink 4.2), 2nd round contract 7.2.9
// (m5-7/03-ink 4.1, reading rules 4.10). Final implementation (T24).
import 'package:note_core/note_core.dart' as core;

import 'pen_profile.dart';

// --- style helpers on the CORE type ---
// wire value of HighlighterStraightening = name
enum HighlighterStraightening { off, snapOnLift, alwaysStraight }

// --- style extras keys (INK owns; CORE stores in StrokeStyle.extras) — 추가 ---
abstract final class InkStyleExtras {
  static const String highlighterStraightening = 'hlStraight'; // v1.4
  static const String nibAngleDeg =
      'nibAngleDeg'; // calligraphy, [0, 180), default 45
  static const String nibAspect =
      'nibAspect'; // calligraphy, minor/major (0.1..1], default 0.25
  static const String followBarrelRoll =
      'rollNib'; // calligraphy, bool, default true (native Pencil Pro)
  static const String dash =
      'dash'; // dashed, [on, off, …] × width, default [4, 3]
  static const String laserFadeMs =
      'laserFadeMs'; // laser, [300, 5000], default 1500
  static const String tapeStyle =
      'tapeStyle'; // tape, 'solid' | 'striped', default 'solid'
}

enum InkTapeStyle { solid, striped }

// Defaults and limits of the reading rules (m5-7/03-ink 4.10).
const double _defaultNibAngleDeg = 45;
const double _defaultNibAspect = 0.25;
const double _minNibAspect = 0.1;
const List<double> _defaultDash = [4, 3];
const double _maxDashEntry = 50;
const double _minDashSum = 0.5;
const int _defaultLaserFadeMs = 1500;
const int _minLaserFadeMs = 300;
const int _maxLaserFadeMs = 5000;

/// A finite double from a JSON number, else null.
double? _finite(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d.isFinite ? d : null;
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

  // (v2.0) The getters read extras leniently: a missing key, a wrong type or a value out
  // of range gives the default (or the clamped value); they never throw (4.10).

  /// extras['nibAngleDeg'] mod 180 in [0, 180); default 45.
  double get nibAngleDeg {
    final v = _finite(extras[InkStyleExtras.nibAngleDeg]);
    if (v == null) return _defaultNibAngleDeg;
    final folded = v % 180; // Dart % is never negative for a positive divisor
    return folded >= 180 ? 0 : folded;
  }

  /// extras['nibAspect'] clamped to (0.1 .. 1] (≤ 0.1 → 0.1); default 0.25.
  double get nibAspect {
    final v = _finite(extras[InkStyleExtras.nibAspect]);
    if (v == null) return _defaultNibAspect;
    if (v <= _minNibAspect) return _minNibAspect;
    return v > 1 ? 1 : v;
  }

  /// extras['rollNib'] when a bool; default true.
  bool get followBarrelRoll {
    final v = extras[InkStyleExtras.followBarrelRoll];
    return v is bool ? v : true;
  }

  /// extras['dash']: a list of 2..8 numbers (even length), each clamped to [0, 50], with a
  /// sum ≥ 0.5 — in multiples of the width; anything else → [4, 3]. Unmodifiable.
  List<double> get dashPattern {
    final v = extras[InkStyleExtras.dash];
    if (v is! List || v.length < 2 || v.length > 8 || v.length.isOdd) {
      return _defaultDash;
    }
    final out = <double>[];
    var sum = 0.0;
    for (final e in v) {
      final d = _finite(e);
      if (d == null) return _defaultDash;
      final c = d < 0 ? 0.0 : (d > _maxDashEntry ? _maxDashEntry : d);
      out.add(c);
      sum += c;
    }
    if (sum < _minDashSum) return _defaultDash;
    return List.unmodifiable(out);
  }

  /// extras['laserFadeMs'] rounded and clamped to [300, 5000]; default 1500.
  int get laserFadeMs {
    final v = _finite(extras[InkStyleExtras.laserFadeMs]);
    if (v == null) return _defaultLaserFadeMs;
    final r = v.round();
    return r < _minLaserFadeMs
        ? _minLaserFadeMs
        : (r > _maxLaserFadeMs ? _maxLaserFadeMs : r);
  }

  /// extras['tapeStyle'] when a wire name ('solid' | 'striped'); default solid.
  InkTapeStyle get tapeStyle {
    final v = extras[InkStyleExtras.tapeStyle];
    if (v is String) {
      for (final s in InkTapeStyle.values) {
        if (s.name == v) return s;
      }
    }
    return InkTapeStyle.solid;
  }

  /// Writes only the given keys (the other extras keys are kept, like
  /// withHighlighterStraightening). Numbers are written as given (double), the dash
  /// pattern as a list of doubles, the tape style as its name.
  core.StrokeStyle withInkExtras({
    double? nibAngleDeg,
    double? nibAspect,
    bool? followBarrelRoll,
    List<double>? dashPattern,
    int? laserFadeMs,
    InkTapeStyle? tapeStyle,
  }) {
    if (nibAngleDeg == null &&
        nibAspect == null &&
        followBarrelRoll == null &&
        dashPattern == null &&
        laserFadeMs == null &&
        tapeStyle == null) {
      return this;
    }
    return copyWith(
      extras: {
        ...extras,
        InkStyleExtras.nibAngleDeg: ?nibAngleDeg,
        InkStyleExtras.nibAspect: ?nibAspect,
        InkStyleExtras.followBarrelRoll: ?followBarrelRoll,
        if (dashPattern != null)
          InkStyleExtras.dash: List<double>.unmodifiable(dashPattern),
        InkStyleExtras.laserFadeMs: ?laserFadeMs,
        if (tapeStyle != null) InkStyleExtras.tapeStyle: tapeStyle.name,
      },
    );
  }
}
