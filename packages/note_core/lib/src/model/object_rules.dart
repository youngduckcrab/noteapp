// Internal (not exported) — the small number rules shared by the 2nd-round page object model
// (m5-7/02-core 6.2.3, 6.2.5, 6.2.7).

/// ARGB with alpha 0xFF, by arithmetic (no bit operations — 1차 7.4.3 web-safe numbers):
/// 0xFF000000 + c % 0x1000000 (CORE 6.2.3).
int opaqueArgb(int argb) => 0xFF000000 + argb % 0x1000000;

/// [value] clamped to [min, max]; NaN → [fallback].
double clampOr(double value, double min, double max, double fallback) =>
    value.isNaN ? fallback : value.clamp(min, max).toDouble();

/// The calligraphy nib angle key of StrokeStyle.extras (C2-38, CORE 6.2.7). INK's
/// InkStyleExtras.nibAngleDeg must be the same string — INK's test compares it with this
/// constant at integration (02-core 8.3 I-1).
const String kCalligraphyNibAngleKey = 'nibAngleDeg';

/// The nib angle of a calligraphy stroke without the key (StrokeStyle.defaultsFor(calligraphy)).
const double kDefaultCalligraphyNibAngleDeg = 45;
