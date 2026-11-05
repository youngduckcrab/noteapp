import 'package:meta/meta.dart';

/// Server commit time of a change chunk (Firestore serverTimestamp), microseconds
/// since epoch, UTC. Web-safe int (< 2^53).
@immutable
final class ServerCursor implements Comparable<ServerCursor> {
  const ServerCursor(this.micros);
  static const ServerCursor zero = ServerCursor(0);
  final int micros;

  /// Largest web-safe integer (2^53 - 1) as decimal text.
  static const String _maxSafeText = '9007199254740991';
  static final RegExp _digits = RegExp(r'^[0-9]+$');

  /// t.toUtc().microsecondsSinceEpoch
  factory ServerCursor.fromDateTime(DateTime t) =>
      ServerCursor(t.toUtc().microsecondsSinceEpoch);

  /// Decimal digits only; throws FormatException.
  factory ServerCursor.parse(String text) {
    if (!_digits.hasMatch(text)) {
      throw FormatException('ServerCursor: decimal digits expected', text);
    }
    final trimmed = text.replaceFirst(RegExp(r'^0+(?=.)'), '');
    if (trimmed.length > _maxSafeText.length ||
        (trimmed.length == _maxSafeText.length &&
            trimmed.compareTo(_maxSafeText) > 0)) {
      throw FormatException('ServerCursor: not below 2^53', text);
    }
    return ServerCursor(int.parse(trimmed));
  }

  static ServerCursor? tryParse(String? text) {
    if (text == null) return null;
    try {
      return ServerCursor.parse(text);
    } on FormatException {
      return null;
    }
  }

  /// Clamped at zero.
  ServerCursor minus(Duration d) {
    final m = micros - d.inMicroseconds;
    return ServerCursor(m < 0 ? 0 : m);
  }

  /// UTC.
  DateTime toDateTime() =>
      DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

  static ServerCursor max(ServerCursor a, ServerCursor b) => a >= b ? a : b;

  @override
  int compareTo(ServerCursor other) => micros.compareTo(other.micros);

  bool operator >(ServerCursor other) => micros > other.micros;
  bool operator <(ServerCursor other) => micros < other.micros;
  bool operator >=(ServerCursor other) => micros >= other.micros;

  @override
  bool operator ==(Object other) =>
      other is ServerCursor && other.micros == micros;

  @override
  int get hashCode => micros.hashCode;

  /// Decimal micros.
  @override
  String toString() => '$micros';
}
