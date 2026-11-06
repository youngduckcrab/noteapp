// Value types of pencil_bridge (contract 00-overview 7.2.13, docs/plans/m5-7/
// 01-infra.md 4.4.2): == / hashCode / toString on all of them.
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// One Apple Pencil event. [timestamp] is the native event time
/// (`ProcessInfo.systemUptime` on iOS — a monotonic clock, not wall time).
sealed class PencilEvent {
  const PencilEvent(this.timestamp);
  final Duration timestamp;
}

/// Double tap on the pencil (Apple Pencil 2 / Pro).
final class PencilTap extends PencilEvent {
  const PencilTap(
    super.timestamp, {
    required this.preferredAction,
    this.position,
    this.z,
  });

  /// Wire name of `UIPencilPreferredAction` (01-infra 4.4.3) — kept as the
  /// string iOS sent, unknown names included.
  final String preferredAction;

  /// Global logical px; iOS 17.5+ hover pose only.
  final Offset? position;

  /// Hover height 0..1 (`zOffset`).
  final double? z;

  @override
  bool operator ==(Object other) =>
      other is PencilTap &&
      other.timestamp == timestamp &&
      other.preferredAction == preferredAction &&
      other.position == position &&
      other.z == z;

  @override
  int get hashCode =>
      Object.hash(PencilTap, timestamp, preferredAction, position, z);

  @override
  String toString() =>
      'PencilTap($timestamp, preferredAction: $preferredAction, '
      'position: $position, z: $z)';
}

/// Squeeze on Apple Pencil Pro (iOS 17.5+).
final class PencilSqueeze extends PencilEvent {
  const PencilSqueeze(
    super.timestamp, {
    required this.phase,
    required this.preferredAction,
    this.position,
    this.z,
    this.roll,
  });

  /// began | changed | ended | cancelled (unknown names kept as sent).
  final String phase;
  final String preferredAction;
  final Offset? position;
  final double? z, roll;

  @override
  bool operator ==(Object other) =>
      other is PencilSqueeze &&
      other.timestamp == timestamp &&
      other.phase == phase &&
      other.preferredAction == preferredAction &&
      other.position == position &&
      other.z == z &&
      other.roll == roll;

  @override
  int get hashCode => Object.hash(
    PencilSqueeze,
    timestamp,
    phase,
    preferredAction,
    position,
    z,
    roll,
  );

  @override
  String toString() =>
      'PencilSqueeze($timestamp, phase: $phase, '
      'preferredAction: $preferredAction, position: $position, z: $z, '
      'roll: $roll)';
}

/// Pencil hovering over the screen (iPadOS 16.1+ hover-capable iPads).
final class PencilHover extends PencilEvent {
  const PencilHover(
    super.timestamp, {
    required this.position,
    this.z,
    this.altitude,
    this.azimuth,
    this.roll,
  });

  /// Global logical px.
  final Offset position;

  /// z: 0..1; altitude, azimuth, roll: rad.
  final double? z, altitude, azimuth, roll;

  @override
  bool operator ==(Object other) =>
      other is PencilHover &&
      other.timestamp == timestamp &&
      other.position == position &&
      other.z == z &&
      other.altitude == altitude &&
      other.azimuth == azimuth &&
      other.roll == roll;

  @override
  int get hashCode =>
      Object.hash(PencilHover, timestamp, position, z, altitude, azimuth, roll);

  @override
  String toString() =>
      'PencilHover($timestamp, position: $position, z: $z, '
      'altitude: $altitude, azimuth: $azimuth, roll: $roll)';
}

/// Barrel roll while drawing (Apple Pencil Pro, iOS 17.5+), ≤ 60 Hz.
final class PencilRoll extends PencilEvent {
  const PencilRoll(super.timestamp, {required this.angle});

  /// rad, `UITouch.rollAngle` while drawing.
  final double angle;

  @override
  bool operator ==(Object other) =>
      other is PencilRoll &&
      other.timestamp == timestamp &&
      other.angle == angle;

  @override
  int get hashCode => Object.hash(PencilRoll, timestamp, angle);

  @override
  String toString() => 'PencilRoll($timestamp, angle: $angle)';
}

/// What the device reports (iOS method 'capabilities'). `squeeze` and `roll`
/// are OS availability (iPadOS 17.5+), not the pencil model (CD2-24).
@immutable
final class PencilCapabilities {
  const PencilCapabilities({
    required this.os,
    this.squeeze = false,
    this.hover = false,
    this.roll = false,
    this.prefersPencilOnlyDrawing = false,
    this.preferredTapAction = 'unknown',
    this.preferredSqueezeAction = 'unknown',
  });

  /// Decodes the 'capabilities' method result; missing keys keep the defaults.
  ///
  /// A value of the wrong type counts as missing. `os` defaults to ''.
  factory PencilCapabilities.fromWire(Map<Object?, Object?> map) {
    bool flag(String key) => switch (map[key]) {
      final bool value => value,
      _ => false,
    };
    String text(String key, String fallback) => switch (map[key]) {
      final String value => value,
      _ => fallback,
    };
    return PencilCapabilities(
      os: text('os', ''),
      squeeze: flag('squeeze'),
      hover: flag('hover'),
      roll: flag('roll'),
      prefersPencilOnlyDrawing: flag('prefersPencilOnlyDrawing'),
      preferredTapAction: text('preferredTapAction', 'unknown'),
      preferredSqueezeAction: text('preferredSqueezeAction', 'unknown'),
    );
  }

  static const PencilCapabilities unsupported = PencilCapabilities(os: '');

  /// `UIDevice.systemVersion`, '' when unsupported.
  final String os;
  final bool squeeze, hover, roll, prefersPencilOnlyDrawing;
  final String preferredTapAction, preferredSqueezeAction;

  @override
  bool operator ==(Object other) =>
      other is PencilCapabilities &&
      other.os == os &&
      other.squeeze == squeeze &&
      other.hover == hover &&
      other.roll == roll &&
      other.prefersPencilOnlyDrawing == prefersPencilOnlyDrawing &&
      other.preferredTapAction == preferredTapAction &&
      other.preferredSqueezeAction == preferredSqueezeAction;

  @override
  int get hashCode => Object.hash(
    os,
    squeeze,
    hover,
    roll,
    prefersPencilOnlyDrawing,
    preferredTapAction,
    preferredSqueezeAction,
  );

  @override
  String toString() =>
      'PencilCapabilities(os: $os, squeeze: $squeeze, hover: $hover, '
      'roll: $roll, prefersPencilOnlyDrawing: $prefersPencilOnlyDrawing, '
      'preferredTapAction: $preferredTapAction, '
      'preferredSqueezeAction: $preferredSqueezeAction)';
}
