// lib/src/model/pressure_curve.dart — contract 00-overview 7.2.4 / CORE 4.2.1, 6.2.3.
import 'package:meta/meta.dart';

import '../common/json_read.dart';

@immutable
final class PressureCurve {
  // CSS cubic-bezier from (0,0) to (1,1); x = raw pressure
  const PressureCurve({
    this.x1 = 0.25,
    this.y1 = 0.25,
    this.x2 = 0.75,
    this.y2 = 0.75,
  });

  static const PressureCurve linear = PressureCurve();
  static const PressureCurve soft = PressureCurve(
    x1: 0.15,
    y1: 0.45,
    x2: 0.45,
    y2: 0.95,
  );
  static const PressureCurve firm = PressureCurve(
    x1: 0.55,
    y1: 0.05,
    x2: 0.85,
    y2: 0.55,
  );

  final double x1, y1, x2, y2;

  /// CORE 6.2.3: monotonic, evaluate(0)=0, evaluate(1)=1, |err|<1e-6
  double evaluate(double x) {
    final xc = _clamp01(x);
    if (x1 == y1 && x2 == y2) return xc;
    var s = xc;
    for (var i = 0; i < 8; i++) {
      final dx = _derivative(s, x1, x2);
      if (dx.abs() < 1e-6) break;
      s = _clamp01(s - (_bezier(s, x1, x2) - xc) / dx);
    }
    if ((_bezier(s, x1, x2) - xc).abs() > 1e-6) {
      var lo = 0.0;
      var hi = 1.0;
      s = xc;
      for (var i = 0; i < 30; i++) {
        final v = _bezier(s, x1, x2);
        if ((v - xc).abs() <= 1e-6) break;
        if (v < xc) {
          lo = s;
        } else {
          hi = s;
        }
        s = (lo + hi) / 2;
      }
    }
    return _clamp01(_bezier(s, y1, y2));
  }

  static double _clamp01(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);

  // One coordinate of the cubic bezier with P0 = 0 and P3 = 1.
  static double _bezier(double s, double p1, double p2) {
    final u = 1 - s;
    return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s;
  }

  static double _derivative(double s, double p1, double p2) {
    final u = 1 - s;
    return 3 * u * u * p1 + 6 * u * s * (p2 - p1) + 3 * s * s * (1 - p2);
  }

  List<double> toJson() => [x1, y1, x2, y2];

  factory PressureCurve.fromJson(List<Object?> json) {
    if (json.length != 4) {
      throw FormatException(
        'pressureCurve needs 4 numbers, got ${json.length}',
      );
    }
    return PressureCurve(
      x1: asDouble(json[0], 'pressureCurve'),
      y1: asDouble(json[1], 'pressureCurve'),
      x2: asDouble(json[2], 'pressureCurve'),
      y2: asDouble(json[3], 'pressureCurve'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PressureCurve &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);

  @override
  String toString() => 'PressureCurve($x1, $y1, $x2, $y2)';
}
