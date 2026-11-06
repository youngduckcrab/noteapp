// lib/src/model/math_types.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.2, 6.11). Final since the 2차 foundation step R2-B6.
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'handwriting_trace.dart';

final class MathInput {
  const MathInput({required this.traces, this.png, this.pngPxPerPt});

  final List<HandwritingTrace> traces;
  final Uint8List? png;
  final double? pngPxPerPt;

  @override
  String toString() =>
      'MathInput(${traces.length} traces, png: ${png?.length ?? '-'} B)';
}

@immutable
final class MathResult {
  const MathResult({
    required this.latex,
    this.confidence,
    this.alternatives = const [],
    required this.engineId,
    required this.latency,
  });

  final String latex;
  final double? confidence;
  final List<String> alternatives;
  final String engineId;
  final Duration latency;

  static const ListEquality<String> _listEquality = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is MathResult &&
      other.latex == latex &&
      other.confidence == confidence &&
      _listEquality.equals(other.alternatives, alternatives) &&
      other.engineId == engineId &&
      other.latency == latency;

  @override
  int get hashCode => Object.hash(
    latex,
    confidence,
    _listEquality.hash(alternatives),
    engineId,
    latency,
  );

  @override
  String toString() =>
      'MathResult($latex, ${confidence ?? '-'}, $alternatives, $engineId, '
      '${latency.inMilliseconds} ms)';
}
