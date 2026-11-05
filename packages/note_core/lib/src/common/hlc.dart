// lib/src/common/hlc.dart — contract 00-overview 7.2.2 / CORE 4.1, rules 6.4.
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

/// Hybrid logical clock value. Text form is fixed-width and sorts
/// lexicographically in the same order as compareTo:
/// '001793750400000-0000-3f2a9c0d11e0b7a4' (15-digit millis, 4-hex counter, 16-hex node).
@immutable
final class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.nodeId);

  static const Hlc zero = Hlc(0, 0, '0000000000000000');
  static const int maxCounter = 0xFFFF;

  /// Largest millis value the fixed-width text form can hold.
  static const int _maxMillis = 999999999999999;

  final int millis; // 0..999999999999999
  final int counter; // 0..0xFFFF
  final String nodeId; // 16 lowercase hex chars

  static final RegExp _pattern = RegExp(
    r'^([0-9]{15})-([0-9a-f]{4})-([0-9a-f]{16})$',
  );

  /// Throws FormatException.
  factory Hlc.parse(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) throw FormatException('Invalid HLC text', text);
    return Hlc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!, radix: 16),
      m.group(3)!,
    );
  }

  static Hlc? tryParse(String? text) {
    if (text == null) return null;
    try {
      return Hlc.parse(text);
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() =>
      '${millis.toString().padLeft(15, '0')}-'
      '${counter.toRadixString(16).padLeft(4, '0')}-$nodeId';

  /// Millis, then counter, then nodeId.
  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis < other.millis ? -1 : 1;
    if (counter != other.counter) return counter < other.counter ? -1 : 1;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(millis, counter, nodeId);
}

final class HlcClock {
  HlcClock({
    required this.nodeId,
    this._clock = const Clock(),
    Hlc? last,
    this.maxForwardDrift = const Duration(hours: 24),
  }) : _last = last ?? Hlc(0, 0, nodeId);

  final String nodeId;
  final Duration maxForwardDrift;
  final Clock _clock;
  Hlc _last;

  Hlc get last => _last;

  int get _wall => _clock.now().millisecondsSinceEpoch;

  /// Local event. Strictly greater than every value returned or received before.
  Hlc now() {
    final wall = _wall;
    final l = _last;
    if (wall > l.millis) {
      _last = Hlc(_cap(wall), 0, nodeId);
    } else {
      _last = _bump(l.millis, l.counter + 1);
    }
    return _last;
  }

  /// Merge a remote value (6.4). Remote values further than [maxForwardDrift]
  /// ahead of the wall clock do not advance the local clock.
  Hlc receive(Hlc remote) {
    final wall = _wall;
    if (remote.millis > wall + maxForwardDrift.inMilliseconds) return _last;
    final l = _last;
    final m = max(wall, max(l.millis, remote.millis));
    final int c;
    if (m == l.millis && m == remote.millis) {
      c = max(l.counter, remote.counter) + 1;
    } else if (m == l.millis) {
      c = l.counter + 1;
    } else if (m == remote.millis) {
      c = remote.counter + 1;
    } else {
      c = 0;
    }
    _last = _bump(m, c);
    return _last;
  }

  Hlc _bump(int millis, int counter) => counter > Hlc.maxCounter
      ? Hlc(_cap(millis + 1), 0, nodeId)
      : Hlc(millis, counter, nodeId);

  static int _cap(int millis) =>
      millis > Hlc._maxMillis ? Hlc._maxMillis : millis;
}

/// 16 lowercase hex chars from a secure random source.
String generateNodeId([Random? random]) {
  final r = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 8; i++) {
    buffer.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
