import 'package:meta/meta.dart';

/// Server commit time of a change chunk (Firestore serverTimestamp), microseconds
/// since epoch, UTC. Web-safe int (< 2^53).
@immutable
final class ServerCursor implements Comparable<ServerCursor> {
  const ServerCursor(this.micros);
  static const ServerCursor zero = ServerCursor(0);
  final int micros;

  /// t.toUtc().microsecondsSinceEpoch
  factory ServerCursor.fromDateTime(DateTime t) =>
      throw UnimplementedError('SYNC T2');

  /// Decimal digits only; throws FormatException.
  factory ServerCursor.parse(String text) =>
      throw UnimplementedError('SYNC T2');

  static ServerCursor? tryParse(String? text) =>
      throw UnimplementedError('SYNC T2');

  /// Clamped at zero.
  ServerCursor minus(Duration d) => throw UnimplementedError('SYNC T2');

  /// UTC.
  DateTime toDateTime() => throw UnimplementedError('SYNC T2');

  static ServerCursor max(ServerCursor a, ServerCursor b) =>
      throw UnimplementedError('SYNC T2');

  @override
  int compareTo(ServerCursor other) => throw UnimplementedError('SYNC T2');

  bool operator >(ServerCursor other) => throw UnimplementedError('SYNC T2');
  bool operator <(ServerCursor other) => throw UnimplementedError('SYNC T2');
  bool operator >=(ServerCursor other) => throw UnimplementedError('SYNC T2');

  /// Decimal micros.
  @override
  String toString() => throw UnimplementedError('SYNC T2');
}
